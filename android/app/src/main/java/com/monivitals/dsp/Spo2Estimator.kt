//
//  Spo2Estimator.kt
//  MoniVitals (Android)
//
//  SpO2 ESTIMATE via ratio-of-ratios on red/IR over a sliding window. This is an
//  uncalibrated estimate and must be labeled as such in the UI. See docs/DSP.md.
//
//  Ported from ios/MoniVitals/DSP/Spo2Estimator.swift (== web/src/dsp/spo2.ts).
//

package com.monivitals.dsp

import kotlin.math.roundToInt

class Spo2Estimator(fs: Double, windowSec: Double = 2.0) {
    private val red = ArrayDeque<Double>()
    private val ir = ArrayDeque<Double>()
    private val capacity: Int = maxOf(8, (fs * windowSec).roundToInt())

    /** Feed one co-sampled red/IR pair. */
    fun push(redV: Double, irV: Double) {
        red.addLast(redV)
        ir.addLast(irV)
        if (red.size > capacity) {
            red.removeFirst()
            ir.removeFirst()
        }
    }

    /** Current SpO2 estimate (%) clamped to [70,100], or null if the window isn't ready. */
    fun estimate(): Double? {
        if (red.size < capacity) return null
        val r = ratioOfRatios(red.toList(), ir.toList()) ?: return null
        return clamp(DSPConstants.spo2A - DSPConstants.spo2B * r, 70.0, 100.0)
    }

    fun reset() {
        red.clear()
        ir.clear()
    }
}

/** R = (AC_red/DC_red)/(AC_ir/DC_ir), where AC = peak-to-peak and DC = window mean. */
fun ratioOfRatios(red: List<Double>, ir: List<Double>): Double? {
    val acRed = peakToPeak(red)
    val acIr = peakToPeak(ir)
    val dcRed = avg(red)
    val dcIr = avg(ir)
    if (dcRed <= 0 || dcIr <= 0 || acIr <= 0) return null
    val num = acRed / dcRed
    val den = acIr / dcIr
    if (den <= 0) return null
    return num / den
}

private fun peakToPeak(v: List<Double>): Double {
    var lo = Double.POSITIVE_INFINITY
    var hi = Double.NEGATIVE_INFINITY
    for (x in v) {
        if (x < lo) lo = x
        if (x > hi) hi = x
    }
    return hi - lo
}

private fun avg(v: List<Double>): Double {
    var s = 0.0
    for (x in v) s += x
    return if (v.isEmpty()) 0.0 else s / v.size
}
