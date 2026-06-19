//
//  Parsers.swift
//  VitalView
//
//  Binary → typed-packet parsers. Little-endian throughout. `K` (samples-per-packet) is
//  derived from the payload length so the firmware may batch any count that fits.
//  See docs/BLE_PROTOCOL.md.
//
//  Ported from web/src/ble/parsers.ts.
//

import Foundation

/// Little-endian reader over `Data`, mirroring the web `DataView` access pattern.
/// All `get*` calls assume the offset is within bounds (the parsers derive K from the
/// length first, exactly like the TypeScript implementation).
struct LEReader {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var byteLength: Int { data.count }

    private func byte(_ offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    func getUInt8(_ offset: Int) -> UInt8 {
        byte(offset)
    }

    func getUInt16(_ offset: Int) -> UInt16 {
        UInt16(byte(offset)) | (UInt16(byte(offset + 1)) << 8)
    }

    func getInt16(_ offset: Int) -> Int16 {
        Int16(bitPattern: getUInt16(offset))
    }

    func getUInt32(_ offset: Int) -> UInt32 {
        UInt32(byte(offset))
            | (UInt32(byte(offset + 1)) << 8)
            | (UInt32(byte(offset + 2)) << 16)
            | (UInt32(byte(offset + 3)) << 24)
    }

    func getInt32(_ offset: Int) -> Int32 {
        Int32(bitPattern: getUInt32(offset))
    }
}

enum Parsers {
    static func parseEcg(_ data: Data) -> EcgPacket {
        let r = LEReader(data)
        let seq = Int(r.getUInt16(0))
        let tUs = Double(r.getUInt32(2))
        let sampleRateHz = Int(r.getUInt16(6))
        let k = max(0, (r.byteLength - 8) >> 2)
        var samples = [Int32](repeating: 0, count: k)
        for i in 0..<k { samples[i] = r.getInt32(8 + i * 4) }
        return EcgPacket(seq: seq, tUs: tUs, sampleRateHz: sampleRateHz, samples: samples)
    }

    static func parseBioz(_ data: Data) -> BiozPacket {
        let r = LEReader(data)
        let seq = Int(r.getUInt16(0))
        let tUs = Double(r.getUInt32(2))
        let sampleRateHz = Int(r.getUInt16(6))
        let z0 = r.getInt32(8)
        let k = max(0, (r.byteLength - 12) >> 2)
        var dz = [Int32](repeating: 0, count: k)
        for i in 0..<k { dz[i] = r.getInt32(12 + i * 4) }
        return BiozPacket(seq: seq, tUs: tUs, sampleRateHz: sampleRateHz, z0Milliohm: z0, dz: dz)
    }

    static func parsePpg(_ data: Data) -> PpgPacket {
        let r = LEReader(data)
        let seq = Int(r.getUInt16(0))
        let tUs = Double(r.getUInt32(2))
        let sampleRateHz = Int(r.getUInt16(6))
        let k = max(0, (r.byteLength - 8) / 12)
        var green = [UInt32](repeating: 0, count: k)
        var red = [UInt32](repeating: 0, count: k)
        var ir = [UInt32](repeating: 0, count: k)
        for i in 0..<k {
            let o = 8 + i * 12
            green[i] = r.getUInt32(o)
            red[i] = r.getUInt32(o + 4)
            ir[i] = r.getUInt32(o + 8)
        }
        return PpgPacket(seq: seq, tUs: tUs, sampleRateHz: sampleRateHz, green: green, red: red, ir: ir)
    }

    static func parseMetrics(_ data: Data) -> MetricsPacket {
        let r = LEReader(data)
        let tUs = Double(r.getUInt32(0))
        let hrRaw = r.getUInt16(4)
        let spo2Raw = r.getUInt16(6)
        let contactQuality = Int(r.getUInt8(8))
        let motion = Int(r.getUInt8(9))
        let patRaw = r.getInt32(10)
        let sbpRaw = r.getInt16(14)
        let dbpRaw = r.getInt16(16)
        let rpeakFlags = r.getUInt16(18)
        return MetricsPacket(
            tUs: tUs,
            hrBpm: hrRaw == BLEProtocol.Sentinel.u16 ? nil : Double(hrRaw) / 10,
            spo2Pct: spo2Raw == BLEProtocol.Sentinel.u16 ? nil : Double(spo2Raw) / 10,
            contactQuality: contactQuality,
            motion: motion,
            patUs: patRaw == BLEProtocol.Sentinel.i32Min ? nil : Double(patRaw),
            sbpMmHg: sbpRaw == BLEProtocol.Sentinel.i16Min ? nil : Double(sbpRaw),
            dbpMmHg: dbpRaw == BLEProtocol.Sentinel.i16Min ? nil : Double(dbpRaw),
            rpeak: (rpeakFlags & 0x01) != 0
        )
    }

    static func parseControl(_ data: Data) -> ControlMessage? {
        let r = LEReader(data)
        if r.byteLength < 1 { return nil }
        let msgType = r.getUInt8(0)
        switch msgType {
        case BLEProtocol.StatusMsg.status:
            return .status(StatusMessage(
                streamingMask: r.getUInt8(1),
                ecgRateCode: Int(r.getUInt8(2)),
                biozRateCode: Int(r.getUInt8(3)),
                ppgRateCode: Int(r.getUInt8(4)),
                tUs: Double(r.getUInt32(5)),
                batteryPct: Int(r.getUInt8(9)),
                errorFlags: r.getUInt8(10)
            ))
        case BLEProtocol.StatusMsg.info:
            let fw = "\(r.getUInt8(1)).\(r.getUInt8(2)).\(r.getUInt8(3))"
            var id = ""
            for i in 0..<6 {
                id += String(format: "%02x", Int(r.getUInt8(4 + i)))
            }
            return .info(InfoMessage(
                firmwareVersion: fw,
                deviceId: id,
                capabilities: Int(r.getUInt16(10))
            ))
        case BLEProtocol.StatusMsg.clock:
            return .clock(ClockMessage(tUs: Double(r.getUInt32(1))))
        default:
            return nil
        }
    }
}
