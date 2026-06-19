import { describe, expect, it } from 'vitest';
import { MockSignal } from '../source/mockSignal';
import { RPeakDetector } from './rpeak';
import { HeartRateEstimator } from './hr';
import { US_PER_S } from './constants';

/** Run the detector over a span of mock ECG and return detected R-peak times (µs). */
function detectRPeaks(mock: MockSignal, fs: number, durationS: number): number[] {
  const det = new RPeakDetector(fs);
  const peaks: number[] = [];
  const n = Math.floor(fs * durationS);
  for (let i = 0; i < n; i++) {
    const t = Math.round((i * US_PER_S) / fs);
    const r = det.process(mock.ecgAt(t), t);
    if (r != null) peaks.push(r);
  }
  return peaks;
}

describe('RPeakDetector', () => {
  it('detects R-peaks at the mock ground-truth times (72 bpm)', () => {
    const fs = 256;
    const dur = 14;
    const mock = new MockSignal({ hrBpm: 72, ecgRateHz: fs });
    const detected = detectRPeaks(mock, fs, dur);

    // Compare against ground truth after the detector's ~1.5 s learning phase.
    const truth = mock.rPeakTimes(2 * US_PER_S, dur * US_PER_S);
    const detectedSteady = detected.filter((t) => t >= 2 * US_PER_S);

    expect(detectedSteady.length).toBeGreaterThanOrEqual(truth.length - 1);
    expect(detectedSteady.length).toBeLessThanOrEqual(truth.length + 1);

    // Every detected peak is within 30 ms of a ground-truth beat.
    for (const d of detectedSteady) {
      const nearest = truth.reduce((a, b) => (Math.abs(b - d) < Math.abs(a - d) ? b : a), truth[0]);
      expect(Math.abs(nearest - d)).toBeLessThan(30_000);
    }
  });

  it('recovers heart rate from detected peaks', () => {
    const fs = 256;
    const mock = new MockSignal({ hrBpm: 88, ecgRateHz: fs });
    const peaks = detectRPeaks(mock, fs, 14);
    const hr = new HeartRateEstimator();
    for (const p of peaks) hr.addRPeak(p);
    expect(hr.bpm()).not.toBeNull();
    expect(hr.bpm()!).toBeCloseTo(88, 0); // within ~0.5 bpm
  });

  it('works across sample rates and a slower heart rate', () => {
    const fs = 512;
    const mock = new MockSignal({ hrBpm: 50, ecgRateHz: fs });
    const peaks = detectRPeaks(mock, fs, 16).filter((t) => t >= 2 * US_PER_S);
    const truth = mock.rPeakTimes(2 * US_PER_S, 16 * US_PER_S);
    expect(Math.abs(peaks.length - truth.length)).toBeLessThanOrEqual(1);
  });
});
