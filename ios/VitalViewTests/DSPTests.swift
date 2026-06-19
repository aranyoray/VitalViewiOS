//
//  DSPTests.swift
//  VitalViewTests
//
//  RollingStats, SpO2, BioZ gating, R-peak/HR, and Timebase tests, mirroring the
//  corresponding web/src/dsp/*.test.ts and web/src/source/timebase.test.ts.
//
//  Requires an Xcode test target / Swift toolchain to run.
//

import XCTest
@testable import VitalView

final class RollingStatsTests: XCTestCase {
    func testMedianOddEvenNoMutation() {
        let a = [3.0, 1, 2]
        XCTAssertEqual(median(a), 2)
        XCTAssertEqual(a, [3, 1, 2]) // unchanged
        XCTAssertEqual(median([4, 1, 3, 2]), 2.5)
    }

    func testMeanVarianceStddev() {
        XCTAssertEqual(mean([2, 4, 6]), 4)
        XCTAssertEqual(variance([2, 4, 6]), 8.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(stddev([2, 4, 6]), (8.0 / 3.0).squareRoot(), accuracy: 1e-6)
    }

    func testClampAndMapRange() {
        XCTAssertEqual(clamp(5, 0, 3), 3)
        XCTAssertEqual(clamp(-1, 0, 3), 0)
        XCTAssertEqual(mapRange(5, 0, 10, 0, 100), 50)
        XCTAssertEqual(mapRange(0, 0, 0, 7, 9), 7) // degenerate input range
    }

    func testRollingMedianFixedCapacity() {
        let rm = RollingMedian(capacity: 3)
        rm.push(10); rm.push(20); rm.push(30); rm.push(40) // evicts 10
        XCTAssertEqual(rm.count, 3)
        XCTAssertEqual(rm.value(), 30) // median of [20,30,40]
    }
}

final class Spo2Tests: XCTestCase {
    func testRatioOfRatios() {
        let red = [950.0, 1050, 950, 1050]
        let ir = [900.0, 1100, 900, 1100]
        XCTAssertEqual(ratioOfRatios(red, ir) ?? 0, 0.5, accuracy: 1e-6)
    }

    func testDegenerateReturnsNil() {
        XCTAssertNil(ratioOfRatios([0, 0], [1, 1]))
    }

    func testEstimatesNearMockTarget() {
        let fs = 100.0
        let target = 97.0
        var params = MockParams.default
        params.spo2Target = target
        params.ppgRateHz = 100
        let mock = MockSignal(params)
        let est = Spo2Estimator(fs: fs)
        for i in 0..<Int(fs * 5) {
            let t = (Double(i) * DSPConstants.usPerS / fs).rounded()
            est.push(mock.redAt(t), mock.irAt(t))
        }
        let spo2 = est.estimate()
        XCTAssertNotNil(spo2)
        XCTAssertLessThan(abs((spo2 ?? 0) - target), 3)
    }
}

final class BioZGatingTests: XCTestCase {
    private func series(_ fs: Double, _ durS: Double, _ fn: (Double) -> Double) -> TimedSeries {
        var t: [Double] = []
        var v: [Double] = []
        for i in 0..<Int(fs * durS) {
            let ti = (Double(i) * DSPConstants.usPerS / fs).rounded()
            t.append(ti)
            v.append(fn(ti))
        }
        return TimedSeries(t: t, v: v)
    }

    func testFlagsMotionBurstWindows() {
        let ecgFs = 256.0, biozFs = 64.0, dur = 10.0
        var params = MockParams.default
        params.ecgRateHz = 256
        params.biozRateHz = 64
        params.motionBursts = [MotionBurst(startUs: 4 * DSPConstants.usPerS,
                                           endUs: 6 * DSPConstants.usPerS, severity: 4)]
        let mock = MockSignal(params)

        let ecg = series(ecgFs, dur) { mock.ecgAt($0) }
        let dz = series(biozFs, dur) { mock.dzAt($0) }
        let z0 = series(biozFs, dur) { mock.z0At($0) }

        let res = gateEcg(ecg: ecg, dz: dz, z0: z0, windowMs: 500)
        func windowAt(_ sec: Double) -> GateWindow {
            res.windows.first { sec * DSPConstants.usPerS >= $0.tStartUs && sec * DSPConstants.usPerS < $0.tEndUs }!
        }
        XCTAssertTrue(windowAt(1).good)   // quiet
        XCTAssertFalse(windowAt(5).good)  // inside motion burst
        XCTAssertTrue(windowAt(8).good)   // quiet again

        XCTAssertGreaterThan(res.goodPct, 70)
        XCTAssertLessThan(res.goodPct, 92)

        let idxInBurst = ecg.t.firstIndex { $0 >= 5 * DSPConstants.usPerS }!
        XCTAssertNil(res.gatedEcg[idxInBurst])
    }

