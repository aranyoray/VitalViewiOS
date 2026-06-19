import { describe, expect, it } from 'vitest';
import { MockSignal } from '../source/mockSignal';
import { DEFAULT_K } from '../ble/protocol';
import type { BiozPacket, EcgPacket, PpgPacket } from '../ble/packets';
import { MetricsEngine } from './engine';
import { fitCalibration, type RefPair } from './calibration';
import { US_PER_S } from './constants';

type AnyPacket = (EcgPacket | BiozPacket | PpgPacket) & { tStart: number };

/** Build packetized streams from the mock signal, mirroring how the device batches. */
function buildPackets(mock: MockSignal, durationS: number): AnyPacket[] {
  const out: AnyPacket[] = [];
  const make = (kind: 'ecg' | 'bioz' | 'ppg', fs: number, k: number) => {
    const n = Math.floor(fs * durationS);
    for (let first = 0; first < n; first += k) {
      const count = Math.min(k, n - first);
      const tUs = Math.round((first * US_PER_S) / fs);
      const tAt = (i: number) => Math.round(((first + i) * US_PER_S) / fs);
      if (kind === 'ecg') {
        const s = new Int32Array(count);
        for (let i = 0; i < count; i++) s[i] = Math.round(mock.ecgAt(tAt(i)));
        out.push({ kind, seq: 0, tUs, sampleRateHz: fs, samples: s, tStart: tUs });
      } else if (kind === 'bioz') {
        const dz = new Int32Array(count);
        for (let i = 0; i < count; i++) dz[i] = Math.round(mock.dzAt(tAt(i)));
        out.push({ kind, seq: 0, tUs, sampleRateHz: fs, z0Milliohm: Math.round(mock.z0At(tUs)), dz, tStart: tUs });
      } else {
        const g = new Uint32Array(count), r = new Uint32Array(count), ir = new Uint32Array(count);
        for (let i = 0; i < count; i++) {
          g[i] = Math.round(mock.greenAt(tAt(i)));
          r[i] = Math.round(mock.redAt(tAt(i)));
          ir[i] = Math.round(mock.irAt(tAt(i)));
        }
        out.push({ kind, seq: 0, tUs, sampleRateHz: fs, green: g, red: r, ir, tStart: tUs });
      }
    }
  };
  make('ecg', mock.p.ecgRateHz, DEFAULT_K.ecg);
  make('bioz', mock.p.biozRateHz, DEFAULT_K.bioz);
  make('ppg', mock.p.ppgRateHz, DEFAULT_K.ppg);
  return out.sort((a, b) => a.tStart - b.tStart);
}

function feed(engine: MetricsEngine, packets: AnyPacket[]): void {
  for (const p of packets) {
    if (p.kind === 'ecg') engine.ingestEcg(p);
    else if (p.kind === 'bioz') engine.ingestBioz(p);
    else engine.ingestPpg(p);
  }
}

describe('MetricsEngine live path (packets → snapshot)', () => {
  it('produces plausible HR, PAT and contact from batched mock packets', () => {
    const mock = new MockSignal({ hrBpm: 76, patMs: 220, ecgRateHz: 256, ppgRateHz: 100, biozRateHz: 64 });
    const engine = new MetricsEngine();
    const packets = buildPackets(mock, 18);
    feed(engine, packets);
    const snap = engine.snapshot(18 * US_PER_S);

    expect(snap.hrBpm).not.toBeNull();
    expect(Math.abs(snap.hrBpm! - 76)).toBeLessThan(2);
    expect(snap.patUs).not.toBeNull();
    expect(Math.abs(snap.patUs! / 1000 - 220)).toBeLessThan(30);
    expect(snap.contactQuality).toBeGreaterThan(50);
    expect(snap.motion).toBeLessThan(40); // still
    // No calibration yet ⇒ BP remains uncalibrated.
    expect(snap.sbpMmHg).toBeNull();
  });

  it('applies a calibration to produce a BP estimate', () => {
    const mock = new MockSignal({ hrBpm: 70, patMs: 240 });
    const engine = new MetricsEngine();
    // Build a calibration where SBP/DBP depend on 1/PAT.
    const pairs: RefPair[] = [0.2, 0.24, 0.3].map((s) => ({ patUs: s * US_PER_S, sbp: 80 + 8 / s, dbp: 50 + 4 / s }));
    engine.setCalibration(fitCalibration(pairs, 'linear_invPAT')!);
    feed(engine, buildPackets(mock, 18));
    const snap = engine.snapshot(18 * US_PER_S);
    expect(snap.sbpMmHg).not.toBeNull();
    expect(snap.sbpMmHg!).toBeGreaterThan(80);
    expect(snap.dbpMmHg!).toBeGreaterThan(50);
  });
});
