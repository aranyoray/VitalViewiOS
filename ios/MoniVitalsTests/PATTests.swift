//
//  PATTests.swift
//  MoniVitalsTests
//
//  PAT pairing logic + end-to-end PAT recovery against the mock generator's known
//  ground truth, mirroring web/src/dsp/pat.test.ts. This validates the full pipeline
//  (RPeakDetector + PpgFootDetector + PatEstimator) against the synthetic signal.
//
//  Requires an Xcode test target / Swift toolchain to run.
//

import XCTest
@testable import MoniVitals

final class PATTests: XCTestCase {
    func testPairsFootWithNearestPrecedingRPeak() {
        let pat = PatEstimator()
        // R-peaks at 0, 1000, 2000 ms; feet 200 ms later.
        for k in 0..<6 {
            pat.addRPeak(Double(k) * 1_000_000)
            let inst = pat.addFoot(Double(k) * 1_000_000 + 200_000)
            XCTAssertEqual(inst, 200_000)
        }
        XCTAssertEqual(pat.medianMs() ?? 0, 200, accuracy: 1e-5)
    }

    func testRejectsImplausibleFeet() {
        let pat = PatEstimator()
        pat.addRPeak(0)
        XCTAssertNil(pat.addFoot(10_000))  // 10 ms — too short
        XCTAssertNil(pat.addFoot(700_000)) // 700 ms — beyond the 600 ms plausibility window
        XCTAssertEqual(pat.addFoot(200_000), 200_000) // valid
    }

    func testEndToEndPatAgainstMockGroundTruth() {
        let truePatMs = 230.0
        let mock = MockSignal(MockParams(
            hrBpm: 75, patMs: truePatMs, ecgRateHz: 256, ppgRateHz: 100, biozRateHz: 64,
            ecgAmplitude: 1200, ecgNoise: 8, ppgGreenDc: 120000, ppgGreenAc: 9000,
            spo2Target: 98, z0Baseline: 300000, z0Noise: 1500, dzAmplitude: 400,
            dzNoise: 60, seed: 1, motionBursts: []))
        let ecgFs = 256.0
        let ppgFs = 100.0
        let dur = 16

        // Detect R-peaks and PPG feet independently.
        let rDet = RPeakDetector(fs: ecgFs)
        var rPeaks: [Double] = []
        for i in 0..<(Int(ecgFs) * dur) {
            let t = (Double(i) * DSPConstants.usPerS / ecgFs).rounded()
            if let r = rDet.process(mock.ecgAt(t), t) { rPeaks.append(r) }
        }

        let fDet = PpgFootDetector(fs: ppgFs)
        var feet: [Double] = []
        for i in 0..<(Int(ppgFs) * dur) {
            let t = (Double(i) * DSPConstants.usPerS / ppgFs).rounded()
            if let f = fDet.process(mock.greenAt(t), t) { feet.append(f) }
        }

        // Feed both into the estimator in strict time order.
        var events: [(t: Double, isR: Bool)] = rPeaks.map { ($0, true) } + feet.map { ($0, false) }
        events.sort { $0.t < $1.t }

        let pat = PatEstimator()
        for e in events {
            if e.isR { pat.addRPeak(e.t) } else { pat.addFoot(e.t) }
        }

        XCTAssertNotNil(pat.medianMs())
        XCTAssertLessThan(abs((pat.medianMs() ?? 0) - truePatMs), 25) // within 25 ms
    }
}
