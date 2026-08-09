//
//  RPeakDetector.kt
//  MoniVitals (Android)
//
//  Pan–Tompkins-style streaming R-peak detector.
//
//  Pipeline: band-pass (5–15 Hz) → 5-point derivative → square → moving-window
//  integration → adaptive threshold with refractory. Each detected integration peak is
//  localized back onto the band-passed signal (max |amplitude| in the preceding window)
//  so the reported timestamp aligns with the true R-peak rather than the delayed
//  integration peak. See docs/DSP.md.
//
//  Ported line-for-line from ios/MoniVitals/DSP/RPeakDetector.swift (== web/src/dsp/rpeak.ts).
//

package com.monivitals.dsp

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToInt

class RPeakDetector(fs: Double, learnMs: Double = 1500.0) {
    private val bandpass = Biquad.bandpass(DSPConstants.ecgBpLowHz, DSPConstants.ecgBpHighHz, fs)
    private val deriv = FivePointDerivative()
    private val integrator: MovingAverage
    private val integWindowUs: Double
    private val searchBackUs: Double
    private val refractoryUs: Double
    private val learnUntilSample: Int

    // Local-max tracking on the integrated signal.
    private var lastInteg = 0.0
    private var lastIntegT = 0.0
    private var rising = false

    // Adaptive threshold estimates.
    private var spk = 0.0
    private var npk = 0.0
    private var learned = false
    private var learnMax = 0.0
    private var learnSum = 0.0

    private var sampleCount = 0
    private var lastPeakUs = Double.NEGATIVE_INFINITY

    // Ring buffer of recent band-passed samples for back-search localization.
    private val bpVal: DoubleArray
    private val bpT: DoubleArray
    private var bpHead = 0
    private var bpFilled = 0

    init {
        val integWidth = maxOf(1, (DSPConstants.qrsIntegMs / 1000 * fs).roundToInt())
        integrator = MovingAverage(integWidth)
        integWindowUs = (DSPConstants.qrsIntegMs / 1000) * 1e6
        searchBackUs = integWindowUs + 60_000
        refractoryUs = (DSPConstants.qrsRefractoryMs / 1000) * 1e6
        learnUntilSample = (learnMs / 1000 * fs).roundToInt()
        val cap = ceil(searchBackUs / 1e6 * fs).toInt() + 8
        bpVal = DoubleArray(cap)
        bpT = DoubleArray(cap)
    }

    /**
     * Feed one ECG sample with its device timestamp (µs). Returns the timestamp of a
     * newly confirmed R-peak (which occurred ~one integration window earlier), or null.
     */
    fun process(sample: Double, tUs: Double): Double? {
        val bp = bandpass.process(sample)
        pushBp(bp, tUs)
        val d = deriv.process(bp)
        val integ = integrator.process(d * d)

        sampleCount += 1
        if (!learned) {
            learnMax = maxOf(learnMax, integ)
            learnSum += integ
            if (sampleCount >= learnUntilSample) {
                spk = learnMax
                npk = learnSum / sampleCount
                learned = true
            }
            lastInteg = integ
            lastIntegT = tUs
            return null
        }

        var result: Double? = null
        if (integ > lastInteg) {
            rising = true
        } else if (integ < lastInteg && rising) {
            rising = false
            result = evaluatePeak(lastInteg, lastIntegT)
        }
        lastInteg = integ
        lastIntegT = tUs
        return result
    }

    private fun threshold(): Double = npk + DSPConstants.qrsThreshFrac * (spk - npk)

    private fun evaluatePeak(value: Double, peakIntegUs: Double): Double? {
        if (value > threshold()) {
            val rPeakUs = localize(peakIntegUs)
            if (rPeakUs - lastPeakUs >= refractoryUs) {
                spk = 0.125 * value + 0.875 * spk
                lastPeakUs = rPeakUs
                return rPeakUs
            }
            // Within refractory: still adapt the signal estimate, but do not emit.
            spk = 0.125 * value + 0.875 * spk
            return null
        }
        npk = 0.125 * value + 0.875 * npk
        return null
    }

    /** Find the timestamp of max |band-passed amplitude| within the search-back window. */
    private fun localize(peakIntegUs: Double): Double {
        val lo = peakIntegUs - searchBackUs
        var bestT = peakIntegUs
        var bestAbs = -1.0
        val cap = bpVal.size
        for (i in 0 until bpFilled) {
            val idx = ((bpHead - 1 - i) % cap + cap) % cap
            val t = bpT[idx]
            if (t < lo) break
            val a = abs(bpVal[idx])
            if (a > bestAbs) {
                bestAbs = a
                bestT = t
            }
        }
        return bestT
    }

    private fun pushBp(v: Double, t: Double) {
        bpVal[bpHead] = v
        bpT[bpHead] = t
        bpHead = (bpHead + 1) % bpVal.size
        if (bpFilled < bpVal.size) bpFilled += 1
    }
}
