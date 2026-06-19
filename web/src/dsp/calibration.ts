/**
 * Per-subject PAT→BP calibration by ordinary least squares. Default model regresses BP
 * on 1/PAT (seconds); an alternate model regresses on PAT directly. See docs/DSP.md.
 *
 * This is a coarse, per-subject empirical fit for an educational demonstration — NOT a
 * validated clinical model.
 */
import { US_PER_S } from './constants';

export type CalibModel = 'linear_invPAT' | 'linear_PAT';

export interface RefPair {
  patUs: number;
  sbp: number;
  dbp: number;
}

/** The minimum needed to predict BP from a PAT (a stored Calibration satisfies this). */
export interface CalibCoeffs {
  model: CalibModel;
  /** y = a + b·x, where x is the model predictor. */
  coeffs: { sbp: [number, number]; dbp: [number, number] };
}

export interface CalibrationFit extends CalibCoeffs {
  rmseSbp: number;
  rmseDbp: number;
  /** Pearson R of the SBP fit (headline goodness-of-fit). */
  r: number;
  rDbp: number;
  n: number;
}

/** Predictor x for a given PAT, per the chosen model. */
export function predictor(patUs: number, model: CalibModel): number {
  const patS = patUs / US_PER_S;
  if (model === 'linear_PAT') return patS;
  return patS > 0 ? 1 / patS : 0;
}

/** Ordinary least squares fit of y = a + b·x. Returns null if x has zero variance. */
export function olsFit(xs: readonly number[], ys: readonly number[]): { a: number; b: number } | null {
  const n = xs.length;
  if (n < 2) return null;
  let sx = 0;
  let sy = 0;
  for (let i = 0; i < n; i++) {
    sx += xs[i];
    sy += ys[i];
  }
  const mx = sx / n;
  const my = sy / n;
  let sxx = 0;
  let sxy = 0;
  for (let i = 0; i < n; i++) {
    const dx = xs[i] - mx;
    sxx += dx * dx;
    sxy += dx * (ys[i] - my);
  }
  if (sxx === 0) return null;
  const b = sxy / sxx;
  return { a: my - b * mx, b };
}

/** Pearson correlation coefficient. */
export function pearson(xs: readonly number[], ys: readonly number[]): number {
  const n = xs.length;
  if (n < 2) return NaN;
  let sx = 0;
  let sy = 0;
  for (let i = 0; i < n; i++) {
    sx += xs[i];
    sy += ys[i];
  }
  const mx = sx / n;
  const my = sy / n;
  let sxx = 0;
  let syy = 0;
  let sxy = 0;
  for (let i = 0; i < n; i++) {
    const dx = xs[i] - mx;
    const dy = ys[i] - my;
    sxx += dx * dx;
    syy += dy * dy;
    sxy += dx * dy;
  }
  if (sxx === 0 || syy === 0) return NaN;
  return sxy / Math.sqrt(sxx * syy);
}

function rmse(predicted: readonly number[], actual: readonly number[]): number {
  let s = 0;
  for (let i = 0; i < actual.length; i++) {
    const e = predicted[i] - actual[i];
    s += e * e;
  }
  return Math.sqrt(s / actual.length);
}

/** Fit a calibration from reference pairs. Needs ≥2 pairs with non-degenerate predictor. */
export function fitCalibration(pairs: readonly RefPair[], model: CalibModel): CalibrationFit | null {
  if (pairs.length < 2) return null;
  const xs = pairs.map((p) => predictor(p.patUs, model));
  const sbp = pairs.map((p) => p.sbp);
  const dbp = pairs.map((p) => p.dbp);
  const fitSbp = olsFit(xs, sbp);
  const fitDbp = olsFit(xs, dbp);
  if (!fitSbp || !fitDbp) return null;
  const predSbp = xs.map((x) => fitSbp.a + fitSbp.b * x);
  const predDbp = xs.map((x) => fitDbp.a + fitDbp.b * x);
  return {
    model,
    coeffs: { sbp: [fitSbp.a, fitSbp.b], dbp: [fitDbp.a, fitDbp.b] },
    rmseSbp: rmse(predSbp, sbp),
    rmseDbp: rmse(predDbp, dbp),
    r: pearson(xs, sbp),
    rDbp: pearson(xs, dbp),
    n: pairs.length,
  };
}

/** Predict SBP/DBP from a PAT using stored calibration coefficients. */
export function predictBp(patUs: number, c: CalibCoeffs): { sbp: number; dbp: number } {
  const x = predictor(patUs, c.model);
  return {
    sbp: c.coeffs.sbp[0] + c.coeffs.sbp[1] * x,
    dbp: c.coeffs.dbp[0] + c.coeffs.dbp[1] * x,
  };
}
