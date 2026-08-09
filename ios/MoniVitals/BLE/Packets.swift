//
//  Packets.swift
//  MoniVitals
//
//  Typed representations of the decoded BLE stream + control packets.
//  Ported from web/src/ble/packets.ts.
//
//  Note: `tUs` is mutable so the source layer can replace the raw uint32 device time
//  with the extended 64-bit-safe value (see Timebase).
//

import Foundation

// MARK: - Stream packets

struct EcgPacket {
    var seq: Int
    /// Device timestamp (µs) of the FIRST sample in the packet.
    var tUs: Double
    var sampleRateHz: Int
    /// Signed ADC counts.
    var samples: [Int32]
}

struct BiozPacket {
    var seq: Int
    var tUs: Double
    var sampleRateHz: Int
    /// Baseline magnitude (milliohm), once per packet — contact quality.
    var z0Milliohm: Int32
    /// Pulsatile delta-Z samples (ADC counts).
    var dz: [Int32]
}

struct PpgPacket {
    var seq: Int
    var tUs: Double
    var sampleRateHz: Int
    /// Green / red / IR channels (18-bit data right-justified).
    var green: [UInt32]
    var red: [UInt32]
    var ir: [UInt32]
}

struct MetricsPacket {
    var tUs: Double
    /// beats/min, or nil if invalid.
    var hrBpm: Double?
    /// percent (estimate), or nil if invalid.
    var spo2Pct: Double?
    var contactQuality: Int // 0..100
    var motion: Int // 0..255
    /// Pulse arrival time in microseconds, or nil if invalid.
    var patUs: Double?
    var sbpMmHg: Double?
    var dbpMmHg: Double?
    var rpeak: Bool
}

// MARK: - Control messages

struct StatusMessage {
    var streamingMask: UInt8
    var ecgRateCode: Int
    var biozRateCode: Int
    var ppgRateCode: Int
    var tUs: Double
    var batteryPct: Int
    var errorFlags: UInt8
}

struct InfoMessage {
    var firmwareVersion: String // "major.minor.patch"
    var deviceId: String // hex
    var capabilities: Int
}

struct ClockMessage {
    var tUs: Double
}

/// A decoded control-characteristic message.
enum ControlMessage {
    case status(StatusMessage)
    case info(InfoMessage)
    case clock(ClockMessage)
}
