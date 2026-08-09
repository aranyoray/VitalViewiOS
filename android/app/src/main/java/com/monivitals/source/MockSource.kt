//
//  MockSource.kt
//  MoniVitals (Android)
//
//  Synthetic data source: drives realistic packets on timers with no hardware, so the
//  entire app — dashboard, recording, calibration, gating, export — is demoable. Emits
//  typed packets with already-monotonic device timestamps.
//
//  Ported from ios/MoniVitals/Source/MockSource.swift (== web/src/source/MockSource.ts).
//  Uses a single-thread ScheduledExecutorService (the serial-queue + DispatchSourceTimer
//  equivalent); elapsed time uses a monotonic clock (nanoTime) and the clock offset uses
//  wall time, mirroring the web's performance.now()/Date.now() split.
//

package com.monivitals.source

import com.monivitals.ble.BLEProtocol
import com.monivitals.ble.BiozPacket
import com.monivitals.ble.EcgPacket
import com.monivitals.ble.InfoMessage
import com.monivitals.ble.MetricsPacket
import com.monivitals.ble.PpgPacket
import com.monivitals.ble.StatusMessage
import com.monivitals.ble.StreamKind
import com.monivitals.dsp.ContactMotionEstimator
import com.monivitals.dsp.DSPConstants
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt
import kotlin.math.roundToLong

private const val TICK_MS = 40L
private const val METRICS_MS = 500L

private class StreamState(var rateHz: Int, var k: Int) {
    var nextIndex: Int = 0
    var seq: Int = 0
}

class MockSource(params: MockParams = MockParams.default) : BaseDataSource() {
    override val isMock: Boolean get() = true

    private var _clockOffsetUs: Double? = null
    override val clockOffsetUs: Double? get() = _clockOffsetUs

    override val deviceName: String? get() = "MoniVitals Mock"

