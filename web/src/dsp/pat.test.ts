import { describe, expect, it } from 'vitest';
import { MockSignal } from '../source/mockSignal';
import { PatEstimator } from './pat';
import { PpgFootDetector } from './ppgFoot';
import { RPeakDetector } from './rpeak';
import { US_PER_S } from './constants';

describe('PatEstimator pairing', () => {
  it('pairs each foot with the nearest preceding R-peak in the plausible window', () => {
    const pat = new PatEstimator();
    // R-peaks at 0, 1000, 2000 ms; feet 200 ms later.
    for (let k = 0; k < 6; k++) {
      pat.addRPeak(k * 1_000_000);
      const inst = pat.addFoot(k * 1_000_000 + 200_000);
      expect(inst).toBe(200_000);
    }
    expect(pat.medianMs()).toBeCloseTo(200, 5);
  });

  it('rejects feet with no R-peak inside [50,600] ms', () => {
    const pat = new PatEstimator();
    pat.addRPeak(0);
    expect(pat.addFoot(10_000)).toBeNull(); // 10 ms — too short
    expect(pat.addFoot(700_000)).toBeNull(); // 700 ms — too long (> PAT_MAX_MS = 600)
    expect(pat.addFoot(200_000)).toBe(200_000); // valid
  });
});

describe('end-to-end PAT against mock ground truth', () => {
  it('recovers the configured PAT from synthetic ECG + PPG', () => {
    const truePatMs = 230;
    const mock = new MockSignal({ hrBpm: 75, patMs: truePatMs, ecgRateHz: 256, ppgRateHz: 100 });
    const ecgFs = 256;
    const ppgFs = 100;
    const dur = 16;

    // Detect R-peaks and PPG feet independently.
    const rDet = new RPeakDetector(ecgFs);
    const rPeaks: number[] = [];
    for (let i = 0; i < ecgFs * dur; i++) {
      const t = Math.round((i * US_PER_S) / ecgFs);
      const r = rDet.process(mock.ecgAt(t), t);
      if (r != null) rPeaks.push(r);
    }

    const fDet = new PpgFootDetector(ppgFs);
    const feet: number[] = [];
    for (let i = 0; i < ppgFs * dur; i++) {
      const t = Math.round((i * US_PER_S) / ppgFs);
      const f = fDet.process(mock.greenAt(t), t);
      if (f != null) feet.push(f);
    }

    // Feed both into the estimator in strict time order.
    const events = [
      ...rPeaks.map((t) => ({ t, kind: 'r' as const })),
      ...feet.map((t) => ({ t, kind: 'f' as const })),
    ].sort((a, b) => a.t - b.t);

    const pat = new PatEstimator();
    for (const e of events) {
      if (e.kind === 'r') pat.addRPeak(e.t);
      else pat.addFoot(e.t);
    }

    expect(pat.medianMs()).not.toBeNull();
    expect(Math.abs(pat.medianMs()! - truePatMs)).toBeLessThan(25); // within 25 ms
  });
});