    func testContactQualityHighAndMotionRises() {
        let biozFs = 64.0
        let est = ContactMotionEstimator(fsBioz: biozFs)
        let mock = MockSignal({ var p = MockParams.default; p.biozRateHz = 64; return p }())
        for i in 0..<Int(biozFs * 3) {
            let t = (Double(i) * DSPConstants.usPerS / biozFs).rounded()
            est.pushZ0(mock.z0At(t))
            est.pushDz(mock.dzAt(t))
        }
        XCTAssertGreaterThan(est.contactQuality(), 70)
        let quietMotion = est.motion()

        let burst = ContactMotionEstimator(fsBioz: biozFs)
        var bp = MockParams.default
        bp.biozRateHz = 64
        bp.motionBursts = [MotionBurst(startUs: 0, endUs: 5 * DSPConstants.usPerS, severity: 5)]
        let mockB = MockSignal(bp)
        for i in 0..<Int(biozFs * 1) {
            let t = (Double(i) * DSPConstants.usPerS / biozFs).rounded()
            burst.pushDz(mockB.dzAt(t))
        }
        XCTAssertGreaterThan(burst.motion(), quietMotion)
    }
}

final class RPeakTests: XCTestCase {
    private func detectRPeaks(_ mock: MockSignal, _ fs: Double, _ durationS: Double) -> [Double] {
        let det = RPeakDetector(fs: fs)
        var peaks: [Double] = []
        for i in 0..<Int(fs * durationS) {
            let t = (Double(i) * DSPConstants.usPerS / fs).rounded()
            if let r = det.process(mock.ecgAt(t), t) { peaks.append(r) }
        }
        return peaks
    }

    func testDetectsAtGroundTruthTimes() {
        let fs = 256.0, dur = 14.0
        var p = MockParams.default; p.hrBpm = 72; p.ecgRateHz = 256
        let mock = MockSignal(p)
        let detected = detectRPeaks(mock, fs, dur)

        let truth = mock.rPeakTimes(2 * DSPConstants.usPerS, dur * DSPConstants.usPerS)
        let detectedSteady = detected.filter { $0 >= 2 * DSPConstants.usPerS }

        XCTAssertGreaterThanOrEqual(detectedSteady.count, truth.count - 1)
        XCTAssertLessThanOrEqual(detectedSteady.count, truth.count + 1)

        for d in detectedSteady {
            let nearest = truth.min(by: { abs($0 - d) < abs($1 - d) })!
            XCTAssertLessThan(abs(nearest - d), 30_000)
        }
    }

    func testRecoversHeartRate() {
        let fs = 256.0
        var p = MockParams.default; p.hrBpm = 88; p.ecgRateHz = 256
        let mock = MockSignal(p)
        let peaks = detectRPeaks(mock, fs, 14)
        let hr = HeartRateEstimator()
        for pk in peaks { hr.addRPeak(pk) }
        XCTAssertNotNil(hr.bpm())
        XCTAssertEqual(hr.bpm() ?? 0, 88, accuracy: 1)
    }

    func testWorksAcrossSampleRatesSlowHR() {
        let fs = 512.0
        var p = MockParams.default; p.hrBpm = 50; p.ecgRateHz = 512
        let mock = MockSignal(p)
        let peaks = detectRPeaks(mock, fs, 16).filter { $0 >= 2 * DSPConstants.usPerS }
        let truth = mock.rPeakTimes(2 * DSPConstants.usPerS, 16 * DSPConstants.usPerS)
        XCTAssertLessThanOrEqual(abs(peaks.count - truth.count), 1)
    }
}

final class TimebaseTests: XCTestCase {
    func testExtenderPassthrough() {
        let ext = TimebaseExtender()
        XCTAssertEqual(ext.extend(100), 100)
        XCTAssertEqual(ext.extend(200), 200)
    }

    func testExtenderAcrossWrap() {
        let ext = TimebaseExtender()
        let nearMax = Double(0xfffffff0)
        XCTAssertEqual(ext.extend(nearMax), nearMax)
        XCTAssertEqual(ext.extend(Double(0x10)), 4_294_967_296 + 16)
    }

    func testSeqTrackerCountsDrops() {
        let t = SeqTracker()
        XCTAssertEqual(t.update(10), 0) // first
        XCTAssertEqual(t.update(11), 0) // contiguous
        XCTAssertEqual(t.update(14), 2) // dropped 12,13
        XCTAssertEqual(t.dropped, 2)
        _ = t.update(65535)
        XCTAssertEqual(t.update(1), 1) // wrapped 65535 -> 0(dropped) -> 1
    }
}
