//
//  Protocol.swift
//  MoniVitals
//
//  BLE GATT protocol constants — the single source of truth is docs/BLE_PROTOCOL.md.
//  Firmware, the web app, and the iOS app must all agree with that document.
//  All multi-byte fields are little-endian.
//
//  Ported from web/src/ble/protocol.ts.
//

import Foundation

/// Stream kinds carried over their own characteristics.
enum StreamKind: String, CaseIterable, Codable {
    case ecg
    case bioz
    case ppg
}

/// Wire-format protocol constants. The GATT/CoreBluetooth transport has been removed;
/// these opcodes, rate tables, sentinels, and stream masks remain the single source of
/// truth for the packet encoders/parsers and the mock/replay sources.
enum BLEProtocol {
    /// Control characteristic opcodes (first payload byte on write).
    enum Opcode {
        static let start: UInt8 = 0x01
        static let stop: UInt8 = 0x02
        static let setRate: UInt8 = 0x03
        static let syncClock: UInt8 = 0x04
        static let getInfo: UInt8 = 0x05
    }

    /// Status notification message types (first payload byte).
    enum StatusMsg {
        static let status: UInt8 = 0x10
        static let info: UInt8 = 0x11
        static let clock: UInt8 = 0x12
    }

    /// Stream ids (used in SET_RATE and conceptually in the START bitmask).
    static func streamId(_ stream: StreamKind) -> UInt8 {
        switch stream {
        case .ecg: return 0
        case .bioz: return 1
        case .ppg: return 2
        }
    }

    /// START bitmask bit for a stream.
    static func streamBit(_ stream: StreamKind) -> UInt8 {
        switch stream {
        case .ecg: return 0x01
        case .bioz: return 0x02
        case .ppg: return 0x04
        }
    }

    static let allStreamsMask: UInt8 = 0x01 | 0x02 | 0x04

    /// Rate-code → Hz tables, per docs/BLE_PROTOCOL.md.
    static func rateCodes(_ stream: StreamKind) -> [Int] {
        switch stream {
        case .ecg: return [128, 256, 512]
        case .bioz: return [32, 64, 128]
        case .ppg: return [50, 100, 200, 400]
        }
    }

    /// Default sample rate (Hz) per stream.
    static func defaultRateHz(_ stream: StreamKind) -> Int {
        switch stream {
        case .ecg: return 256
        case .bioz: return 64
        case .ppg: return 100
        }
    }

    /// Default samples-per-packet used by the firmware / mock encoder (parsers derive K).
    static func defaultK(_ stream: StreamKind) -> Int {
        switch stream {
        case .ecg: return 20
        case .bioz: return 16
        case .ppg: return 12
        }
    }

    /// Error-flag bits in the STATUS message.
    enum ErrorFlag {
        static let leadOff: UInt8 = 0x01
        static let ppgSaturation: UInt8 = 0x02
        static let bufferOverflow: UInt8 = 0x04
    }

    /// Invalid sentinels used in the metrics packet.
    enum Sentinel {
        static let u16: UInt16 = 0xffff
        static let i32Min: Int32 = -2_147_483_648
        static let i16Min: Int16 = -32_768
    }

    /// Resolve a rate code to Hz, falling back to the stream default.
    static func rate(from stream: StreamKind, code: Int) -> Int {
        let codes = rateCodes(stream)
        if code >= 0 && code < codes.count { return codes[code] }
        return defaultRateHz(stream)
    }

    /// Resolve a Hz value to its rate code (nearest match), for SET_RATE.
    static func code(from stream: StreamKind, hz: Int) -> Int {
        let codes = rateCodes(stream)
        var best = 0
        var bestErr = Int.max
        for i in 0..<codes.count {
            let err = abs(codes[i] - hz)
            if err < bestErr {
                bestErr = err
                best = i
            }
        }
        return best
    }
}
