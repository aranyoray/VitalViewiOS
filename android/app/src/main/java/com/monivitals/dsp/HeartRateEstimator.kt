//
//  HeartRateEstimator.kt
//  MoniVitals (Android)
//
//  Heart rate from R–R intervals, with a rolling median. See docs/DSP.md.
//  Ported from ios/MoniVitals/DSP/HeartRateEstimator.swift (== web/src/dsp/hr.ts).
//

package com.monivitals.dsp

class HeartRateEstimator {
    private var lastRUs: Double? = null
    private val buffer = RollingMedian(DSPConstants.hrMedianN)

    /** Register an R-peak (µs). Returns the instantaneous bpm if the RR is plausible. */
    fun addRPeak(tUs: Double): Double? {
        val last = lastRUs
        if (last == null) {
            lastRUs = tUs
            return null
        }
        val rrUs = tUs - last
        lastRUs = tUs
        if (rrUs <= 0) return null
        val bpm = (60 * DSPConstants.usPerS) / rrUs
        if (bpm < DSPConstants.hrMinBpm || bpm > DSPConstants.hrMaxBpm) return null
        buffer.push(bpm)
        return bpm
    }

    /** Rolling-median heart rate (bpm), or null until ≥3 beats are collected. */
    fun bpm(): Double? {
        if (buffer.count < 3) return null
        return buffer.value()
    }

    fun reset() {
        lastRUs = null
        buffer.clear()
    }
}