    private val signal = MockSignal(params)
    private val streams: Map<StreamKind, StreamState> = mapOf(
        StreamKind.ECG to StreamState(BLEProtocol.defaultRateHz(StreamKind.ECG), BLEProtocol.defaultK(StreamKind.ECG)),
        StreamKind.BIOZ to StreamState(BLEProtocol.defaultRateHz(StreamKind.BIOZ), BLEProtocol.defaultK(StreamKind.BIOZ)),
        StreamKind.PPG to StreamState(BLEProtocol.defaultRateHz(StreamKind.PPG), BLEProtocol.defaultK(StreamKind.PPG)),
    )
    private var enabledMask = 0
    @Volatile private var running = false
    private var startNanos = 0L
    private var batteryPct = 100.0
    private var lastMetricsDeviceUs = 0.0
    private val contact = ContactMotionEstimator(params.biozRateHz.toDouble())
    private val exec = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "monivitals-mock") }

    // Guards every access to `signal.p` (its fields and the motionBursts list). The executor
    // thread reads it in tick()/emitMetrics(); the UI thread mutates/reads it via
    // setParams()/injectMotion()/getParams(). Without this the motionBursts iteration in
    // MockSignal.dzAt() can throw ConcurrentModificationException.
    private val paramsLock = Any()

    private var tickTimer: ScheduledFuture<*>? = null
    private var metricsTimer: ScheduledFuture<*>? = null
    private var statusTimer: ScheduledFuture<*>? = null

    /** Live-adjust the synthetic signal (HR/PAT/SpO2/etc.) from Settings. */
    fun setParams(mutate: (MockParams) -> Unit) {
        synchronized(paramsLock) { mutate(signal.p) }
    }

    fun getParams(): MockParams = synchronized(paramsLock) { signal.p.copy() }

    /** Inject a motion burst now (drives the motion/gating demo). */
    fun injectMotion(durationMs: Double = 2000.0, severity: Double = 4.0) {
        synchronized(paramsLock) {
            val now = deviceNowUs()
            signal.p.motionBursts.add(MotionBurst(now, now + durationMs * 1000, severity))
        }
    }

    override fun connect() {
        setState(ConnectionState.CONNECTING)
        exec.schedule({
            setState(ConnectionState.CONNECTED)
            startNanos = System.nanoTime()
            emitInfo()
            statusTimer = exec.scheduleAtFixedRate({ emitStatus() }, 1000, 1000, TimeUnit.MILLISECONDS)
        }, 150, TimeUnit.MILLISECONDS)
    }

    override fun disconnect() {
        stop()
        statusTimer?.cancel(false)
        statusTimer = null
        setState(ConnectionState.DISCONNECTED)
    }

    override fun start(streamMask: Int) {
        exec.execute {
            enabledMask = streamMask
            startNanos = System.nanoTime()
            lastMetricsDeviceUs = 0.0
            for (s in streams.values) {
                s.nextIndex = 0
                s.seq = 0
            }
            contact.reset()
            running = true
            tickTimer = exec.scheduleAtFixedRate({ tick() }, TICK_MS, TICK_MS, TimeUnit.MILLISECONDS)
            metricsTimer = exec.scheduleAtFixedRate({ emitMetrics() }, METRICS_MS, METRICS_MS, TimeUnit.MILLISECONDS)
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

    override fun setRate(stream: StreamKind, hz: Int) {
        exec.execute {
            val s = streams[stream] ?: return@execute
            s.rateHz = hz
            if (running) s.nextIndex = (elapsedS() * hz).toInt()
            when (stream) {
                StreamKind.BIOZ -> signal.p.biozRateHz = hz
                StreamKind.ECG -> signal.p.ecgRateHz = hz
                StreamKind.PPG -> signal.p.ppgRateHz = hz
            }
        }
    }

    override fun syncClock() {
        exec.schedule({
            val deviceTus = deviceNowUs()
            _clockOffsetUs = System.currentTimeMillis() * 1000.0 - deviceTus
        }, 20, TimeUnit.MILLISECONDS)
    }

    override fun getInfo() {
        exec.execute { emitInfo() }
    }

    // MARK: - internals

    private fun emitInfo() {
        events.info.tryEmit(
            InfoMessage(
                firmwareVersion = "1.0.0-mock",
                deviceId = "mock00000001",
                capabilities = BLEProtocol.streamBit(StreamKind.ECG) or
                    BLEProtocol.streamBit(StreamKind.BIOZ) or
                    BLEProtocol.streamBit(StreamKind.PPG),
            )
        )
        events.battery.tryEmit(batteryPct.toInt())
    }

    private fun elapsedS(): Double = (System.nanoTime() - startNanos) / 1e9

    private fun deviceNowUs(): Double = (elapsedS() * DSPConstants.usPerS).roundToLong().toDouble()

    private fun tick() {
        if (!running) return
        val elapsed = elapsedS()
        synchronized(paramsLock) {
            if (enabledMask and BLEProtocol.streamBit(StreamKind.ECG) != 0) tickEcg(elapsed)
            if (enabledMask and BLEProtocol.streamBit(StreamKind.BIOZ) != 0) tickBioz(elapsed)
            if (enabledMask and BLEProtocol.streamBit(StreamKind.PPG) != 0) tickPpg(elapsed)
        }
    }

    private fun tickEcg(elapsedS: Double) {
        val s = streams[StreamKind.ECG] ?: return
        val target = (elapsedS * s.rateHz).toInt()
        while (s.nextIndex < target) {
            val count = minOf(s.k, target - s.nextIndex)
            val first = s.nextIndex
            val tUs = (first.toDouble() * DSPConstants.usPerS / s.rateHz).roundToLong().toDouble()
            val samples = IntArray(count)
            for (i in 0 until count) {
                val t = ((first + i).toDouble() * DSPConstants.usPerS / s.rateHz).roundToLong().toDouble()
                samples[i] = signal.ecgAt(t).roundToInt()
            }
            events.ecg.tryEmit(EcgPacket(seq = s.seq, tUs = tUs, sampleRateHz = s.rateHz, samples = samples))
            s.nextIndex += count
            s.seq = (s.seq + 1) and 0xffff
        }
    }

    private fun tickBioz(elapsedS: Double) {
        val s = streams[StreamKind.BIOZ] ?: return
        val target = (elapsedS * s.rateHz).toInt()
        while (s.nextIndex < target) {
            val count = minOf(s.k, target - s.nextIndex)
            val first = s.nextIndex
            val tUs = (first.toDouble() * DSPConstants.usPerS / s.rateHz).roundToLong().toDouble()
            val z0 = signal.z0At(tUs).roundToInt()
            val dz = IntArray(count)
            for (i in 0 until count) {
                val t = ((first + i).toDouble() * DSPConstants.usPerS / s.rateHz).roundToLong().toDouble()
                dz[i] = signal.dzAt(t).roundToInt()
                contact.pushDz(dz[i].toDouble())
            }
            contact.pushZ0(z0.toDouble())
            events.bioz.tryEmit(BiozPacket(seq = s.seq, tUs = tUs, sampleRateHz = s.rateHz, z0Milliohm = z0, dz = dz))
            s.nextIndex += count
            s.seq = (s.seq + 1) and 0xffff
        }
    }

    private fun tickPpg(elapsedS: Double) {
        val s = streams[StreamKind.PPG] ?: return
        val target = (elapsedS * s.rateHz).toInt()
        while (s.nextIndex < target) {
            val count = minOf(s.k, target - s.nextIndex)
            val first = s.nextIndex
            val tUs = (first.toDouble() * DSPConstants.usPerS / s.rateHz).roundToLong().toDouble()
            val green = LongArray(count)
            val red = LongArray(count)
            val ir = LongArray(count)
            for (i in 0 until count) {
                val t = ((first + i).toDouble() * DSPConstants.usPerS / s.rateHz).roundToLong().toDouble()
                green[i] = maxOf(0L, signal.greenAt(t).roundToLong())
                red[i] = maxOf(0L, signal.redAt(t).roundToLong())
                ir[i] = maxOf(0L, signal.irAt(t).roundToLong())
            }
            events.ppg.tryEmit(PpgPacket(seq = s.seq, tUs = tUs, sampleRateHz = s.rateHz, green = green, red = red, ir = ir))
            s.nextIndex += count
            s.seq = (s.seq + 1) and 0xffff
        }
    }

    private fun emitMetrics() {
        if (!running) return
        val tUs = deviceNowUs()
        val packet = synchronized(paramsLock) {
            val beats = signal.rPeakTimes(lastMetricsDeviceUs, tUs)
            lastMetricsDeviceUs = tUs
            MetricsPacket(
                tUs = tUs,
                hrBpm = signal.p.hrBpm,
                spo2Pct = signal.p.spo2Target,
                contactQuality = contact.contactQuality(),
                motion = contact.motion(),
                patUs = signal.p.patMs * 1000,
                sbpMmHg = null, // firmware reports BP uncalibrated; calibration is per-subject in-app
                dbpMmHg = null,
                rpeak = beats.isNotEmpty(),
            )
        }
        events.metrics.tryEmit(packet)
    }

    private fun emitStatus() {
        // Slow battery drain for realism.
        batteryPct = maxOf(0.0, batteryPct - 0.05)
        events.battery.tryEmit(batteryPct.roundToInt())
        events.status.tryEmit(
            StatusMessage(
                streamingMask = if (running) enabledMask else 0,
                ecgRateCode = 1,
                biozRateCode = 1,
                ppgRateCode = 1,
                tUs = deviceNowUs(),
                batteryPct = batteryPct.roundToInt(),
                errorFlags = 0,
            )
        )
    }
}
