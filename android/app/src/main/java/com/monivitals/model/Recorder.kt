//
//  Recorder.kt
//  MoniVitals (Android)
//
//  Buffers live samples and flushes them to the store in ~2 s chunks. One instance per
//  active recording session. Robust to mid-stream disconnects (flush on stop).
//  Mirrors the iOS Recorder (ios/MoniVitals/Model/Store.swift) / web Recorder.
//

package com.monivitals.model

import com.monivitals.ble.BiozPacket
import com.monivitals.ble.EcgPacket
import com.monivitals.ble.PpgPacket
import com.monivitals.ble.StreamKind
import com.monivitals.dsp.DSPConstants
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.roundToLong

class Recorder(val sessionId: String, private val store: Store = Store.shared) {
    val counts: MutableMap<StreamKind, Int> = mutableMapOf(
        StreamKind.ECG to 0, StreamKind.BIOZ to 0, StreamKind.PPG to 0,
    )

    // Chunk file writes are O(existing file size) and grow over a session, so they run on a
    // dedicated background thread — never on the caller (main) thread. Buffers are swapped
    // before the write is submitted, so the submitted chunk is an immutable snapshot.
    private val io = Executors.newSingleThreadExecutor { r -> Thread(r, "monivitals-recorder-io") }

    private class BufferState {
        var tStartUs: Double? = null
        var rate = 0
        val t = mutableListOf<Double>()
        val a = mutableListOf<Double>() // ecg samples | z0 | green
        val b = mutableListOf<Double>() // dz | red
        val c = mutableListOf<Double>() // ir
    }

    private val buffers: MutableMap<StreamKind, BufferState> = mutableMapOf(
        StreamKind.ECG to BufferState(),
        StreamKind.BIOZ to BufferState(),
        StreamKind.PPG to BufferState(),
    )
    private val flushSamples = mapOf(StreamKind.ECG to 512, StreamKind.BIOZ to 128, StreamKind.PPG to 800)

    fun ingestEcg(p: EcgPacket) {
        val buf = buffers[StreamKind.ECG]!!
        if (buf.tStartUs == null) buf.tStartUs = p.tUs
        buf.rate = p.sampleRateHz
        val dt = DSPConstants.usPerS / p.sampleRateHz
        for (i in p.samples.indices) {
            buf.t.add(p.tUs + (i * dt).roundToLong())
            buf.a.add(p.samples[i].toDouble())
        }
        counts[StreamKind.ECG] = (counts[StreamKind.ECG] ?: 0) + p.samples.size
        if (buf.a.size >= flushSamples[StreamKind.ECG]!!) flush(StreamKind.ECG)
    }

    fun ingestBioz(p: BiozPacket) {
        val buf = buffers[StreamKind.BIOZ]!!
        if (buf.tStartUs == null) buf.tStartUs = p.tUs
        buf.rate = p.sampleRateHz
        val dt = DSPConstants.usPerS / p.sampleRateHz
        for (i in p.dz.indices) {
            buf.t.add(p.tUs + (i * dt).roundToLong())
            buf.a.add(p.z0Milliohm.toDouble()) // forward-filled z0
            buf.b.add(p.dz[i].toDouble())
        }
        counts[StreamKind.BIOZ] = (counts[StreamKind.BIOZ] ?: 0) + p.dz.size
        if (buf.a.size >= flushSamples[StreamKind.BIOZ]!!) flush(StreamKind.BIOZ)
    }

    fun ingestPpg(p: PpgPacket) {
        val buf = buffers[StreamKind.PPG]!!
        if (buf.tStartUs == null) buf.tStartUs = p.tUs
        buf.rate = p.sampleRateHz
        val dt = DSPConstants.usPerS / p.sampleRateHz
        for (i in p.green.indices) {
            buf.t.add(p.tUs + (i * dt).roundToLong())
            buf.a.add(p.green[i].toDouble())
            buf.b.add(p.red[i].toDouble())
            buf.c.add(p.ir[i].toDouble())
        }
        counts[StreamKind.PPG] = (counts[StreamKind.PPG] ?: 0) + p.green.size
        if (buf.a.size >= flushSamples[StreamKind.PPG]!!) flush(StreamKind.PPG)
    }

    /** Persist buffered samples for one stream as a StreamChunk. */
    fun flush(stream: StreamKind) {
        val buf = buffers[stream]!!
        val tStart = buf.tStartUs
        if (buf.a.isEmpty() || tStart == null) return
        var chunk = StreamChunk(
            id = null, sessionId = sessionId, stream = stream,
            tStartUs = tStart, sampleRateHz = buf.rate, t = buf.t.toList(),
        )
        chunk = when (stream) {
            StreamKind.ECG -> chunk.copy(ecg = buf.a.map { it.toInt() })
            StreamKind.BIOZ -> chunk.copy(z0 = buf.a.map { it.toInt() }, dz = buf.b.map { it.toInt() })
            StreamKind.PPG -> chunk.copy(
                green = buf.a.map { it.toLong() },
                red = buf.b.map { it.toLong() },
                ir = buf.c.map { it.toLong() },
            )
        }
        buffers[stream] = BufferState()
        io.execute { store.addChunk(chunk) }
    }

    fun flushAll() {
        for (s in StreamKind.allCases) flush(s)
    }

    /** Flush remaining buffers and block until all queued writes are persisted. */
    fun finish() {
        flushAll()
        io.shutdown()
        try {
            io.awaitTermination(3, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
}
