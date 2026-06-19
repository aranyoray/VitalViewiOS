/**
 * Streaming filter primitives shared by the detectors. Stateful objects process one
 * sample at a time so they work identically on live BLE data and on recorded replay.
 */

/** Biquad coefficients (normalized so a0 = 1). */
export interface BiquadCoeffs {
  b0: number;
  b1: number;
  b2: number;
  a1: number;
  a2: number;
}

/**
 * 2nd-order Butterworth band-pass coefficients (RBJ cookbook) for the given
 * center/bandwidth derived from low/high cutoffs.
 */
export function bandpassCoeffs(lowHz: number, highHz: number, fs: number): BiquadCoeffs {
  const f0 = Math.sqrt(lowHz * highHz);
  const bw = highHz - lowHz;
  const w0 = (2 * Math.PI * f0) / fs;
  const cosw0 = Math.cos(w0);
  const sinw0 = Math.sin(w0);
  // Bandwidth-based Q.
  const q = f0 / bw;
  const alpha = sinw0 / (2 * q);
  const a0 = 1 + alpha;
  return {
    b0: alpha / a0,
    b1: 0,
    b2: -alpha / a0,
    a1: (-2 * cosw0) / a0,
    a2: (1 - alpha) / a0,
  };
}

/** Direct Form II transposed biquad, processed one sample at a time. */
export class Biquad {
  private z1 = 0;
  private z2 = 0;
  constructor(private c: BiquadCoeffs) {}

  static bandpass(lowHz: number, highHz: number, fs: number): Biquad {
    return new Biquad(bandpassCoeffs(lowHz, highHz, fs));
  }

  process(x: number): number {
    const y = this.c.b0 * x + this.z1;
    this.z1 = this.c.b1 * x - this.c.a1 * y + this.z2;
    this.z2 = this.c.b2 * x - this.c.a2 * y;
    return y;
  }

  reset(): void {
    this.z1 = 0;
    this.z2 = 0;
  }
}

/** 5-point derivative (Pan–Tompkins): y[n] = (2x[n] + x[n-1] − x[n-3] − 2x[n-4]) / 8. */
export class FivePointDerivative {
  private x = [0, 0, 0, 0, 0];
  process(sample: number): number {
    this.x[4] = this.x[3];
    this.x[3] = this.x[2];
    this.x[2] = this.x[1];
    this.x[1] = this.x[0];
    this.x[0] = sample;
    return (2 * this.x[0] + this.x[1] - this.x[3] - 2 * this.x[4]) / 8;
  }
}

/** Causal moving-window average over a fixed number of samples. */
export class MovingAverage {
  private buf: Float64Array;
  private idx = 0;
  private filled = 0;
  private sum = 0;
  constructor(public readonly width: number) {
    this.buf = new Float64Array(Math.max(1, width));
  }
  process(x: number): number {
    const w = this.buf.length;
    this.sum -= this.buf[this.idx];
    this.buf[this.idx] = x;
    this.sum += x;
    this.idx = (this.idx + 1) % w;
    if (this.filled < w) this.filled++;
    return this.sum / this.filled;
  }
}
