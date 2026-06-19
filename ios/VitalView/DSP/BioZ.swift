//
//  BioZ.swift
//  VitalView
//
//  BioZ-derived signal-quality metrics and the BioZ-gated ECG cleaning that is the
//  project's core thesis. See docs/DSP.md.
//
//  Ported from web/src/dsp/bioz.ts.
//

import Foundation

// MARK: - Live contact / motion estimator

/// Live contact-quality and motion estimator fed from the BioZ stream.
final class ContactMotionEstimator {
    private var z0: [Double] = []
    private var dz: [Double] = []
    private let z0Cap: Int
    private let dzCap: Int
    private var motionThresh: Double

    init(fsBioz: Double, motionThresh: Double = DSPConstants.motionThresh) {
        self.dzCap = max(8, Int((fsBioz * DSPConstants.motionWindowMs / 1000).rounded()))
        self.z0Cap = 32
        self.motionThresh = motionThresh
    }

    func setMotionThresh(_ thresh: Double) {
        motionThresh = thresh
    }

    func pushZ0(_ value: Double) {
        z0.append(value)
        if z0.count > z0Cap { z0.removeFirst() }
    }

    func pushDz(_ value: Double) {
        dz.append(value)
        if dz.count > dzCap { dz.removeFirst() }
    }

    func z0Baseline() -> Double {
        z0.isEmpty ? 0 : median(z0)
    }

    /// 0..100 contact quality from Z0 level (60%) and stability (40%).
    func contactQuality() -> Int {
        if z0.isEmpty { return 0 }
        let m = z0.reduce(0, +) / Double(z0.count)
        let level = clamp(mapRange(m, DSPConstants.z0GoodMohm, DSPConstants.z0BadMohm, 100, 0), 0, 100)
        let stability = m > 0 ? 100 * (1 - clamp(stddev(z0) / m, 0, 1)) : 0
        return Int((0.6 * level + 0.4 * stability).rounded())
    }

    /// 0 (still) .. 255 motion severity from ΔZ variance.
    func motion() -> Int {
        if dz.count < 4 { return 0 }
        let v = variance(dz)
        return Int(clamp((255 * v / motionThresh).rounded(), 0, 255))
    }

    func reset() {
        z0.removeAll()
        dz.removeAll()
    }
}

// MARK: - Gating (pure)

/// A time series in device microseconds.
struct TimedSeries {
    var t: [Double]
    var v: [Double]
}

struct GateWindow {
    var tStartUs: Double
    var tEndUs: Double
    var good: Bool
    var dzVar: Double
}

struct GateResult {
    var windows: [GateWindow]
    /// ECG value or nil (blanked) per input ECG sample.
    var gatedEcg: [Double?]
    var goodPct: Double
}

/// BioZ-gated ECG cleaning over fixed windows. A window is bad when ΔZ variance exceeds
/// `motionThresh` or |Z0 − baseline| exceeds `contactThresh`. Pure function — used by the
/// Gating view and unit-tested.
func gateEcg(
    ecg: TimedSeries,
    dz: TimedSeries,
    z0: TimedSeries,
    windowMs: Double = DSPConstants.motionWindowMs,
    motionThresh: Double = DSPConstants.motionThresh,
    contactThresh: Double = DSPConstants.contactThresh
) -> GateResult {
    let windowUs = windowMs * 1000

    let z0Baseline = z0.v.isEmpty ? 0 : median(z0.v)

    if ecg.t.isEmpty {
        return GateResult(windows: [], gatedEcg: [], goodPct: 0)
    }

    let tStart = ecg.t[0]
    let tEnd = ecg.t[ecg.t.count - 1]
    var windows: [GateWindow] = []
    var ws = tStart
    while ws <= tEnd {
        let we = ws + windowUs
        let dzWin = sliceValues(dz, ws, we)
        let z0Win = sliceValues(z0, ws, we)
        let dzVar = dzWin.count >= 2 ? variance(dzWin) : 0
        let z0Dev = z0Win.isEmpty ? 0 : abs(median(z0Win) - z0Baseline)
        let bad = dzVar > motionThresh || z0Dev > contactThresh
        windows.append(GateWindow(tStartUs: ws, tEndUs: we, good: !bad, dzVar: dzVar))
        ws += windowUs
    }

    var gatedEcg = [Double?](repeating: nil, count: ecg.t.count)
    for i in 0..<ecg.t.count {
        let t = ecg.t[i]
        let wIdx = min(windows.count - 1, max(0, Int(((t - tStart) / windowUs).rounded(.down))))
        gatedEcg[i] = windows[wIdx].good ? ecg.v[i] : nil
    }

    let goodCount = windows.filter { $0.good }.count
    let goodPct = windows.isEmpty ? 0 : (Double(goodCount) / Double(windows.count)) * 100
    return GateResult(windows: windows, gatedEcg: gatedEcg, goodPct: goodPct)
}

private func sliceValues(_ series: TimedSeries, _ lo: Double, _ hi: Double) -> [Double] {
    var out: [Double] = []
    for i in 0..<series.t.count {
        let t = series.t[i]
        if t >= lo && t < hi { out.append(series.v[i]) }
    }
    return out
}
