/**
 * Pulse Arrival Time: pair each PPG foot with the nearest preceding R-peak within
 * a physiologically plausible window, and report a rolling median. See docs/DSP.md.
 */
import { PAT_MAX_MS, PAT_MEDIAN_N, PAT_MIN_MS, US_PER_S } from './constants';
import { RollingMedian } from './rollingStats';

const PAT_MIN_US = (PAT_MIN_MS / 1000) * US_PER_S;
const PAT_MAX_US = (PAT_MAX_MS / 1000) * US_PER_S;

export class PatEstimator {
  private rPeaks: number[] = [];
  private readonly buffer = new RollingMedian(PAT_MEDIAN_N);

  /** Register a detected R-peak timestamp (µs). */
  addRPeak(tUs: number): void {
    this.rPeaks.push(tUs);
    // Keep only peaks that could still pair with a future foot.
    const cutoff = tUs - PAT_MAX_US * 4;
    if (this.rPeaks.length > 32 || this.rPeaks[0] < cutoff) {
      this.rPeaks = this.rPeaks.filter((t) => t >= cutoff);
    }
  }

  /**
   * Register a detected PPG foot timestamp (µs). Returns the instantaneous PAT (µs)
   * for this beat if a valid pairing exists, else null.
   */
  addFoot(tUs: number): number | null {
    let best: number | null = null;
    for (let i = this.rPeaks.length - 1; i >= 0; i--) {
      const r = this.rPeaks[i];
      if (r > tUs) continue;
      const dt = tUs - r;
      if (dt > PAT_MAX_US) break; // older peaks only get further away
      if (dt >= PAT_MIN_US) {
        best = dt;
        break;
      }
    }
    if (best != null) this.buffer.push(best);
    return best;
  }

  /** Rolling-median PAT in microseconds, or null until ≥3 valid beats are collected. */
  medianUs(): number | null {
    if (this.buffer.count < 3) return null;
    return this.buffer.value();
  }

  /** Rolling-median PAT in milliseconds, or null. */
  medianMs(): number | null {
    const us = this.medianUs();
    return us == null ? null : us / 1000;
  }

  reset(): void {
    this.rPeaks = [];
    this.buffer.clear();
  }
}
