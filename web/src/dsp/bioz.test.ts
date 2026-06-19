import { describe, expect, it } from 'vitest';
import { ContactMotionEstimator, gateEcg, type TimedSeries } from './bioz';
import { MockSignal } from '../source/mockSignal';
import { US_PER_S } from './constants';

function series(fs: number, durS: number, fn: (t: number) => number): TimedSeries {
  const t: number[] = [];
  const v: number[] = [];
  const n = Math.floor(fs * durS);
  for (let i = 0; i < n; i++) {
    const ti = Math.round((i * US_PER_S) / fs);
    t.push(ti);
    v.push(fn(ti));
  }
  return { t, v };
}

describe('BioZ-gated ECG cleaning', () => {
  it('flags motion-burst windows as bad and keeps the rest good', () => {
    const ecgFs = 256;
    const biozFs = 64;
    const dur = 10;
    const mock = new MockSignal({
      ecgRateHz: ecgFs,
      biozRateHz: biozFs,
      motionBursts: [{ startUs: 4 * US_PER_S, endUs: 6 * US_PER_S, severity: 4 }],
    });

    const ecg = series(ecgFs, dur, (t) => mock.ecgAt(t));
    const dz = series(biozFs, dur, (t) => mock.dzAt(t));
    const z0 = series(biozFs, dur, (t) => mock.z0At(t));

    const res = gateEcg(ecg, dz, z0, { windowMs: 500 });

    const windowAt = (sec: number) => res.windows.find((w) => sec * US_PER_S >= w.tStartUs && sec * US_PER_S < w.tEndUs)!;
    expect(windowAt(1).good).toBe(true); // quiet
    expect(windowAt(5).good).toBe(false); // inside motion burst
    expect(windowAt(8).good).toBe(true); // quiet again

    // ~2 s of 10 s is bad ⇒ good_pct around 80%.
    expect(res.goodPct).toBeGreaterThan(70);
    expect(res.goodPct).toBeLessThan(92);

    // gatedEcg blanks samples inside the burst.
    const idxInBurst = ecg.t.findIndex((t) => t >= 5 * US_PER_S);
    expect(res.gatedEcg[idxInBurst]).toBeNull();
  });

  it('contact quality is high for a stable low Z0 and motion rises during a burst', () => {
    const biozFs = 64;
    const est = new ContactMotionEstimator(biozFs);
    const mock = new MockSignal({ biozRateHz: biozFs });
    for (let i = 0; i < biozFs * 3; i++) {
      const t = Math.round((i * US_PER_S) / biozFs);
      est.pushZ0(mock.z0At(t));
      est.pushDz(mock.dzAt(t));
    }
    expect(est.contactQuality()).toBeGreaterThan(70);
    const quietMotion = est.motion();

    const burst = new ContactMotionEstimator(biozFs);
    const mockB = new MockSignal({
      biozRateHz: biozFs,
      motionBursts: [{ startUs: 0, endUs: 5 * US_PER_S, severity: 5 }],
    });
    for (let i = 0; i < biozFs * 1; i++) {
      const t = Math.round((i * US_PER_S) / biozFs);
      burst.pushDz(mockB.dzAt(t));
    }
    expect(burst.motion()).toBeGreaterThan(quietMotion);
  });
});
