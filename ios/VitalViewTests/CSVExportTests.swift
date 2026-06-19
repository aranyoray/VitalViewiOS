//
//  CSVExportTests.swift
//  VitalViewTests
//
//  CSV escaping + fixed-header / blank-cell / forward-fill correctness, mirroring the
//  relevant parts of web/src/model/csv.test.ts. (The iOS export produces a folder bundle
//  rather than a ZIP, so the zip-specific web tests are not ported.)
//
//  Requires an Xcode test target / Swift toolchain to run.
//

import XCTest
@testable import VitalView

final class CSVExportTests: XCTestCase {
    func testCsvEscape() {
        XCTAssertEqual(CSVExport.csvEscape("plain"), "plain")
        XCTAssertEqual(CSVExport.csvEscape(42 as Double), "42")
        XCTAssertEqual(CSVExport.csvEscape(nil as String?), "")
        XCTAssertEqual(CSVExport.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.csvEscape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExport.csvEscape("line1\nline2"), "\"line1\nline2\"")
    }

    func testJsNumberFormatting() {
        // Integers must have no trailing ".0" so output is byte-comparable with the web.
        XCTAssertEqual(CSVExport.jsNumber(215), "215")
        XCTAssertEqual(CSVExport.jsNumber(215000.0 / 1000.0), "215")
        XCTAssertEqual(CSVExport.jsNumber(72), "72")
        XCTAssertEqual(CSVExport.jsNumber(3906), "3906")
        XCTAssertEqual(CSVExport.jsNumber(0), "0")
    }

    func testBuildBundleFilesHeadersAndCells() {
        let bundle = BundleData(
            session: Session(
                id: "abc12345", subjectCode: "S01", label: .rest, deviceId: "dev",
                firmwareVersion: "1.0.0",
                startedAt: "2026-01-01T00:00:00.000Z", endedAt: "2026-01-01T00:01:00.000Z",
                notes: "", metricsSource: .app,
                gating: GatingConfig(motionThresh: 4e6, contactThresh: 5e6, windowMs: 500),
                calibrationSnapshot: nil),
            subject: Subject(code: "S01", ageBand: "18-25", sex: nil, notes: "",
                             createdAt: "2026-01-01T00:00:00.000Z"),
            calibration: nil,
            streams: {
                var s = SessionStreams()
                s.ecg = SessionStreams.Ecg(t: [0, 3906], ecg: [10, -20])
                s.bioz = SessionStreams.Bioz(t: [0], z0: [300000], dz: [5])
                s.ppg = SessionStreams.Ppg(t: [0], green: [1000], red: [1100], ir: [1200])
                return s
            }(),
            metrics: [MetricsRecord(id: nil, sessionId: "abc12345", tUs: 1000, hrBpm: 72,
                                    spo2Pct: 98, contactQuality: 90, motion: 3,
                                    patUs: 215000, sbpMmHg: nil, dbpMmHg: nil)],
            annotations: [Annotation(id: nil, sessionId: "abc12345", tUs: 2000,
                                     type: .cuffReading, sbp: 120, dbp: 80, text: "arm")]
        )

        let files = Dictionary(uniqueKeysWithValues: CSVExport.buildBundleFiles(bundle).map { ($0.name, $0.content) })

        XCTAssertEqual(files["ecg.csv"]!.split(separator: "\n", omittingEmptySubsequences: false)[0], "t_us,ecg")
        XCTAssertEqual(files["ecg.csv"]!.split(separator: "\n", omittingEmptySubsequences: false)[1], "0,10")
        XCTAssertEqual(files["bioz.csv"]!.split(separator: "\n", omittingEmptySubsequences: false)[0], "t_us,z0_milliohm,dz")
        XCTAssertEqual(files["metrics.csv"]!.split(separator: "\n", omittingEmptySubsequences: false)[0],
                       "t_us,hr_bpm,spo2_pct,contact_quality,motion,pat_ms,sbp_est,dbp_est")
        // pat_ms = 215, sbp/dbp blank (uncalibrated)
        XCTAssertEqual(files["metrics.csv"]!.split(separator: "\n", omittingEmptySubsequences: false)[1], "1000,72,98,90,3,215,,")
        XCTAssertEqual(files["annotations.csv"]!.split(separator: "\n", omittingEmptySubsequences: false)[1], "2000,cuff_reading,120,80,arm")

        let meta = try! JSONSerialization.jsonObject(with: files["session_meta.json"]!.data(using: .utf8)!) as! [String: Any]
        let session = meta["session"] as! [String: Any]
        XCTAssertEqual(session["subjectCode"] as? String, "S01")
        XCTAssertEqual(meta["schemaVersion"] as? Int, 1)
    }
}
