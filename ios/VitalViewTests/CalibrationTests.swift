//
//  CalibrationTests.swift
//  VitalViewTests
//
//  Calibration math, mirroring web/src/dsp/calibration.test.ts.
//  Requires an Xcode test target / Swift toolchain to run.
//

import XCTest
@testable import VitalView

final class CalibrationTests: XCTestCase {
    func testOlsRecoversKnownLine() {
        let xs = [1.0, 2, 3, 4]
        let ys = xs.map { 3 + 2 * $0 }
        let fit = olsFit(xs, ys)!
        XCTAssertEqual(fit.a, 3, accuracy: 1e-6)
        XCTAssertEqual(fit.b, 2, accuracy: 1e-6)
    }

    func testPearson() {
        XCTAssertEqual(pearson([1, 2, 3], [2, 4, 6]), 1, accuracy: 1e-6)
        XCTAssertTrue(pearson([5, 5, 5], [1, 2, 3]).isNaN)
    }

    func testPredictorModels() {
        let patUs = 0.25 * DSPConstants.usPerS // 250 ms ⇒ 0.25 s
        XCTAssertEqual(predictor(patUs, .linearInvPAT), 4, accuracy: 1e-6) // 1/0.25
        XCTAssertEqual(predictor(patUs, .linearPAT), 0.25, accuracy: 1e-6)
    }

    func testFitAndPredictInvPAT() {
        let model = CalibModel.linearInvPAT
        let pairs: [RefPair] = [0.2, 0.25, 0.3, 0.35, 0.4].map { patS in
            let inv = 1 / patS
            return RefPair(patUs: patS * DSPConstants.usPerS, sbp: 80 + 8 * inv, dbp: 50 + 4 * inv)
        }
        let fit = fitCalibration(pairs, model)!
        XCTAssertEqual(fit.coeffs.sbp[0], 80, accuracy: 1e-4)
        XCTAssertEqual(fit.coeffs.sbp[1], 8, accuracy: 1e-4)
        XCTAssertEqual(fit.r, 1, accuracy: 1e-6)
        XCTAssertLessThan(fit.rmseSbp, 1e-6)

        let bp = predictBp(0.25 * DSPConstants.usPerS, fit)
        XCTAssertEqual(bp.sbp, 80 + 8 * 4, accuracy: 1e-4) // 1/0.25 = 4
        XCTAssertEqual(bp.dbp, 50 + 4 * 4, accuracy: 1e-4)
    }

    func testReturnsNilWithFewerThanTwoPairs() {
        XCTAssertNil(fitCalibration([RefPair(patUs: 200000, sbp: 120, dbp: 80)], .linearInvPAT))
    }
}
