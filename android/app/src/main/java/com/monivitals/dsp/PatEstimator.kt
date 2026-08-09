//
//  PatEstimator.kt
//  MoniVitals (Android)
//
//  Pulse Arrival Time: pair each PPG foot with the nearest preceding R-peak within a
//  physiologically plausible window, and report a rolling median. See docs/DSP.md.
//
//  Ported from ios/MoniVitals/DSP/PatEstimator.swift (== web/src/dsp/pat.ts).
//

package com.monivitals.dsp

class PatEstimator {
    private val patMinUs = (DSPConstants.patMinMs / 1000) * DSPConstants.usPerS
    private val patMaxUs = (DSPConstants.patMaxMs / 1000) * DSPConstants.usPerS

    private var rPeaks = mutableListOf<Double>()
    private val buffer = RollingMedian(DSPConstants.patMedianN)

    /** Register a detected R-peak timestamp (µs). */
    fun addRPeak(tUs: Double) {
        rPeaks.add(tUs)
        // Keep only peaks that could still pair with a future foot.
        val cutoff = tUs - patMaxUs * 4
        if (rPeaks.size > 32 || (rPeaks.firstOrNull() ?: 0.0) < cutoff) {
            rPeaks = rPeaks.filter { it >= cutoff }.toMutableList()
        }
    }

    /**
     * Register a detected PPG foot timestamp (µs). Returns the instantaneous PAT (µs)
     * for this beat if a valid pairing exists, else null.
     */
    fun addFoot(tUs: Double): Double? {
        var best: Double? = null
        var i = rPeaks.size - 1
        while (i >= 0) {
            val r = rPeaks[i]
            i -= 1
            if (r > tUs) continue
            val dt = tUs - r
            if (dt > patMaxUs) break // older peaks only get further away
            if (dt >= patMinUs) {
                best = dt
                break
            }
        }
        if (best != null) buffer.push(best)
        return best
    }

    /** Rolling-median PAT in microseconds, or null until ≥3 valid beats are collected. */
    fun medianUs(): Double? {
        if (buffer.count < 3) return null
        return buffer.value()
    }

    /** Rolling-median PAT in milliseconds, or null. */
    fun medianMs(): Double? {
        val us = medianUs() ?: return null
        return us / 1000
    }

    fun reset() {
        rPeaks.clear()
        buffer.clear()
    }
}
