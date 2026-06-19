//
//  HeartRateEstimator.swift
//  VitalView
//
//  Heart rate from R–R intervals, with a rolling median. See docs/DSP.md.
//  Ported from web/src/dsp/hr.ts.
//

import Foundation

final class HeartRateEstimator {
    private var lastRUs: Double? = nil
    private let buffer = RollingMedian(capacity: DSPConstants.hrMedianN)

    /// Register an R-peak (µs). Returns the instantaneous bpm if the RR is plausible.
    @discardableResult
    func addRPeak(_ tUs: Double) -> Double? {
        guard let last = lastRUs else {
            lastRUs = tUs
            return nil
        }
        let rrUs = tUs - last
        lastRUs = tUs
        if rrUs <= 0 { return nil }
        let bpm = (60 * DSPConstants.usPerS) / rrUs
        if bpm < DSPConstants.hrMinBpm || bpm > DSPConstants.hrMaxBpm { return nil }
        buffer.push(bpm)
        return bpm
    }

    /// Rolling-median heart rate (bpm), or nil until ≥3 beats are collected.
    func bpm() -> Double? {
        if buffer.count < 3 { return nil }
        return buffer.value()
    }

    func reset() {
        lastRUs = nil
        buffer.clear()
    }
}
