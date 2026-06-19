/**
 * PPG pulse-foot detector (intersecting tangents).
 *
 * Light low-pass → first derivative → detect each pulse's maximum-upslope point
 * (adaptive peak detection on the derivative with a refractory) → the foot is the
 * intersection of the horizontal line at the pre-upstroke minimum and the tangent
 * through the max-upslope point. See docs/DSP.md.
 */
import { QRS_REFRACTORY_MS } from './constants';
import { MovingAverage } from './filters';

export class PpgFootDetector {
  private readonly lp: MovingAverage;
  private readonly refractoryUs: number;
  private readonly historyUs = 1_000_000;
  private readonly learnUntilSample: number;

  private prevY = NaN;
  private prevT = NaN;

  // Local-max tracking on the slope.
  private lastSlope = 0;
  private lastSlopeT = 0;
  private lastSlopeY = 0;
  private rising = false;

  private spk = 0;
  private npk = 0;
  private learned = false;
  private learnMax = 0;
  private learnSum = 0;
  private learnCount = 0;

  private sampleCount = 0;
  private lastFootUs = -Infinity;

  // History of smoothed samples for the pre-upstroke minimum search.
  private readonly hY: Float64Array;
  private readonly hT: Float64Array;
  private head = 0;
  private filled = 0;

  constructor(
    private readonly fs: number,
    learnMs = 1500,
  ) {
    this.lp = new MovingAverage(Math.max(1, Math.round(fs * 0.03)));
    this.refractoryUs = (QRS_REFRACTORY_MS / 1000) * 1e6;
    this.learnUntilSample = Math.round((learnMs / 1000) * fs);
    const cap = Math.ceil((this.historyUs / 1e6) * fs) + 8;
    this.hY = new Float64Array(cap);
    this.hT = new Float64Array(cap);
  }

  /** Feed one PPG (green) sample with its device timestamp (µs). Returns a foot time or null. */
  process(green: number, tUs: number): number | null {
    const y = this.lp.process(green);
    this.pushHistory(y, tUs);

    let slope = 0;
    if (!Number.isNaN(this.prevY) && tUs > this.prevT) {
      slope = (y - this.prevY) / (tUs - this.prevT);
    }
    this.prevY = y;
    this.prevT = tUs;

    this.sampleCount++;
    if (!this.learned) {
      if (slope > 0) {
        this.learnMax = Math.max(this.learnMax, slope);
        this.learnSum += slope;
        this.learnCount++;
      }
      if (this.sampleCount >= this.learnUntilSample) {
        this.spk = this.learnMax;
        this.npk = this.learnCount > 0 ? this.learnSum / this.learnCount : 0;
        this.learned = true;
      }
      this.lastSlope = slope;
      this.lastSlopeT = tUs;
      this.lastSlopeY = y;
      return null;
    }

    let result: number | null = null;
    if (slope > this.lastSlope) {
      this.rising = true;
    } else if (slope < this.lastSlope && this.rising) {
      this.rising = false;
      result = this.evaluateUpstroke(this.lastSlope, this.lastSlopeT, this.lastSlopeY);
    }
    this.lastSlope = slope;
    this.lastSlopeT = tUs;
    this.lastSlopeY = y;
    return result;
  }

  private threshold(): number {
    return this.npk + 0.3 * (this.spk - this.npk);
  }

  private evaluateUpstroke(slope: number, tS: number, yS: number): number | null {
    if (slope <= 0 || slope <= this.threshold()) {
      this.npk = 0.125 * Math.max(0, slope) + 0.875 * this.npk;
      return null;
    }
    this.spk = 0.125 * slope + 0.875 * this.spk;
    const foot = this.computeFoot(slope, tS, yS);
    if (foot - this.lastFootUs >= this.refractoryUs) {
      this.lastFootUs = foot;
      return foot;
    }
    return null;
  }

  /** Intersecting tangents: foot where the tangent at max-slope meets the prior minimum. */
  private computeFoot(slope: number, tS: number, yS: number): number {
    // Pre-upstroke minimum of the smoothed signal within the search-back window.
    const lo = tS - this.refractoryUs * 2;
    let yMin = yS;
    for (let i = 0; i < this.filled; i++) {
      const idx = (this.head - 1 - i + this.hY.length * 2) % this.hY.length;
      const t = this.hT[idx];
      if (t > tS) continue;
      if (t < lo) break;
      if (this.hY[idx] < yMin) yMin = this.hY[idx];
    }
    // t_foot = t_s + (y_min - y_s) / slope  (slope > 0, y_min <= y_s ⇒ foot precedes t_s).
    const foot = tS + (yMin - yS) / slope;
    return Math.min(foot, tS);
  }

  private pushHistory(y: number, t: number): void {
    this.hY[this.head] = y;
    this.hT[this.head] = t;
    this.head = (this.head + 1) % this.hY.length;
    if (this.filled < this.hY.length) this.filled++;
  }
}
