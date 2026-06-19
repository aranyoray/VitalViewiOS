//
//  CSVExport.swift
//  VitalView
//
//  CSV session export (docs/CSV_FORMAT.md). Pure builders (testable without a store)
//  plus a store-reading entry point that writes a bundle folder for ShareLink /
//  UIActivityViewController.
//
//  Mirrors web/src/model/csv.ts. Column order is fixed; blank numeric cells denote
//  "invalid / not available" (not zero). Numbers are formatted the JavaScript way
//  (integers without a trailing ".0") so output is byte-comparable with the web export.
//

import Foundation

/// Everything needed to build a session bundle.
struct BundleData {
    var session: Session
    var subject: Subject?
    var calibration: Calibration?
    var streams: SessionStreams
    var metrics: [MetricsRecord]
    var annotations: [Annotation]
}

enum CSVExport {
    // MARK: - number / field formatting

    /// Format a Double like JavaScript's `String(number)`: integers have no decimals,
    /// other values use the shortest round-tripping representation.
    static func jsNumber(_ x: Double) -> String {
        if x.isNaN { return "NaN" }
        if x == x.rounded() && abs(x) < 1e15 {
            return String(Int64(x))
        }
        // `%g`-style shortest representation, trimming trailing zeros.
        var s = String(format: "%.15g", x)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    /// RFC-4180 field escaping; nil → empty cell.
    static func csvEscape(_ v: String?) -> String {
        guard let v else { return "" }
        if v.contains(",") || v.contains("\"") || v.contains("\n") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    static func csvEscape(_ v: Double?) -> String {
        guard let v else { return "" }
        return jsNumber(v)
    }

    static func csvEscape(_ v: Int) -> String { String(v) }

    private static func toCsv(_ header: [String], _ rows: [[String]]) -> String {
        var lines = [header.joined(separator: ",")]
        for row in rows { lines.append(row.joined(separator: ",")) }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - session_meta.json

    static func buildSessionMeta(_ d: BundleData) -> String {
        // Build an ordered dictionary tree and serialize with sorted keys disabled,
        // relying on JSONSerialization. Matches the web schema (schemaVersion 1).
        let sessionObj: [String: Any] = [
            "id": d.session.id,
            "subjectCode": d.session.subjectCode,
            "label": d.session.label.rawValue,
            "deviceId": d.session.deviceId,
            "firmwareVersion": d.session.firmwareVersion,
            "startedAt": d.session.startedAt,
            "endedAt": d.session.endedAt.map { $0 as Any } ?? NSNull(),
            "notes": d.session.notes,
            "metricsSource": d.session.metricsSource.rawValue,
            "gating": [
                "motionThresh": d.session.gating.motionThresh,
                "contactThresh": d.session.gating.contactThresh,
                "windowMs": d.session.gating.windowMs,
            ],
        ]

        let subjectObj: [String: Any]
        if let s = d.subject {
            subjectObj = [
                "code": s.code,
                "ageBand": s.ageBand,
                "sex": s.sex.map { $0 as Any } ?? NSNull(),
                "notes": s.notes,
            ]
        } else {
            subjectObj = ["code": d.session.subjectCode]
        }

        let calibObj: Any
        if let c = d.calibration {
            calibObj = [
                "model": c.model.rawValue,
                "coeffs": ["sbp": c.coeffs.sbp, "dbp": c.coeffs.dbp],
                "rmseSbp": c.rmseSbp,
                "rmseDbp": c.rmseDbp,
                "r": c.r,
                "createdAt": c.createdAt,
            ]
        } else {
            calibObj = NSNull()
        }

        let root: [String: Any] = [
            "schemaVersion": 1,
            "session": sessionObj,
            "subject": subjectObj,
            "calibration": calibObj,
        ]

        let data = (try? JSONSerialization.data(withJSONObject: root,
                                                options: [.prettyPrinted])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - bundle files

    /// Build the in-memory bundle: filename → file contents.
    static func buildBundleFiles(_ d: BundleData) -> [(name: String, content: String)] {
        let s = d.streams

        var ecgRows: [[String]] = []
        for i in 0..<s.ecg.t.count {
            ecgRows.append([jsNumber(s.ecg.t[i]), String(s.ecg.ecg[i])])
        }

        var biozRows: [[String]] = []
        for i in 0..<s.bioz.t.count {
            biozRows.append([jsNumber(s.bioz.t[i]), String(s.bioz.z0[i]), String(s.bioz.dz[i])])
        }

        var ppgRows: [[String]] = []
        for i in 0..<s.ppg.t.count {
            ppgRows.append([jsNumber(s.ppg.t[i]), String(s.ppg.green[i]),
                            String(s.ppg.red[i]), String(s.ppg.ir[i])])
        }

        let metricsRows: [[String]] = d.metrics.map { m in
            [
                jsNumber(m.tUs),
                csvEscape(m.hrBpm),
                csvEscape(m.spo2Pct),
                String(m.contactQuality),
                String(m.motion),
                m.patUs == nil ? "" : jsNumber(m.patUs! / 1000),
                csvEscape(m.sbpMmHg),
                csvEscape(m.dbpMmHg),
            ]
        }

        let annoRows: [[String]] = d.annotations.map { a in
            [jsNumber(a.tUs), csvEscape(a.type.rawValue), csvEscape(a.sbp),
             csvEscape(a.dbp), csvEscape(a.text)]
        }

        return [
            ("session_meta.json", buildSessionMeta(d)),
            ("ecg.csv", toCsv(["t_us", "ecg"], ecgRows)),
            ("bioz.csv", toCsv(["t_us", "z0_milliohm", "dz"], biozRows)),
            ("ppg.csv", toCsv(["t_us", "green", "red", "ir"], ppgRows)),
            ("metrics.csv", toCsv(
                ["t_us", "hr_bpm", "spo2_pct", "contact_quality", "motion", "pat_ms", "sbp_est", "dbp_est"],
                metricsRows)),
            ("annotations.csv", toCsv(["t_us", "type", "sbp", "dbp", "text"], annoRows)),
        ]
    }

    /// The bundle folder name: `<label>_<first 8 of id>`.
    static func bundleFolderName(_ session: Session) -> String {
        "\(session.label.rawValue)_\(String(session.id.prefix(8)))"
    }

    // MARK: - store-reading entry point

    /// Read a session from the store and write the CSV bundle into a temp folder.
    /// Returns the folder URL (suitable for ShareLink / UIActivityViewController).
    static func exportSession(_ sessionId: String, store: Store = .shared) throws -> URL {
        guard let session = store.getSession(sessionId) else {
            throw NSError(domain: "VitalView", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Session \(sessionId) not found"])
        }
        let subject = store.getSubject(session.subjectCode)
        let streams = store.readSessionStreams(sessionId)
        let metrics = store.listMetrics(sessionId)
        let annotations = store.listAnnotations(sessionId)
        let files = buildBundleFiles(BundleData(
            session: session,
            subject: subject,
            calibration: session.calibrationSnapshot,
            streams: streams,
            metrics: metrics,
            annotations: annotations
        ))

        let folderName = bundleFolderName(session)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalview_export", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in files {
            let url = dir.appendingPathComponent(f.name)
            try f.content.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        return dir
    }
}
