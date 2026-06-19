import { describe, expect, it } from 'vitest';
import { fitCalibration, olsFit, pearson, predictBp, predictor, type RefPair } from './calibration';
import { US_PER_S } from './constants';

describe('calibration math', () => {
  it('olsFit recovers a known line', () => {
    const xs = [1, 2, 3, 4];
    const ys = xs.map((x) => 3 + 2 * x);
    const fit = olsFit(xs, ys)!;
    expect(fit.a).toBeCloseTo(3, 6);
    expect(fit.b).toBeCloseTo(2, 6);
  });

  it('pearson is 1 for a perfect positive line and 0 variance returns NaN', () => {
    expect(pearson([1, 2, 3], [2, 4, 6])).toBeCloseTo(1, 6);
    expect(Number.isNaN(pearson([5, 5, 5], [1, 2, 3]))).toBe(true);
  });

  it('predictor uses 1/PAT for invPAT and PAT for linear_PAT', () => {
    const patUs = 0.25 * US_PER_S; // 250 ms ⇒ 0.25 s
    expect(predictor(patUs, 'linear_invPAT')).toBeCloseTo(4, 6); // 1/0.25
    expect(predictor(patUs, 'linear_PAT')).toBeCloseTo(0.25, 6);
  });

  it('fits a clean SBP = 80 + 8*(1/PAT) relationship and predicts it back', () => {
    const model = 'linear_invPAT';
    const pairs: RefPair[] = [0.2, 0.25, 0.3, 0.35, 0.4].map((patS) => {
      const inv = 1 / patS;
      return { patUs: patS * US_PER_S, sbp: 80 + 8 * inv, dbp: 50 + 4 * inv };
    });
    const fit = fitCalibration(pairs, model)!;
    expect(fit.coeffs.sbp[0]).toBeCloseTo(80, 4);
    expect(fit.coeffs.sbp[1]).toBeCloseTo(8, 4);
    expect(fit.r).toBeCloseTo(1, 6);
    expect(fit.rmseSbp).toBeLessThan(1e-6);

    const bp = predictBp(0.25 * US_PER_S, fit);
    expect(bp.sbp).toBeCloseTo(80 + 8 * 4, 4); // 1/0.25 = 4
    expect(bp.dbp).toBeCloseTo(50 + 4 * 4, 4);
  });

  it('returns null with fewer than two pairs', () => {
    expect(fitCalibration([{ patUs: 200000, sbp: 120, dbp: 80 }], 'linear_invPAT')).toBeNull();
  });
});
