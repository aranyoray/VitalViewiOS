//
//  PatEstimator.swift
//  MoniVitals
//
//  Pulse Arrival Time: pair each PPG foot with the nearest preceding R-peak within a
//  physiologically plausible window, and report a rolling median. See docs/DSP.md.
//
//  Ported from web/src/dsp/pat.ts.
//

import Foundation

final class PatEstimator {
    private static let patMinUs = (DSPConstants.patMinMs / 1000) * DSPConstants.usPerS
    private static let patMaxUs = (DSPConstants.patMaxMs / 1000) * DSPConstants.usPerS

    private var rPeaks: [Double] = []
    private let buffer = RollingMedian(capacity: DSPConstants.patMedianN)

    /// Register a detected R-peak timestamp (µs).
    func addRPeak(_ tUs: Double) {
        rPeaks.append(tUs)
        // Keep only peaks that could still pair with a future foot.
        let cutoff = tUs - Self.patMaxUs * 4
        if rPeaks.count > 32 || (rPeaks.first ?? 0) < cutoff {
            rPeaks = rPeaks.filter { $0 >= cutoff }
        }
    }

    /// Register a detected PPG foot timestamp (µs). Returns the instantaneous PAT (µs)
    /// for this beat if a valid pairing exists, else nil.
    @discardableResult
    func addFoot(_ tUs: Double) -> Double? {
        var best: Double? = nil
        var i = rPeaks.count - 1
        while i >= 0 {
            let r = rPeaks[i]
            i -= 1
            if r > tUs { continue }
            let dt = tUs - r
            if dt > Self.patMaxUs { break } // older peaks only get further away
            if dt >= Self.patMinUs {
                best = dt
                break
            }
        }
        if let best { buffer.push(best) }
        return best
    }

    /// Rolling-median PAT in microseconds, or nil until ≥3 valid beats are collected.
    func medianUs() -> Double? {
        if buffer.count < 3 { return nil }
        return buffer.value()
    }

    /// Rolling-median PAT in milliseconds, or nil.
    func medianMs() -> Double? {
        guard let us = medianUs() else { return nil }
        return us / 1000
    }

    func reset() {
        rPeaks.removeAll()
        buffer.clear()
    }
}
