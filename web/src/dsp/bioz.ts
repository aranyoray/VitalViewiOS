/**
 * BioZ-derived signal-quality metrics and the BioZ-gated ECG cleaning that is the
 * project's core thesis. See docs/DSP.md.
 */
import {
  CONTACT_THRESH,
  MOTION_THRESH,
  MOTION_WINDOW_MS,
  Z0_BAD_MOHM,
  Z0_GOOD_MOHM,
} from './constants';
import { clamp, mapRange, median, stddev, variance } from './rollingStats';

/** Live contact-quality and motion estimator fed from the BioZ stream. */
export class ContactMotionEstimator {
  private z0: number[] = [];
  private dz: number[] = [];
  private readonly z0Cap: number;
  private readonly dzCap: number;

  constructor(
    fsBioz: number,
    private motionThresh = MOTION_THRESH,
  ) {
    this.dzCap = Math.max(8, Math.round((fsBioz * MOTION_WINDOW_MS) / 1000));
    this.z0Cap = 32;
  }

  setMotionThresh(thresh: number): void {
    this.motionThresh = thresh;
  }

  pushZ0(z0: number): void {
    this.z0.push(z0);
    if (this.z0.length > this.z0Cap) this.z0.shift();
  }

  pushDz(dz: number): void {
    this.dz.push(dz);
    if (this.dz.length > this.dzCap) this.dz.shift();
  }

  z0Baseline(): number {
    return this.z0.length ? median(this.z0) : 0;
  }

  /** 0..100 contact quality from Z₀ level (60%) and stability (40%). */
  contactQuality(): number {
    if (this.z0.length === 0) return 0;
    const m = this.z0.reduce((a, b) => a + b, 0) / this.z0.length;
    const level = clamp(mapRange(m, Z0_GOOD_MOHM, Z0_BAD_MOHM, 100, 0), 0, 100);
    const stability = m > 0 ? 100 * (1 - clamp(stddev(this.z0) / m, 0, 1)) : 0;
    return Math.round(0.6 * level + 0.4 * stability);
  }

  /** 0 (still) .. 255 motion severity from ΔZ variance. */
  motion(): number {
    if (this.dz.length < 4) return 0;
    const v = variance(this.dz);
    return clamp(Math.round((255 * v) / this.motionThresh), 0, 255);
  }

  reset(): void {
    this.z0 = [];
    this.dz = [];
  }
}

export interface TimedSeries {
  t: number[]; // device µs
  v: number[];
}

export interface GateWindow {
  tStartUs: number;
  tEndUs: number;
  good: boolean;
  dzVar: number;
}

export interface GateResult {
  windows: GateWindow[];
  /** ECG value or null (blanked) per input ECG sample. */
  gatedEcg: (number | null)[];
  goodPct: number;
}

/**
 * BioZ-gated ECG cleaning over fixed windows. A window is bad when ΔZ variance exceeds
 * `motionThresh` or |Z₀ − baseline| exceeds `contactThresh`. Pure function — used by the
 * Gating view and unit-tested.
 */
export function gateEcg(
  ecg: TimedSeries,
  dz: TimedSeries,
  z0: TimedSeries,
  opts: { windowMs?: number; motionThresh?: number; contactThresh?: number } = {},
): GateResult {
  const windowMs = opts.windowMs ?? MOTION_WINDOW_MS;
  const motionThresh = opts.motionThresh ?? MOTION_THRESH;
  const contactThresh = opts.contactThresh ?? CONTACT_THRESH;
  const windowUs = windowMs * 1000;

  const z0Baseline = z0.v.length ? median(z0.v) : 0;

  if (ecg.t.length === 0) {
    return { windows: [], gatedEcg: [], goodPct: 0 };
  }

  const tStart = ecg.t[0];
  const tEnd = ecg.t[ecg.t.length - 1];
  const windows: GateWindow[] = [];
  for (let ws = tStart; ws <= tEnd; ws += windowUs) {
    const we = ws + windowUs;
    const dzWin = sliceValues(dz, ws, we);
    const z0Win = sliceValues(z0, ws, we);
    const dzVar = dzWin.length >= 2 ? variance(dzWin) : 0;
    const z0Dev = z0Win.length ? Math.abs(median(z0Win) - z0Baseline) : 0;
    const bad = dzVar > motionThresh || z0Dev > contactThresh;
    windows.push({ tStartUs: ws, tEndUs: we, good: !bad, dzVar });
  }

  const gatedEcg: (number | null)[] = new Array(ecg.t.length);
  for (let i = 0; i < ecg.t.length; i++) {
    const t = ecg.t[i];
    const wIdx = Math.min(windows.length - 1, Math.max(0, Math.floor((t - tStart) / windowUs)));
    gatedEcg[i] = windows[wIdx]?.good ? ecg.v[i] : null;
  }

  const goodCount = windows.filter((w) => w.good).length;
  const goodPct = windows.length ? (goodCount / windows.length) * 100 : 0;
  return { windows, gatedEcg, goodPct };
}

function sliceValues(series: TimedSeries, lo: number, hi: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < series.t.length; i++) {
    const t = series.t[i];
    if (t >= lo && t < hi) out.push(series.v[i]);
  }
  return out;
}
