//
//  BioZ.kt
//  MoniVitals (Android)
//
//  BioZ-derived signal-quality metrics and the BioZ-gated ECG cleaning that is the
//  project's core thesis. See docs/DSP.md.
//
//  Ported from ios/MoniVitals/DSP/BioZ.swift (== web/src/dsp/bioz.ts).
//

package com.monivitals.dsp

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt

// MARK: - Live contact / motion estimator

/** Live contact-quality and motion estimator fed from the BioZ stream. */
class ContactMotionEstimator(
    fsBioz: Double,
    motionThresh: Double = DSPConstants.motionThresh,
) {
    private val z0 = ArrayDeque<Double>()
    private val dz = ArrayDeque<Double>()
    private val z0Cap = 32
    private val dzCap: Int = maxOf(8, (fsBioz * DSPConstants.motionWindowMs / 1000).roundToInt())
    private var motionThresh = motionThresh

    fun setMotionThresh(thresh: Double) {
        motionThresh = thresh
    }

    fun pushZ0(value: Double) {
        z0.addLast(value)
        if (z0.size > z0Cap) z0.removeFirst()
    }

    fun pushDz(value: Double) {
        dz.addLast(value)
        if (dz.size > dzCap) dz.removeFirst()
    }

    fun z0Baseline(): Double = if (z0.isEmpty()) 0.0 else median(z0.toList())

    /** 0..100 contact quality from Z0 level (60%) and stability (40%). */
    fun contactQuality(): Int {
        if (z0.isEmpty()) return 0
        val m = z0.sum() / z0.size
        val level = clamp(mapRange(m, DSPConstants.z0GoodMohm, DSPConstants.z0BadMohm, 100.0, 0.0), 0.0, 100.0)
        val stability = if (m > 0) 100 * (1 - clamp(stddev(z0.toList()) / m, 0.0, 1.0)) else 0.0
        return (0.6 * level + 0.4 * stability).roundToInt()
    }

    /** 0 (still) .. 255 motion severity from ΔZ variance. */
    fun motion(): Int {
        if (dz.size < 4) return 0
        val v = variance(dz.toList())
        return clamp((255 * v / motionThresh).roundToInt().toDouble(), 0.0, 255.0).toInt()
    }

    fun reset() {
        z0.clear()
        dz.clear()
    }
}

// MARK: - Gating (pure)

/** A time series in device microseconds. */
data class TimedSeries(val t: List<Double>, val v: List<Double>)

data class GateWindow(
    val tStartUs: Double,
    val tEndUs: Double,
    val good: Boolean,
    val dzVar: Double,
)

data class GateResult(
    val windows: List<GateWindow>,
    /** ECG value or null (blanked) per input ECG sample. */
    val gatedEcg: List<Double?>,
    val goodPct: Double,
)

/**
 * BioZ-gated ECG cleaning over fixed windows. A window is bad when ΔZ variance exceeds
 * `motionThresh` or |Z0 − baseline| exceeds `contactThresh`. Pure function — used by the
 * Gating view and unit-tested.
 */
fun gateEcg(
    ecg: TimedSeries,
    dz: TimedSeries,
    z0: TimedSeries,
    windowMs: Double = DSPConstants.motionWindowMs,
    motionThresh: Double = DSPConstants.motionThresh,
    contactThresh: Double = DSPConstants.contactThresh,
): GateResult {
    val windowUs = windowMs * 1000

    val z0Baseline = if (z0.v.isEmpty()) 0.0 else median(z0.v)

    if (ecg.t.isEmpty()) {
        return GateResult(windows = emptyList(), gatedEcg = emptyList(), goodPct = 0.0)
    }

    val tStart = ecg.t[0]
    val tEnd = ecg.t[ecg.t.size - 1]
    val windows = mutableListOf<GateWindow>()
    var ws = tStart
    while (ws <= tEnd) {
        val we = ws + windowUs
        val dzWin = sliceValues(dz, ws, we)
        val z0Win = sliceValues(z0, ws, we)
        val dzVar = if (dzWin.size >= 2) variance(dzWin) else 0.0
        val z0Dev = if (z0Win.isEmpty()) 0.0 else abs(median(z0Win) - z0Baseline)
        val bad = dzVar > motionThresh || z0Dev > contactThresh
        windows.add(GateWindow(tStartUs = ws, tEndUs = we, good = !bad, dzVar = dzVar))
        ws += windowUs
    }

    val gatedEcg = arrayOfNulls<Double>(ecg.t.size)
    for (i in ecg.t.indices) {
        val t = ecg.t[i]
        val wIdx = minOf(windows.size - 1, maxOf(0, floor((t - tStart) / windowUs).toInt()))
        gatedEcg[i] = if (windows[wIdx].good) ecg.v[i] else null
    }

    val goodCount = windows.count { it.good }
    val goodPct = if (windows.isEmpty()) 0.0 else (goodCount.toDouble() / windows.size) * 100
    return GateResult(windows = windows, gatedEcg = gatedEcg.toList(), goodPct = goodPct)
}

private fun sliceValues(series: TimedSeries, lo: Double, hi: Double): List<Double> {
    val out = mutableListOf<Double>()
    for (i in series.t.indices) {
        val t = series.t[i]
        if (t >= lo && t < hi) out.add(series.v[i])
    }
    return out
}
