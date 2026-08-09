//
//  ReplaySource.kt
//  MoniVitals (Android)
//
//  Replays a REAL recorded biosignal (PhysioNet BIDMC: ECG lead II + PPG) bundled with
//  the app, so the DSP computes heart rate and pulse-arrival-time from genuine waveforms
//  instead of a self-encoding synthetic signal. The recording loops seamlessly with
//  monotonically increasing device timestamps.
//
//  Notes on fidelity:
//   • ECG + PPG are the real recording.
//   • The dataset has single-wavelength PPG, so red/IR are synthesized from the real PPG
//     shape at the AC ratio implied by the recording's own SpO2 reading — the SpO2 tile
//     therefore reflects the RECORDED reference value, and is labeled as such.
//   • Bioimpedance has no open real counterpart, so a light synthetic ΔZ drives the
//     contact/movement indicators (clearly a simulated channel).
//
//  Ported from ios/MoniVitals/Source/ReplaySource.swift — mirrors its logic exactly.
//  Uses the same single-thread ScheduledExecutorService serial-queue as MockSource, and
//  elapsed time uses the monotonic clock (nanoTime); clock offset uses wall time.
//
//  MoniVitals is a research / educational tool, NOT a medical device.
//

package com.monivitals.source

import android.content.Context
import com.monivitals.ble.BLEProtocol
import com.monivitals.ble.BiozPacket
import com.monivitals.ble.EcgPacket
import com.monivitals.ble.InfoMessage
import com.monivitals.ble.MetricsPacket
import com.monivitals.ble.PpgPacket
import com.monivitals.ble.StatusMessage
import com.monivitals.ble.StreamKind
import com.monivitals.dsp.DSPConstants
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sin

/** The bundled recording (see assets/bidmc_sample.json, produced from PhysioNet BIDMC). */
@Serializable
private data class Recording(
    val source: String,
    val fs: Int,
    val refHR: Double,
    val refSpO2: Double,
    val spo2Ratio: Double,
    val ppgMean: Double,
    val ecg: List<Double>,
    val ppg: List<Double>,
)

private const val REPLAY_TICK_MS = 40L
private const val REPLAY_METRICS_MS = 500L

class ReplaySource(context: Context) : BaseDataSource() {
    override val isMock: Boolean get() = true

    private var _clockOffsetUs: Double? = null
    override val clockOffsetUs: Double? get() = _clockOffsetUs

    private val rec: Recording = run {
        val raw = context.assets.open("bidmc_sample.json").bufferedReader().use { it.readText() }
        Json { ignoreUnknownKeys = true }.decodeFromString(Recording.serializer(), raw)
    }

    private val fs: Int = rec.fs
    private val n: Int = rec.ecg.size
    private val ppgDc = 120_000.0
    private val ppgGain = 100_000.0

    /** Recorded reference values (for display as ground-truth comparison). */
    val referenceHR: Double = rec.refHR
    val referenceSpO2: Double = rec.refSpO2
    val recordingName: String = rec.source

    override val deviceName: String? get() = rec.source

    private var emitted = 0 // total ECG/PPG samples emitted (monotonic)
    @Volatile private var running = false
    private var startNanos = 0L
    private var seqEcg = 0
    private var seqPpg = 0
    private var seqBioz = 0
    private var batteryPct = 100.0

