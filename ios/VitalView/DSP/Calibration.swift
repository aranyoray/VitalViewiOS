//
//  Calibration.swift
//  VitalView
//
//  Per-subject PAT→BP calibration by ordinary least squares. Default model regresses BP
//  on 1/PAT (seconds); an alternate model regresses on PAT directly. See docs/DSP.md.
//
//  This is a coarse, per-subject empirical fit for an educational demonstration — NOT a
//  validated clinical model.
//
//  Ported from web/src/dsp/calibration.ts.
//

import Foundation

/// Regression model used to map PAT → BP.
enum CalibModel: String, Codable, CaseIterable {
    case linearInvPAT = "linear_invPAT"
    case linearPAT = "linear_PAT"
}

/// One reference pair: a PAT (µs) with the cuff-measured SBP/DBP at that moment.
struct RefPair: Codable, Equatable {
    var patUs: Double
    var sbp: Double
    var dbp: Double
}

/// `y = a + b·x` coefficients for SBP and DBP.
struct BpCoeffs: Codable, Equatable {
    /// [a, b] for SBP.
    var sbp: [Double]
    /// [a, b] for DBP.
    var dbp: [Double]
}

/// The minimum needed to predict BP from a PAT (a stored Calibration satisfies this).
protocol CalibCoeffs {
    var model: CalibModel { get }
    var coeffs: BpCoeffs { get }
}

/// Result of fitting a calibration, including goodness-of-fit.
struct CalibrationFit: CalibCoeffs {
    var model: CalibModel
    var coeffs: BpCoeffs
    var rmseSbp: Double
    var rmseDbp: Double
    /// Pearson R of the SBP fit (headline goodness-of-fit).
    var r: Double
    var rDbp: Double
    var n: Int
}

/// Predictor `x` for a given PAT, per the chosen model.
func predictor(_ patUs: Double, _ model: CalibModel) -> Double {
    let patS = patUs / DSPConstants.usPerS
    if model == .linearPAT { return patS }
    return patS > 0 ? 1 / patS : 0
}

/// Ordinary least squares fit of `y = a + b·x`. Returns nil if x has zero variance.
func olsFit(_ xs: [Double], _ ys: [Double]) -> (a: Double, b: Double)? {
    let n = xs.count
    if n < 2 { return nil }
    var sx = 0.0, sy = 0.0
    for i in 0..<n {
        sx += xs[i]
        sy += ys[i]
    }
    let mx = sx / Double(n)
    let my = sy / Double(n)
    var sxx = 0.0, sxy = 0.0
    for i in 0..<n {
        let dx = xs[i] - mx
        sxx += dx * dx
        sxy += dx * (ys[i] - my)
    }
    if sxx == 0 { return nil }
    let b = sxy / sxx
    return (a: my - b * mx, b: b)
}

/// Pearson correlation coefficient. Returns NaN if either series has zero variance.
func pearson(_ xs: [Double], _ ys: [Double]) -> Double {
    let n = xs.count
    if n < 2 { return .nan }
    var sx = 0.0, sy = 0.0
    for i in 0..<n {
        sx += xs[i]
        sy += ys[i]
    }
    let mx = sx / Double(n)
    let my = sy / Double(n)
    var sxx = 0.0, syy = 0.0, sxy = 0.0
    for i in 0..<n {
        let dx = xs[i] - mx
        let dy = ys[i] - my
        sxx += dx * dx
        syy += dy * dy
        sxy += dx * dy
    }
    if sxx == 0 || syy == 0 { return .nan }
    return sxy / (sxx * syy).squareRoot()
}

private func rmse(_ predicted: [Double], _ actual: [Double]) -> Double {
    var s = 0.0
    for i in 0..<actual.count {
        let e = predicted[i] - actual[i]
        s += e * e
    }
    return (s / Double(actual.count)).squareRoot()
}

/// Fit a calibration from reference pairs. Needs ≥2 pairs with non-degenerate predictor.
func fitCalibration(_ pairs: [RefPair], _ model: CalibModel) -> CalibrationFit? {
    if pairs.count < 2 { return nil }
    let xs = pairs.map { predictor($0.patUs, model) }
    let sbp = pairs.map { $0.sbp }
    let dbp = pairs.map { $0.dbp }
    guard let fitSbp = olsFit(xs, sbp), let fitDbp = olsFit(xs, dbp) else { return nil }
    let predSbp = xs.map { fitSbp.a + fitSbp.b * $0 }
    let predDbp = xs.map { fitDbp.a + fitDbp.b * $0 }
    return CalibrationFit(
        model: model,
        coeffs: BpCoeffs(sbp: [fitSbp.a, fitSbp.b], dbp: [fitDbp.a, fitDbp.b]),
        rmseSbp: rmse(predSbp, sbp),
        rmseDbp: rmse(predDbp, dbp),
        r: pearson(xs, sbp),
        rDbp: pearson(xs, dbp),
        n: pairs.count
    )
}

/// Predict SBP/DBP from a PAT using stored calibration coefficients.
func predictBp(_ patUs: Double, _ c: CalibCoeffs) -> (sbp: Double, dbp: Double) {
    let x = predictor(patUs, c.model)
    return (
        sbp: c.coeffs.sbp[0] + c.coeffs.sbp[1] * x,
        dbp: c.coeffs.dbp[0] + c.coeffs.dbp[1] * x
    )
}
