//
//  RPeakDetector.swift
//  VitalView
//
//  Pan–Tompkins-style streaming R-peak detector.
//
//  Pipeline: band-pass (5–15 Hz) → 5-point derivative → square → moving-window
//  integration → adaptive threshold with refractory. Each detected integration peak is
//  localized back onto the band-passed signal (max |amplitude| in the preceding window)
//  so the reported timestamp aligns with the true R-peak rather than the delayed
//  integration peak. See docs/DSP.md.
//
//  Ported line-for-line from web/src/dsp/rpeak.ts.
//

import Foundation

final class RPeakDetector {
    private let bandpass: Biquad
    private let deriv = FivePointDerivative()
    private let integrator: MovingAverage
    private let integWindowUs: Double
    private let searchBackUs: Double
    private let refractoryUs: Double
    private let learnUntilSample: Int

    // Local-max tracking on the integrated signal.
    private var lastInteg = 0.0
    private var lastIntegT = 0.0
    private var rising = false

    // Adaptive threshold estimates.
    private var spk = 0.0
    private var npk = 0.0
    private var learned = false
    private var learnMax = 0.0
    private var learnSum = 0.0

    private var sampleCount = 0
    private var lastPeakUs = -Double.infinity

    // Ring buffer of recent band-passed samples for back-search localization.
    private var bpVal: [Double]
    private var bpT: [Double]
    private var bpHead = 0
    private var bpFilled = 0

    init(fs: Double, learnMs: Double = 1500) {
        self.bandpass = Biquad.bandpass(lowHz: DSPConstants.ecgBpLowHz, highHz: DSPConstants.ecgBpHighHz, fs: fs)
        let integWidth = max(1, Int((DSPConstants.qrsIntegMs / 1000 * fs).rounded()))
        self.integrator = MovingAverage(width: integWidth)
        self.integWindowUs = (DSPConstants.qrsIntegMs / 1000) * 1e6
        self.searchBackUs = self.integWindowUs + 60_000
        self.refractoryUs = (DSPConstants.qrsRefractoryMs / 1000) * 1e6
        self.learnUntilSample = Int((learnMs / 1000 * fs).rounded())
        let cap = Int((self.searchBackUs / 1e6 * fs).rounded(.up)) + 8
        self.bpVal = Array(repeating: 0.0, count: cap)
        self.bpT = Array(repeating: 0.0, count: cap)
    }

    /// Feed one ECG sample with its device timestamp (µs). Returns the timestamp of a
    /// newly confirmed R-peak (which occurred ~one integration window earlier), or nil.
    func process(_ sample: Double, _ tUs: Double) -> Double? {
        let bp = bandpass.process(sample)
        pushBp(bp, tUs)
        let d = deriv.process(bp)
        let integ = integrator.process(d * d)

        sampleCount += 1
        if !learned {
            learnMax = Swift.max(learnMax, integ)
            learnSum += integ
            if sampleCount >= learnUntilSample {
                spk = learnMax
                npk = learnSum / Double(sampleCount)
                learned = true
            }
            lastInteg = integ
            lastIntegT = tUs
            return nil
        }

        var result: Double? = nil
        if integ > lastInteg {
            rising = true
        } else if integ < lastInteg && rising {
            rising = false
            result = evaluatePeak(lastInteg, lastIntegT)
        }
        lastInteg = integ
        lastIntegT = tUs
        return result
    }

    private func threshold() -> Double {
        npk + DSPConstants.qrsThreshFrac * (spk - npk)
    }

    private func evaluatePeak(_ value: Double, _ peakIntegUs: Double) -> Double? {
        if value > threshold() {
            let rPeakUs = localize(peakIntegUs)
            if rPeakUs - lastPeakUs >= refractoryUs {
                spk = 0.125 * value + 0.875 * spk
                lastPeakUs = rPeakUs
                return rPeakUs
            }
            // Within refractory: still adapt the signal estimate, but do not emit.
            spk = 0.125 * value + 0.875 * spk
            return nil
        }
        npk = 0.125 * value + 0.875 * npk
        return nil
    }

    /// Find the timestamp of max |band-passed amplitude| within the search-back window.
    private func localize(_ peakIntegUs: Double) -> Double {
        let lo = peakIntegUs - searchBackUs
        var bestT = peakIntegUs
        var bestAbs = -1.0
        let cap = bpVal.count
        for i in 0..<bpFilled {
            let idx = ((bpHead - 1 - i) % cap + cap) % cap
            let t = bpT[idx]
            if t < lo { break }
            let a = abs(bpVal[idx])
            if a > bestAbs {
                bestAbs = a
                bestT = t
            }
        }
        return bestT
    }

    private func pushBp(_ v: Double, _ t: Double) {
        bpVal[bpHead] = v
        bpT[bpHead] = t
        bpHead = (bpHead + 1) % bpVal.count
        if bpFilled < bpVal.count { bpFilled += 1 }
    }
}
