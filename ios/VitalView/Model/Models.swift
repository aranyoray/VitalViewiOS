//
//  Models.swift
//  VitalView
//
//  Local-first data model. Identify subjects only by a non-PII code.
//  Mirrors web/src/model/types.ts. All persisted types are Codable.
//

import Foundation

enum SessionLabel: String, Codable, CaseIterable {
    case rest
    case seated
    case walking
    case postExercise = "post-exercise"
    case other
}

enum AnnotationType: String, Codable, CaseIterable {
    case cuffReading = "cuff_reading"
    case motionStart = "motion_start"
    case motionStop = "motion_stop"
    case artifact
    case marker
}

enum MetricsSource: String, Codable, CaseIterable {
    case app
    case firmware
}

/// A study subject, identified only by a non-identifying code.
struct Subject: Codable, Identifiable, Equatable {
    var code: String // primary key, non-identifying
    var ageBand: String
    var sex: String?
    var notes: String
    var createdAt: String // ISO-8601

    var id: String { code }
}

/// Gating thresholds captured per session.
struct GatingConfig: Codable, Equatable {
    var motionThresh: Double
    var contactThresh: Double
    var windowMs: Double
}

/// A recording session.
struct Session: Codable, Identifiable, Equatable {
    var id: String
    var subjectCode: String
    var label: SessionLabel
    var deviceId: String
    var firmwareVersion: String
    var startedAt: String
    var endedAt: String?
    var notes: String
    var metricsSource: MetricsSource
    var gating: GatingConfig
    /// Calibration snapshot at session start (or nil).
    var calibrationSnapshot: Calibration?
}

/// One stored block of samples; timestamps are explicit (extended device µs).
/// Per-sample arrays are stored as `[Double]`/`[Int32]`/`[UInt32]` so the struct is Codable.
struct StreamChunk: Codable {
    var id: Int?
    var sessionId: String
    var stream: StreamKind
    var tStartUs: Double
    var sampleRateHz: Int
    /// Per-sample device timestamps (µs).
    var t: [Double]
    /// ECG only.
    var ecg: [Int32]?
    /// BioZ only (z0 forward-filled per sample).
    var z0: [Int32]?
    var dz: [Int32]?
    /// PPG only.
    var green: [UInt32]?
    var red: [UInt32]?
    var ir: [UInt32]?
}

/// A persisted metrics row.
struct MetricsRecord: Codable {
    var id: Int?
    var sessionId: String
    var tUs: Double
    var hrBpm: Double?
    var spo2Pct: Double?
    var contactQuality: Int
    var motion: Int
    var patUs: Double?
    var sbpMmHg: Double?
    var dbpMmHg: Double?
}

/// A timestamped annotation (markers + cuff readings).
struct Annotation: Codable, Identifiable {
    var id: Int?
    var sessionId: String
    var tUs: Double
    var type: AnnotationType
    var sbp: Double?
    var dbp: Double?
    var text: String?
}

/// A stored per-subject PAT→BP calibration. Conforms to `CalibCoeffs` so `predictBp`
/// can run directly on it.
struct Calibration: Codable, CalibCoeffs, Equatable {
    var id: Int?
    var subjectCode: String
    var model: CalibModel
    var coeffs: BpCoeffs
    var referencePairs: [RefPair]
    var rmseSbp: Double
    var rmseDbp: Double
    var r: Double
    var createdAt: String
}

/// App settings (persisted in UserDefaults as JSON).
struct AppSettings: Codable, Equatable {
    var metricsSource: MetricsSource = .app
    var motionThresh: Double = DSPConstants.motionThresh
    var contactThresh: Double = DSPConstants.contactThresh
    var gatingWindowMs: Double = DSPConstants.motionWindowMs
    var calibModel: CalibModel = .linearInvPAT
    var streamRates: [StreamKind: Int] = [.ecg: 256, .bioz: 64, .ppg: 100]
    var theme: Theme = .system
    var consentAccepted: Bool = false
    var disclaimerAcknowledged: Bool = false

    enum Theme: String, Codable, CaseIterable {
        case dark
        case light
        case system
    }
}
