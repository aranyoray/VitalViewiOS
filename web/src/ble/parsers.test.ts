import { describe, expect, it } from 'vitest';
import {
  encodeBioz,
  encodeEcg,
  encodeInfo,
  encodeMetrics,
  encodePpg,
  encodeStatus,
} from './encoders';
import { parseBioz, parseControl, parseEcg, parseMetrics, parsePpg, parseControl as pc } from './parsers';
import type { BiozPacket, EcgPacket, MetricsPacket, PpgPacket } from './packets';

describe('BLE packet round-trips', () => {
  it('ECG encodes and parses back, deriving K from length', () => {
    const p: EcgPacket = {
      kind: 'ecg',
      seq: 1234,
      tUs: 4_000_000_000, // exercises full uint32 range
      sampleRateHz: 256,
      samples: Int32Array.from([0, -5, 100000, -123456, 2147483647, -2147483648]),
    };
    const out = parseEcg(encodeEcg(p));
    expect(out.seq).toBe(p.seq);
    expect(out.tUs).toBe(p.tUs);
    expect(out.sampleRateHz).toBe(256);
    expect(Array.from(out.samples)).toEqual(Array.from(p.samples));
  });

  it('BioZ round-trips Z0 and dz', () => {
    const p: BiozPacket = {
      kind: 'bioz',
      seq: 7,
      tUs: 12345,
      sampleRateHz: 64,
      z0Milliohm: 305000,
      dz: Int32Array.from([1, -2, 300, -4000]),
    };
    const out = parseBioz(encodeBioz(p));
    expect(out.z0Milliohm).toBe(305000);
    expect(Array.from(out.dz)).toEqual([1, -2, 300, -4000]);
  });

  it('PPG round-trips interleaved green/red/ir', () => {
    const p: PpgPacket = {
      kind: 'ppg',
      seq: 9,
      tUs: 999,
      sampleRateHz: 100,
      green: Uint32Array.from([1000, 2000, 3000]),
      red: Uint32Array.from([1100, 2100, 3100]),
      ir: Uint32Array.from([1200, 2200, 3200]),
    };
    const out = parsePpg(encodePpg(p));
    expect(Array.from(out.green)).toEqual([1000, 2000, 3000]);
    expect(Array.from(out.red)).toEqual([1100, 2100, 3100]);
    expect(Array.from(out.ir)).toEqual([1200, 2200, 3200]);
  });

  it('Metrics round-trips, honoring invalid sentinels', () => {
    const valid: MetricsPacket = {
      kind: 'metrics',
      tUs: 5000,
      hrBpm: 72.3,
      spo2Pct: 98.1,
      contactQuality: 88,
      motion: 12,
      patUs: 215000,
      sbpMmHg: 121,
      dbpMmHg: 79,
      rpeak: true,
    };
    const out = parseMetrics(encodeMetrics(valid));
    expect(out.hrBpm).toBeCloseTo(72.3, 1);
    expect(out.spo2Pct).toBeCloseTo(98.1, 1);
    expect(out.patUs).toBe(215000);
    expect(out.sbpMmHg).toBe(121);
    expect(out.rpeak).toBe(true);

    const invalid: MetricsPacket = {
      ...valid,
      hrBpm: null,
      spo2Pct: null,
      patUs: null,
      sbpMmHg: null,
      dbpMmHg: null,
      rpeak: false,
    };
    const out2 = parseMetrics(encodeMetrics(invalid));
    expect(out2.hrBpm).toBeNull();
    expect(out2.spo2Pct).toBeNull();
    expect(out2.patUs).toBeNull();
    expect(out2.sbpMmHg).toBeNull();
    expect(out2.dbpMmHg).toBeNull();
  });

  it('Status and Info control messages parse', () => {
    const status = encodeStatus({
      kind: 'status',
      streamingMask: 0x07,
      ecgRateCode: 1,
      biozRateCode: 1,
      ppgRateCode: 1,
      tUs: 123456,
      batteryPct: 84,
      errorFlags: 0x02,
    });
    const s = parseControl(status);
    expect(s?.kind).toBe('status');
    if (s?.kind === 'status') {
      expect(s.streamingMask).toBe(0x07);
      expect(s.batteryPct).toBe(84);
      expect(s.errorFlags).toBe(0x02);
      expect(s.tUs).toBe(123456);
    }

    const info = encodeInfo({
      kind: 'info',
      firmwareVersion: '1.4.2',
      deviceId: 'a1b2c3d4e5f6',
      capabilities: 0x0007,
    });
    const i = pc(info);
    expect(i?.kind).toBe('info');
    if (i?.kind === 'info') {
      expect(i.firmwareVersion).toBe('1.4.2');
      expect(i.deviceId).toBe('a1b2c3d4e5f6');
      expect(i.capabilities).toBe(0x0007);
    }
  });
});
