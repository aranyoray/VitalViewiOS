//
//  ParserRoundTripTests.swift
//  MoniVitalsTests
//
//  Encode → parse round-trips for every BLE packet, mirroring
//  web/src/ble/parsers.test.ts. Requires an Xcode test target / Swift toolchain to run
//  (there is no Swift toolchain in the authoring environment).
//

import XCTest
@testable import MoniVitals

final class ParserRoundTripTests: XCTestCase {
    func testEcgRoundTripDerivesKFromLength() {
        let p = EcgPacket(
            seq: 1234,
            tUs: 4_000_000_000, // exercises full uint32 range
            sampleRateHz: 256,
            samples: [0, -5, 100000, -123456, 2147483647, -2147483648]
        )
        let out = Parsers.parseEcg(Encoders.encodeEcg(p))
        XCTAssertEqual(out.seq, p.seq)
        XCTAssertEqual(out.tUs, p.tUs)
        XCTAssertEqual(out.sampleRateHz, 256)
        XCTAssertEqual(out.samples, p.samples)
    }

    func testBiozRoundTrip() {
        let p = BiozPacket(seq: 7, tUs: 12345, sampleRateHz: 64,
                           z0Milliohm: 305000, dz: [1, -2, 300, -4000])
        let out = Parsers.parseBioz(Encoders.encodeBioz(p))
        XCTAssertEqual(out.z0Milliohm, 305000)
        XCTAssertEqual(out.dz, [1, -2, 300, -4000])
    }

    func testPpgRoundTrip() {
        let p = PpgPacket(seq: 9, tUs: 999, sampleRateHz: 100,
                          green: [1000, 2000, 3000], red: [1100, 2100, 3100], ir: [1200, 2200, 3200])
        let out = Parsers.parsePpg(Encoders.encodePpg(p))
        XCTAssertEqual(out.green, [1000, 2000, 3000])
        XCTAssertEqual(out.red, [1100, 2100, 3100])
        XCTAssertEqual(out.ir, [1200, 2200, 3200])
    }

    func testMetricsRoundTripHonoringSentinels() {
        let valid = MetricsPacket(tUs: 5000, hrBpm: 72.3, spo2Pct: 98.1,
                                  contactQuality: 88, motion: 12, patUs: 215000,
                                  sbpMmHg: 121, dbpMmHg: 79, rpeak: true)
        let out = Parsers.parseMetrics(Encoders.encodeMetrics(valid))
        XCTAssertEqual(out.hrBpm ?? 0, 72.3, accuracy: 0.05)
        XCTAssertEqual(out.spo2Pct ?? 0, 98.1, accuracy: 0.05)
        XCTAssertEqual(out.patUs, 215000)
        XCTAssertEqual(out.sbpMmHg, 121)
        XCTAssertTrue(out.rpeak)

        let invalid = MetricsPacket(tUs: 5000, hrBpm: nil, spo2Pct: nil,
                                    contactQuality: 88, motion: 12, patUs: nil,
                                    sbpMmHg: nil, dbpMmHg: nil, rpeak: false)
        let out2 = Parsers.parseMetrics(Encoders.encodeMetrics(invalid))
        XCTAssertNil(out2.hrBpm)
        XCTAssertNil(out2.spo2Pct)
        XCTAssertNil(out2.patUs)
        XCTAssertNil(out2.sbpMmHg)
        XCTAssertNil(out2.dbpMmHg)
    }

    func testStatusAndInfoControlMessages() {
        let status = Encoders.encodeStatus(StatusMessage(
            streamingMask: 0x07, ecgRateCode: 1, biozRateCode: 1, ppgRateCode: 1,
            tUs: 123456, batteryPct: 84, errorFlags: 0x02))
        guard case let .status(s)? = Parsers.parseControl(status) else {
            return XCTFail("expected status")
        }
        XCTAssertEqual(s.streamingMask, 0x07)
        XCTAssertEqual(s.batteryPct, 84)
        XCTAssertEqual(s.errorFlags, 0x02)
        XCTAssertEqual(s.tUs, 123456)

        let info = Encoders.encodeInfo(InfoMessage(
            firmwareVersion: "1.4.2", deviceId: "a1b2c3d4e5f6", capabilities: 0x0007))
        guard case let .info(i)? = Parsers.parseControl(info) else {
            return XCTFail("expected info")
        }
        XCTAssertEqual(i.firmwareVersion, "1.4.2")
        XCTAssertEqual(i.deviceId, "a1b2c3d4e5f6")
        XCTAssertEqual(i.capabilities, 0x0007)
    }
}
