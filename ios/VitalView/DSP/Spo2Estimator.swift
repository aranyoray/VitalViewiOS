//
//  Spo2Estimator.swift
//  VitalView
//
//  SpO2 ESTIMATE via ratio-of-ratios on red/IR over a sliding window. This is an
//  uncalibrated estimate and must be labeled as such in the UI. See docs/DSP.md.
//
//  Ported from web/src/dsp/spo2.ts.
//

import Foundation

final class Spo2Estimator {
    private var red: [Double] = []
    private var ir: [Double] = []
    private let capacity: Int

    init(fs: Double, windowSec: Double = 2) {
        self.capacity = max(8, Int((fs * windowSec).rounded()))
    }

    /// Feed one co-sampled red/IR pair.
    func push(_ redV: Double, _ irV: Double) {
        red.append(redV)
        ir.append(irV)
        if red.count > capacity {
            red.removeFirst()
            ir.removeFirst()
        }
    }

    /// Current SpO2 estimate (%) clamped to [70,100], or nil if the window isn't ready.
    func estimate() -> Double? {
        if red.count < capacity { return nil }
        guard let r = ratioOfRatios(red, ir) else { return nil }
        return clamp(DSPConstants.spo2A - DSPConstants.spo2B * r, 70, 100)
    }

    func reset() {
        red.removeAll()
        ir.removeAll()
    }
}

/// R = (AC_red/DC_red)/(AC_ir/DC_ir), where AC = peak-to-peak and DC = window mean.
func ratioOfRatios(_ red: [Double], _ ir: [Double]) -> Double? {
    let acRed = peakToPeak(red)
    let acIr = peakToPeak(ir)
    let dcRed = avg(red)
    let dcIr = avg(ir)
    if dcRed <= 0 || dcIr <= 0 || acIr <= 0 { return nil }
    let num = acRed / dcRed
    let den = acIr / dcIr
    if den <= 0 { return nil }
    return num / den
}

private func peakToPeak(_ v: [Double]) -> Double {
    var lo = Double.infinity
    var hi = -Double.infinity
    for x in v {
        if x < lo { lo = x }
        if x > hi { hi = x }
    }
    return hi - lo
}

private func avg(_ v: [Double]) -> Double {
    var s = 0.0
    for x in v { s += x }
    return v.isEmpty ? 0 : s / Double(v.count)
}
