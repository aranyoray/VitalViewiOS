/** Small statistics helpers used by the metric reporters. */

/** Median of a numeric array (does not mutate the input). */
export function median(values: readonly number[]): number {
  if (values.length === 0) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

export function mean(values: readonly number[]): number {
  if (values.length === 0) return NaN;
  let s = 0;
  for (const v of values) s += v;
  return s / values.length;
}

/** Population variance. */
export function variance(values: readonly number[]): number {
  const n = values.length;
  if (n === 0) return 0;
  const m = mean(values);
  let s = 0;
  for (const v of values) {
    const d = v - m;
    s += d * d;
  }
  return s / n;
}

export function stddev(values: readonly number[]): number {
  return Math.sqrt(variance(values));
}

export function clamp(x: number, lo: number, hi: number): number {
  return x < lo ? lo : x > hi ? hi : x;
}

/** Linear map from one range to another (unclamped). */
export function mapRange(x: number, inLo: number, inHi: number, outLo: number, outHi: number): number {
  if (inHi === inLo) return outLo;
  return outLo + ((x - inLo) * (outHi - outLo)) / (inHi - inLo);
}

/** Fixed-capacity ring of recent values that reports its rolling median. */
export class RollingMedian {
  private buf: number[] = [];
  constructor(private readonly capacity: number) {}
  push(v: number): void {
    this.buf.push(v);
    if (this.buf.length > this.capacity) this.buf.shift();
  }
  get count(): number {
    return this.buf.length;
  }
  value(): number {
    return median(this.buf);
  }
  clear(): void {
    this.buf = [];
  }
}
