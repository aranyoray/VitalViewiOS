import { describe, expect, it } from 'vitest';
import { ratioOfRatios, Spo2Estimator } from './spo2';
import { MockSignal } from '../source/mockSignal';
import { US_PER_S } from './constants';

describe('SpO2 (ratio-of-ratios estimate)', () => {
  it('computes R from AC/DC of each channel', () => {
    // red: DC 1000, AC pk-pk 100 ⇒ 0.1 ; ir: DC 1000, AC pk-pk 200 ⇒ 0.2 ; R = 0.5
    const red = [950, 1050, 950, 1050];
    const ir = [900, 1100, 900, 1100];
    expect(ratioOfRatios(red, ir)).toBeCloseTo(0.5, 6);
  });

  it('returns null on degenerate input', () => {
    expect(ratioOfRatios([0, 0], [1, 1])).toBeNull();
  });

  it('estimates near the mock target SpO2', () => {
    const fs = 100;
    const target = 97;
    const mock = new MockSignal({ spo2Target: target, ppgRateHz: fs });
    const est = new Spo2Estimator(fs);
    for (let i = 0; i < fs * 5; i++) {
      const t = Math.round((i * US_PER_S) / fs);
      est.push(mock.redAt(t), mock.irAt(t));
    }
    const spo2 = est.estimate();
    expect(spo2).not.toBeNull();
    expect(Math.abs(spo2! - target)).toBeLessThan(3); // estimate, with synthetic noise
  });
});
