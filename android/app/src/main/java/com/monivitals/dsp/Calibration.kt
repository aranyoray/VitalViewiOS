//
//  Calibration.kt
//  MoniVitals (Android)
//
//  Per-subject PAT→BP calibration by ordinary least squares. Default model regresses BP
//  on 1/PAT (seconds); an alternate model regresses on PAT directly. See docs/DSP.md.
//
//  This is a coarse, per-subject empirical fit for an educational demonstration — NOT a
//  validated clinical model.
//
//  Ported from ios/MoniVitals/DSP/Calibration.swift (== web/src/dsp/calibration.ts).
//

package com.monivitals.dsp

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.sqrt

/** Regression model used to map PAT → BP. */
@Serializable
enum class CalibModel {
    @SerialName("linear_invPAT") LINEAR_INV_PAT,
    @SerialName("linear_PAT") LINEAR_PAT;

    /** Stable string identifier matching the web/iOS rawValue. */
    val rawValue: String
        get() = when (this) {
            LINEAR_INV_PAT -> "linear_invPAT"
            LINEAR_PAT -> "linear_PAT"
        }
}

/** One reference pair: a PAT (µs) with the cuff-measured SBP/DBP at that moment. */
@Serializable
data class RefPair(
    val patUs: Double,
    val sbp: Double,
    val dbp: Double,
)

/** `y = a + b·x` coefficients for SBP and DBP. */
@Serializable
data class BpCoeffs(
    /** [a, b] for SBP. */
    val sbp: List<Double>,
    /** [a, b] for DBP. */
    val dbp: List<Double>,
)

/** The minimum needed to predict BP from a PAT (a stored Calibration satisfies this). */
interface CalibCoeffs {
    val model: CalibModel
    val coeffs: BpCoeffs
}

/** Result of fitting a calibration, including goodness-of-fit. */
data class CalibrationFit(
    override val model: CalibModel,
    override val coeffs: BpCoeffs,
    val rmseSbp: Double,
    val rmseDbp: Double,
    /** Pearson R of the SBP fit (headline goodness-of-fit). */
    val r: Double,
    val rDbp: Double,
    val n: Int,
) : CalibCoeffs

/** Predictor `x` for a given PAT, per the chosen model. */
fun predictor(patUs: Double, model: CalibModel): Double {
    val patS = patUs / DSPConstants.usPerS
    if (model == CalibModel.LINEAR_PAT) return patS
    return if (patS > 0) 1 / patS else 0.0
}

/** Ordinary least squares fit of `y = a + b·x`. Returns null if x has zero variance. */
fun olsFit(xs: List<Double>, ys: List<Double>): Pair<Double, Double>? {
    val n = xs.size
    if (n < 2) return null
    var sx = 0.0
    var sy = 0.0
    for (i in 0 until n) {
        sx += xs[i]
        sy += ys[i]
    }
    val mx = sx / n
    val my = sy / n
    var sxx = 0.0
    var sxy = 0.0
    for (i in 0 until n) {
        val dx = xs[i] - mx
        sxx += dx * dx
        sxy += dx * (ys[i] - my)
    }
    if (sxx == 0.0) return null
    val b = sxy / sxx
    return Pair(my - b * mx, b) // (a, b)
}

/** Pearson correlation coefficient. Returns NaN if either series has zero variance. */
fun pearson(xs: List<Double>, ys: List<Double>): Double {
    val n = xs.size
    if (n < 2) return Double.NaN
    var sx = 0.0
    var sy = 0.0
    for (i in 0 until n) {
        sx += xs[i]
        sy += ys[i]
    }
    val mx = sx / n
    val my = sy / n
    var sxx = 0.0
    var syy = 0.0
    var sxy = 0.0
    for (i in 0 until n) {
        val dx = xs[i] - mx
        val dy = ys[i] - my
        sxx += dx * dx
        syy += dy * dy
        sxy += dx * dy
    }
    if (sxx == 0.0 || syy == 0.0) return Double.NaN
    return sxy / sqrt(sxx * syy)
}

private fun rmse(predicted: List<Double>, actual: List<Double>): Double {
    var s = 0.0
    for (i in actual.indices) {
        val e = predicted[i] - actual[i]
        s += e * e
    }
    return sqrt(s / actual.size)
}

/** Fit a calibration from reference pairs. Needs ≥2 pairs with non-degenerate predictor. */
fun fitCalibration(pairs: List<RefPair>, model: CalibModel): CalibrationFit? {
    if (pairs.size < 2) return null
    val xs = pairs.map { predictor(it.patUs, model) }
    val sbp = pairs.map { it.sbp }
    val dbp = pairs.map { it.dbp }
    val fitSbp = olsFit(xs, sbp) ?: return null
    val fitDbp = olsFit(xs, dbp) ?: return null
    val predSbp = xs.map { fitSbp.first + fitSbp.second * it }
    val predDbp = xs.map { fitDbp.first + fitDbp.second * it }
    return CalibrationFit(
        model = model,
        coeffs = BpCoeffs(sbp = listOf(fitSbp.first, fitSbp.second), dbp = listOf(fitDbp.first, fitDbp.second)),
        rmseSbp = rmse(predSbp, sbp),
        rmseDbp = rmse(predDbp, dbp),
        r = pearson(xs, sbp),
        rDbp = pearson(xs, dbp),
        n = pairs.size,
    )
}

/** Predict SBP/DBP from a PAT using stored calibration coefficients. */
fun predictBp(patUs: Double, c: CalibCoeffs): Pair<Double, Double> {
    val x = predictor(patUs, c.model)
    return Pair(
        c.coeffs.sbp[0] + c.coeffs.sbp[1] * x, // sbp
        c.coeffs.dbp[0] + c.coeffs.dbp[1] * x, // dbp
    )
}
