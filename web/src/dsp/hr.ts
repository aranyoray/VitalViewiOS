/** Heart rate from R–R intervals, with a rolling median. See docs/DSP.md. */
import { HR_MAX_BPM, HR_MEDIAN_N, HR_MIN_BPM, US_PER_S } from './constants';
import { RollingMedian } from './rollingStats';

export class HeartRateEstimator {
  private lastRUs: number | null = null;
  private readonly buffer = new RollingMedian(HR_MEDIAN_N);

  /** Register an R-peak (µs). Returns the instantaneous bpm if the RR is plausible. */
  addRPeak(tUs: number): number | null {
    if (this.lastRUs == null) {
      this.lastRUs = tUs;
      return null;
    }
    const rrUs = tUs - this.lastRUs;
    this.lastRUs = tUs;
    if (rrUs <= 0) return null;
    const bpm = (60 * US_PER_S) / rrUs;
    if (bpm < HR_MIN_BPM || bpm > HR_MAX_BPM) return null;
    this.buffer.push(bpm);
    return bpm;
  }

  /** Rolling-median heart rate (bpm), or null until ≥3 beats are collected. */
  bpm(): number | null {
    if (this.buffer.count < 3) return null;
    return this.buffer.value();
  }

  reset(): void {
    this.lastRUs = null;
    this.buffer.clear();
  }
}
