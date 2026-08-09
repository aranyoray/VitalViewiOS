//
//  RingBuffer.kt
//  MoniVitals (Android)
//
//  Fixed-capacity ring buffer of (deviceTimeUs, value) points for live waveform
//  rendering. Mutated at full sample rate by the packet handlers and read by the Compose
//  Canvas on a frame tick — never via reactive state, so the UI is not recomposed per
//  sample.
//
//  Ported from ios/MoniVitals/Views/RingBuffer.kt (== web WaveBuffer). Reads/writes are
//  guarded by a lock since packets may arrive on a background thread while the Canvas
//  reads on the main thread.
//

package com.monivitals.ui

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

class WaveBuffer(val capacity: Int) {
    private val ts = DoubleArray(capacity)
    private val vs = DoubleArray(capacity)
    private var head = 0
    private var filled = 0
    private val lock = ReentrantLock()

    fun push(t: Double, v: Double) = lock.withLock {
        ts[head] = t
        vs[head] = v
        head = (head + 1) % capacity
        if (filled < capacity) filled += 1
    }

    val length: Int get() = lock.withLock { filled }

    fun latestT(): Double? = lock.withLock {
        if (filled == 0) null else ts[(head - 1 + capacity) % capacity]
    }

    /** Points with timestamp ≥ tFrom, in chronological order. */
    fun window(tFrom: Double): Pair<DoubleArray, DoubleArray> = lock.withLock {
        val t = ArrayList<Double>(filled)
        val v = ArrayList<Double>(filled)
        for (i in 0 until filled) {
            val idx = (head - filled + i + capacity * 2) % capacity
            if (ts[idx] >= tFrom) {
                t.add(ts[idx])
                v.add(vs[idx])
            }
        }
        Pair(t.toDoubleArray(), v.toDoubleArray())
    }

    fun clear() = lock.withLock {
        head = 0
        filled = 0
    }
}

/** The non-reactive set of waveform ring buffers, mirroring the web live runtime. */
class WaveBuffers {
    val ecg = WaveBuffer(4096)
    val ppgGreen = WaveBuffer(8192)
    val ppgRed = WaveBuffer(8192)
    val ppgIr = WaveBuffer(8192)
    val biozDz = WaveBuffer(2048)
    val z0 = WaveBuffer(1024)

    fun clear() {
        ecg.clear(); ppgGreen.clear(); ppgRed.clear(); ppgIr.clear(); biozDz.clear(); z0.clear()
    }

    /** Latest device timestamp across the high-rate streams. */
    fun latestDeviceUs(): Double =
        maxOf(ecg.latestT() ?: 0.0, ppgGreen.latestT() ?: 0.0, biozDz.latestT() ?: 0.0)
}
