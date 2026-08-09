//
//  PpgFootDetector.kt
//  MoniVitals (Android)
//
//  PPG pulse-foot detector (intersecting tangents).
//
//  Light low-pass → first derivative → detect each pulse's maximum-upslope point
//  (adaptive peak detection on the derivative with a refractory) → the foot is the
//  intersection of the horizontal line at the pre-upstroke minimum and the tangent
//  through the max-upslope point. See docs/DSP.md.
//
//  Ported line-for-line from ios/MoniVitals/DSP/PpgFootDetector.swift (== web/src/dsp/ppgFoot.ts).
//

package com.monivitals.dsp

import kotlin.math.ceil
import kotlin.math.roundToInt

class PpgFootDetector(fs: Double, learnMs: Double = 1500.0) {
    private val lp: MovingAverage
    private val refractoryUs: Double
    private val historyUs = 1_000_000.0
    private val learnUntilSample: Int

    // `null` mirrors the TS `NaN` "not yet seen" sentinel for the previous sample.
    private var prevY: Double? = null
    private var prevT: Double? = null

    // Local-max tracking on the slope.
    private var lastSlope = 0.0
    private var lastSlopeT = 0.0
    private var lastSlopeY = 0.0
    private var rising = false

    private var spk = 0.0
    private var npk = 0.0
    private var learned = false
    private var learnMax = 0.0
    private var learnSum = 0.0
    private var learnCount = 0

    private var sampleCount = 0
    private var lastFootUs = Double.NEGATIVE_INFINITY

    // History of smoothed samples for the pre-upstroke minimum search.
    private val hY: DoubleArray
    private val hT: DoubleArray
    private var head = 0
    private var filled = 0

    init {
        lp = MovingAverage(maxOf(1, (fs * 0.03).roundToInt()))
        refractoryUs = (DSPConstants.qrsRefractoryMs / 1000) * 1e6
        learnUntilSample = (learnMs / 1000 * fs).roundToInt()
        val cap = ceil(historyUs / 1e6 * fs).toInt() + 8
        hY = DoubleArray(cap)
        hT = DoubleArray(cap)
    }

    /** Feed one PPG (green) sample with its device timestamp (µs). Returns a foot time or null. */
    fun process(green: Double, tUs: Double): Double? {
        val y = lp.process(green)
        pushHistory(y, tUs)

        var slope = 0.0
        val py = prevY
        val pt = prevT
        if (py != null && pt != null && tUs > pt) {
            slope = (y - py) / (tUs - pt)
        }
        prevY = y
        prevT = tUs

        sampleCount += 1
        if (!learned) {
            if (slope > 0) {
                learnMax = maxOf(learnMax, slope)
                learnSum += slope
                learnCount += 1
            }
            if (sampleCount >= learnUntilSample) {
                spk = learnMax
                npk = if (learnCount > 0) learnSum / learnCount else 0.0
                learned = true
            }
            lastSlope = slope
            lastSlopeT = tUs
            lastSlopeY = y
            return null
        }

        var result: Double? = null
        if (slope > lastSlope) {
            rising = true
        } else if (slope < lastSlope && rising) {
            rising = false
            result = evaluateUpstroke(lastSlope, lastSlopeT, lastSlopeY)
        }
        lastSlope = slope
        lastSlopeT = tUs
        lastSlopeY = y
        return result
    }

    private fun threshold(): Double = npk + 0.3 * (spk - npk)

    private fun evaluateUpstroke(slope: Double, tS: Double, yS: Double): Double? {
        if (slope <= 0 || slope <= threshold()) {
            npk = 0.125 * maxOf(0.0, slope) + 0.875 * npk
            return null
        }
        spk = 0.125 * slope + 0.875 * spk
        val foot = computeFoot(slope, tS, yS)
        if (foot - lastFootUs >= refractoryUs) {
            lastFootUs = foot
            return foot
        }
        return null
    }

    /** Intersecting tangents: foot where the tangent at max-slope meets the prior minimum. */
    private fun computeFoot(slope: Double, tS: Double, yS: Double): Double {
        // Pre-upstroke minimum of the smoothed signal within the search-back window.
        val lo = tS - refractoryUs * 2
        var yMin = yS
        val cap = hY.size
        for (i in 0 until filled) {
            val idx = ((head - 1 - i) % cap + cap) % cap
            val t = hT[idx]
            if (t > tS) continue
            if (t < lo) break
            if (hY[idx] < yMin) yMin = hY[idx]
        }
        // t_foot = t_s + (y_min - y_s) / slope (slope > 0, y_min <= y_s ⇒ foot precedes t_s).
        val foot = tS + (yMin - yS) / slope
        return minOf(foot, tS)
    }

    private fun pushHistory(y: Double, t: Double) {
        hY[head] = y
        hT[head] = t
        head = (head + 1) % hY.size
        if (filled < hY.size) filled += 1
    }
}