    private val exec = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "monivitals-replay") }
    private var tickTimer: ScheduledFuture<*>? = null
    private var metricsTimer: ScheduledFuture<*>? = null
    private var statusTimer: ScheduledFuture<*>? = null

    // MARK: - Lifecycle

    override fun connect() {
        setState(ConnectionState.CONNECTING)
        exec.schedule({
            setState(ConnectionState.CONNECTED)
            startNanos = System.nanoTime()
            emitInfo()
            statusTimer = exec.scheduleAtFixedRate({ emitStatus() }, 1000, 1000, TimeUnit.MILLISECONDS)
        }, 100, TimeUnit.MILLISECONDS)
    }

    override fun disconnect() {
        stop()
        statusTimer?.cancel(false)
        statusTimer = null
        setState(ConnectionState.DISCONNECTED)
    }

    override fun start(streamMask: Int) {
        exec.execute {
            emitted = 0
            seqEcg = 0
            seqPpg = 0
            seqBioz = 0
            startNanos = System.nanoTime()
            running = true
            tickTimer = exec.scheduleAtFixedRate({ tick() }, REPLAY_TICK_MS, REPLAY_TICK_MS, TimeUnit.MILLISECONDS)
            metricsTimer = exec.scheduleAtFixedRate({ emitMetrics() }, REPLAY_METRICS_MS, REPLAY_METRICS_MS, TimeUnit.MILLISECONDS)
        }
    }

    override fun stop() {
        exec.execute {
            running = false
            tickTimer?.cancel(false)
            metricsTimer?.cancel(false)
            tickTimer = null
            metricsTimer = null
        }
    }

    override fun syncClock() {
        exec.schedule({
            _clockOffsetUs = System.currentTimeMillis() * 1000.0 - deviceUs(emitted)
        }, 20, TimeUnit.MILLISECONDS)
    }

    override fun getInfo() {
        exec.execute { emitInfo() }
    }

    // MARK: - Emission

    private fun tick() {
        if (!running) return
        val elapsed = (System.nanoTime() - startNanos) / 1e9
        val target = (elapsed * fs).toInt() // total samples that should exist by now
        if (target <= emitted) return
        val count = target - emitted
        val firstTus = deviceUs(emitted)

        val ecg = IntArray(count)
        val green = LongArray(count)
        val red = LongArray(count)
        val ir = LongArray(count)
        val dz = IntArray(count)

        for (i in 0 until count) {
            val s = emitted + i
            val j = s % n // loop the recording
            ecg[i] = rec.ecg[j].roundToInt()
            val ac = (rec.ppg[j] - rec.ppgMean) * ppgGain // real PPG AC
            green[i] = maxOf(0L, (ppgDc + ac).roundToLong())
            ir[i] = maxOf(0L, (ppgDc + ac).roundToLong()) // IR AC == green AC
            red[i] = maxOf(0L, (ppgDc + ac * rec.spo2Ratio).roundToLong()) // red AC scaled → SpO2 ref
            // Light synthetic bioimpedance ΔZ (pulsatile at the recorded HR) + tiny noise.
            val tSec = s.toDouble() / fs
            dz[i] = (400.0 * sin(2 * PI * (rec.refHR / 60.0) * tSec) + 40.0 * sin(tSec * 53.7)).roundToInt()
        }

        events.ecg.tryEmit(EcgPacket(seq = seqEcg, tUs = firstTus, sampleRateHz = fs, samples = ecg))
        events.ppg.tryEmit(PpgPacket(seq = seqPpg, tUs = firstTus, sampleRateHz = fs, green = green, red = red, ir = ir))
        events.bioz.tryEmit(BiozPacket(seq = seqBioz, tUs = firstTus, sampleRateHz = fs, z0Milliohm = 300_000, dz = dz))
        seqEcg = (seqEcg + 1) and 0xffff
        seqPpg = (seqPpg + 1) and 0xffff
        seqBioz = (seqBioz + 1) and 0xffff
        emitted = target
    }

    private fun emitMetrics() {
        if (!running) return
        // Firmware/reference metrics: the recording's own HR + SpO2 readings.
        events.metrics.tryEmit(
            MetricsPacket(
                tUs = deviceUs(emitted),
                hrBpm = rec.refHR,
                spo2Pct = rec.refSpO2,
                contactQuality = 100,
                motion = 0,
                patUs = null,
                sbpMmHg = null,
                dbpMmHg = null,
                rpeak = false,
            )
        )
    }

    private fun emitInfo() {
        events.info.tryEmit(
            InfoMessage(
                firmwareVersion = "bidmc-replay",
                deviceId = "bidmc00000001",
                capabilities = BLEProtocol.streamBit(StreamKind.ECG) or
                    BLEProtocol.streamBit(StreamKind.BIOZ) or
                    BLEProtocol.streamBit(StreamKind.PPG),
            )
        )
        events.battery.tryEmit(batteryPct.toInt())
    }

    private fun emitStatus() {
        events.battery.tryEmit(batteryPct.toInt())
        events.status.tryEmit(
            StatusMessage(
                streamingMask = if (running) BLEProtocol.allStreamsMask else 0,
                ecgRateCode = 1,
                biozRateCode = 1,
                ppgRateCode = 1,
                tUs = deviceUs(emitted),
                batteryPct = batteryPct.toInt(),
                errorFlags = 0,
            )
        )
    }

    private fun deviceUs(sampleIndex: Int): Double =
        (sampleIndex.toDouble() * DSPConstants.usPerS / fs).roundToLong().toDouble()
}
