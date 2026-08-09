//
//  RollingStats.kt
//  MoniVitals (Android)
//
//  Small statistics helpers used by the metric reporters.
//  Ported from ios/MoniVitals/DSP/RollingStats.swift (== web/src/dsp/rollingStats.ts).
//

package com.monivitals.dsp

import kotlin.math.sqrt

/** Median of a numeric list (does not mutate the input). Returns NaN for empty input. */
fun median(values: List<Double>): Double {
    if (values.isEmpty()) return Double.NaN
    val sorted = values.sorted()
    val mid = sorted.size shr 1
    return if (sorted.size % 2 != 0) sorted[mid] else (sorted[mid - 1] + sorted[mid]) / 2
}

/** Arithmetic mean. Returns NaN for empty input. */
fun mean(values: List<Double>): Double {
    if (values.isEmpty()) return Double.NaN
    var s = 0.0
    for (v in values) s += v
    return s / values.size
}

/** Population variance. Returns 0 for empty input. */
fun variance(values: List<Double>): Double {
    val n = values.size
    if (n == 0) return 0.0
    val m = mean(values)
    var s = 0.0
    for (v in values) {
        val d = v - m
        s += d * d
    }
    return s / n
}

/** Population standard deviation. */
fun stddev(values: List<Double>): Double = sqrt(variance(values))

/** Clamp `x` into `[lo, hi]`. */
fun clamp(x: Double, lo: Double, hi: Double): Double = if (x < lo) lo else if (x > hi) hi else x

/** Linear map from one range to another (unclamped). */
fun mapRange(x: Double, inLo: Double, inHi: Double, outLo: Double, outHi: Double): Double {
    if (inHi == inLo) return outLo
    return outLo + ((x - inLo) * (outHi - outLo)) / (inHi - inLo)
}

/** Fixed-capacity ring of recent values that reports its rolling median. */
class RollingMedian(private val capacity: Int) {
    private val buf = ArrayDeque<Double>()

    fun push(v: Double) {
        buf.addLast(v)
        if (buf.size > capacity) buf.removeFirst()
    }

    val count: Int get() = buf.size

    fun value(): Double = median(buf.toList())

    fun clear() = buf.clear()
}
