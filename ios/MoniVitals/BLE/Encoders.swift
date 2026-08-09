//
//  Encoders.swift
//  MoniVitals
//
//  Typed-packet → binary encoders. Used by the mock source to emit firmware-identical
//  byte payloads and by round-trip parser tests. Little-endian throughout.
//
//  Ported from web/src/ble/encoders.ts.
//

import Foundation

/// Little-endian byte writer, mirroring the web `DataView` set* pattern.
struct LEWriter {
    private(set) var data: Data

    init(capacity: Int) {
        data = Data(count: capacity)
    }

    mutating func setUInt8(_ offset: Int, _ value: UInt8) {
        data[data.startIndex + offset] = value
    }

    mutating func setUInt16(_ offset: Int, _ value: UInt16) {
        setUInt8(offset, UInt8(value & 0xff))
        setUInt8(offset + 1, UInt8((value >> 8) & 0xff))
    }

    mutating func setInt16(_ offset: Int, _ value: Int16) {
        setUInt16(offset, UInt16(bitPattern: value))
    }

    mutating func setUInt32(_ offset: Int, _ value: UInt32) {
        setUInt8(offset, UInt8(value & 0xff))
        setUInt8(offset + 1, UInt8((value >> 8) & 0xff))
        setUInt8(offset + 2, UInt8((value >> 16) & 0xff))
        setUInt8(offset + 3, UInt8((value >> 24) & 0xff))
    }

    mutating func setInt32(_ offset: Int, _ value: Int32) {
        setUInt32(offset, UInt32(bitPattern: value))
    }
}

enum Encoders {
    /// uint32 truncation matching JS `x >>> 0` on a Double timestamp.
    private static func u32(_ tUs: Double) -> UInt32 {
        UInt32(truncatingIfNeeded: Int64(tUs))
    }

    static func encodeEcg(_ p: EcgPacket) -> Data {
        var w = LEWriter(capacity: 8 + p.samples.count * 4)
        w.setUInt16(0, UInt16(p.seq & 0xffff))
        w.setUInt32(2, u32(p.tUs))
        w.setUInt16(6, UInt16(p.sampleRateHz))
        for i in 0..<p.samples.count { w.setInt32(8 + i * 4, p.samples[i]) }
        return w.data
    }

    static func encodeBioz(_ p: BiozPacket) -> Data {
        var w = LEWriter(capacity: 12 + p.dz.count * 4)
        w.setUInt16(0, UInt16(p.seq & 0xffff))
        w.setUInt32(2, u32(p.tUs))
        w.setUInt16(6, UInt16(p.sampleRateHz))
        w.setInt32(8, p.z0Milliohm)
        for i in 0..<p.dz.count { w.setInt32(12 + i * 4, p.dz[i]) }
        return w.data
    }

    static func encodePpg(_ p: PpgPacket) -> Data {
        let k = p.green.count
        var w = LEWriter(capacity: 8 + k * 12)
        w.setUInt16(0, UInt16(p.seq & 0xffff))
        w.setUInt32(2, u32(p.tUs))
        w.setUInt16(6, UInt16(p.sampleRateHz))
        for i in 0..<k {
            let o = 8 + i * 12
            w.setUInt32(o, p.green[i])
            w.setUInt32(o + 4, p.red[i])
            w.setUInt32(o + 8, p.ir[i])
        }
        return w.data
    }

    static func encodeMetrics(_ p: MetricsPacket) -> Data {
        var w = LEWriter(capacity: 20)
        w.setUInt32(0, u32(p.tUs))
        w.setUInt16(4, p.hrBpm == nil ? BLEProtocol.Sentinel.u16 : UInt16((p.hrBpm! * 10).rounded()))
        w.setUInt16(6, p.spo2Pct == nil ? BLEProtocol.Sentinel.u16 : UInt16((p.spo2Pct! * 10).rounded()))
        w.setUInt8(8, UInt8(p.contactQuality & 0xff))
        w.setUInt8(9, UInt8(p.motion & 0xff))
        w.setInt32(10, p.patUs == nil ? BLEProtocol.Sentinel.i32Min : Int32(p.patUs!.rounded()))
        w.setInt16(14, p.sbpMmHg == nil ? BLEProtocol.Sentinel.i16Min : Int16(p.sbpMmHg!.rounded()))
        w.setInt16(16, p.dbpMmHg == nil ? BLEProtocol.Sentinel.i16Min : Int16(p.dbpMmHg!.rounded()))
        w.setUInt16(18, p.rpeak ? 0x01 : 0x00)
        return w.data
    }

    static func encodeStatus(_ m: StatusMessage) -> Data {
        var w = LEWriter(capacity: 11)
        w.setUInt8(0, BLEProtocol.StatusMsg.status)
        w.setUInt8(1, m.streamingMask)
        w.setUInt8(2, UInt8(m.ecgRateCode))
        w.setUInt8(3, UInt8(m.biozRateCode))
        w.setUInt8(4, UInt8(m.ppgRateCode))
        w.setUInt32(5, u32(m.tUs))
        w.setUInt8(9, UInt8(m.batteryPct))
        w.setUInt8(10, m.errorFlags)
        return w.data
    }

    static func encodeInfo(_ m: InfoMessage) -> Data {
        var w = LEWriter(capacity: 12)
        w.setUInt8(0, BLEProtocol.StatusMsg.info)
        let parts = m.firmwareVersion.split(separator: ".").map { Int($0) ?? 0 }
        w.setUInt8(1, UInt8(parts.count > 0 ? parts[0] : 0))
        w.setUInt8(2, UInt8(parts.count > 1 ? parts[1] : 0))
        w.setUInt8(3, UInt8(parts.count > 2 ? parts[2] : 0))
        let chars = Array(m.deviceId)
        for i in 0..<6 {
            let start = i * 2
            var byteVal: UInt8 = 0
            if start + 1 < chars.count {
                let pair = String(chars[start]) + String(chars[start + 1])
                byteVal = UInt8(pair, radix: 16) ?? 0
            }
            w.setUInt8(4 + i, byteVal)
        }
        w.setUInt16(10, UInt16(m.capabilities))
        return w.data
    }
}
