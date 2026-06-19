/**
 * Pan–Tompkins-style streaming R-peak detector.
 *
 * Pipeline: band-pass (5–15 Hz) → 5-point derivative → square → moving-window
 * integration → adaptive threshold with refractory. Each detected integration peak is
 * localized back onto the band-passed signal (max |amplitude| in the preceding window)
 * so the reported timestamp aligns with the true R-peak rather than the delayed
 * integration peak. See docs/DSP.md.
 */
import {
  ECG_BP_HIGH_HZ,
  ECG_BP_LOW_HZ,
  QRS_INTEG_MS,
  QRS_REFRACTORY_MS,
  QRS_THRESH_FRAC,
} from './constants';
import { Biquad, FivePointDerivative, MovingAverage } from './filters';

export class RPeakDetector {
  private readonly bandpass: Biquad;
  private readonly deriv = new FivePointDerivative();
  private readonly integrator: MovingAverage;
  private readonly integWindowUs: number;
  private readonly searchBackUs: number;
  private readonly refractoryUs: number;
  private readonly learnUntilSample: number;

  // Local-max tracking on the integrated signal.
  private lastInteg = 0;
  private lastIntegT = 0;
  private rising = false;

  // Adaptive threshold estimates.
  private spk = 0;
  private npk = 0;
  private learned = false;
  private learnMax = 0;
  private learnSum = 0;

  private sampleCount = 0;
  private lastPeakUs = -Infinity;

  // Ring buffer of recent band-passed samples for back-search localization.
  private readonly bpVal: Float64Array;
  private readonly bpT: Float64Array;
  private bpHead = 0;
  private bpFilled = 0;

  constructor(
    private readonly fs: number,
    learnMs = 1500,
  ) {
    this.bandpass = Biquad.bandpass(ECG_BP_LOW_HZ, ECG_BP_HIGH_HZ, fs);
    const integWidth = Math.max(1, Math.round((QRS_INTEG_MS / 1000) * fs));
    this.integrator = new MovingAverage(integWidth);
    this.integWindowUs = (QRS_INTEG_MS / 1000) * 1e6;
    this.searchBackUs = this.integWindowUs + 60_000;
    this.refractoryUs = (QRS_REFRACTORY_MS / 1000) * 1e6;
    this.learnUntilSample = Math.round((learnMs / 1000) * fs);
    const cap = Math.ceil((this.searchBackUs / 1e6) * fs) + 8;
    this.bpVal = new Float64Array(cap);
    this.bpT = new Float64Array(cap);
  }

  /**
   * Feed one ECG sample with its device timestamp (µs). Returns the timestamp of a
   * newly confirmed R-peak (which occurred ~one integration window earlier), or null.
   */
  process(sample: number, tUs: number): number | null {
    const bp = this.bandpass.process(sample);
    this.pushBp(bp, tUs);
    const d = this.deriv.process(bp);
    const integ = this.integrator.process(d * d);

    this.sampleCount++;
    if (!this.learned) {
      this.learnMax = Math.max(this.learnMax, integ);
      this.learnSum += integ;
      if (this.sampleCount >= this.learnUntilSample) {
        this.spk = this.learnMax;
        this.npk = this.learnSum / this.sampleCount;
        this.learned = true;
      }
      this.lastInteg = integ;
      this.lastIntegT = tUs;
      return null;
    }

    let result: number | null = null;
    if (integ > this.lastInteg) {
      this.rising = true;
    } else if (integ < this.lastInteg && this.rising) {
      this.rising = false;
      result = this.evaluatePeak(this.lastInteg, this.lastIntegT);
    }
    this.lastInteg = integ;
    this.lastIntegT = tUs;
    return result;
  }

  private threshold(): number {
    return this.npk + QRS_THRESH_FRAC * (this.spk - this.npk);
  }

  private evaluatePeak(value: number, peakIntegUs: number): number | null {
    if (value > this.threshold()) {
      const rPeakUs = this.localize(peakIntegUs);
      if (rPeakUs - this.lastPeakUs >= this.refractoryUs) {
        this.spk = 0.125 * value + 0.875 * this.spk;
        this.lastPeakUs = rPeakUs;
        return rPeakUs;
      }
      // Within refractory: still adapt the signal estimate, but do not emit.
      this.spk = 0.125 * value + 0.875 * this.spk;
      return null;
    }
    this.npk = 0.125 * value + 0.875 * this.npk;
    return null;
  }

  /** Find the timestamp of max |band-passed amplitude| within the search-back window. */
  private localize(peakIntegUs: number): number {
    const lo = peakIntegUs - this.searchBackUs;
    let bestT = peakIntegUs;
    let bestAbs = -1;
    for (let i = 0; i < this.bpFilled; i++) {
      const idx = (this.bpHead - 1 - i + this.bpVal.length * 2) % this.bpVal.length;
      const t = this.bpT[idx];
      if (t < lo) break;
      const a = Math.abs(this.bpVal[idx]);
      if (a > bestAbs) {
        bestAbs = a;
        bestT = t;
      }
    }
    return bestT;
  }

  private pushBp(v: number, t: number): void {
    this.bpVal[this.bpHead] = v;
    this.bpT[this.bpHead] = t;
    this.bpHead = (this.bpHead + 1) % this.bpVal.length;
    if (this.bpFilled < this.bpVal.length) this.bpFilled++;
  }
}
