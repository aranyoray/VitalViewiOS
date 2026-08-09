//
//  Filters.kt
//  MoniVitals (Android)
//
//  Streaming filter primitives shared by the detectors. Stateful objects process one
//  sample at a time so they work identically on live BLE data and on recorded replay.
//
//  Ported line-for-line from ios/MoniVitals/DSP/Filters.swift (== web/src/dsp/filters.ts).
//

package com.monivitals.dsp

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// MARK: - Biquad

/** Biquad coefficients (normalized so a0 = 1). */
data class BiquadCoeffs(
    val b0: Double,
    val b1: Double,
    val b2: Double,
    val a1: Double,
    val a2: Double,
)

/**
 * 2nd-order Butterworth band-pass coefficients (RBJ cookbook) for the given
 * center/bandwidth derived from the low/high cutoffs.
 */
fun bandpassCoeffs(lowHz: Double, highHz: Double, fs: Double): BiquadCoeffs {
    val f0 = sqrt(lowHz * highHz)
    val bw = highHz - lowHz
    val w0 = (2 * PI * f0) / fs
    val cosw0 = cos(w0)
    val sinw0 = sin(w0)
    val q = f0 / bw
    val alpha = sinw0 / (2 * q)
    val a0 = 1 + alpha
    return BiquadCoeffs(
        b0 = alpha / a0,
        b1 = 0.0,
        b2 = -alpha / a0,
        a1 = (-2 * cosw0) / a0,
        a2 = (1 - alpha) / a0,
    )
}

/** Direct Form II transposed biquad, processed one sample at a time. */
class Biquad(private val c: BiquadCoeffs) {
    private var z1 = 0.0
    private var z2 = 0.0

    fun process(x: Double): Double {
        val y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    fun reset() {
        z1 = 0.0
        z2 = 0.0
    }

    companion object {
        fun bandpass(lowHz: Double, highHz: Double, fs: Double): Biquad =
            Biquad(bandpassCoeffs(lowHz, highHz, fs))
    }
}

// MARK: - Five-point derivative

/** 5-point derivative (Pan–Tompkins): `y[n] = (2x[n] + x[n-1] − x[n-3] − 2x[n-4]) / 8`. */
class FivePointDerivative {
    private val x = DoubleArray(5)

    fun process(sample: Double): Double {
        x[4] = x[3]
        x[3] = x[2]
        x[2] = x[1]
        x[1] = x[0]
        x[0] = sample
        return (2 * x[0] + x[1] - x[3] - 2 * x[4]) / 8
    }
}

// MARK: - Moving average

/** Causal moving-window average over a fixed number of samples. */
class MovingAverage(width: Int) {
    private val buf = DoubleArray(maxOf(1, width))
    private var idx = 0
    private var filled = 0
    private var sum = 0.0

    fun process(x: Double): Double {
        val w = buf.size
        sum -= buf[idx]
        buf[idx] = x
        sum += x
        idx = (idx + 1) % w
        if (filled < w) filled += 1
        return sum / filled
    }
}
