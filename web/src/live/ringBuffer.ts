/**
 * Fixed-capacity ring buffer of (deviceTimeUs, value) points for live waveform
 * rendering. Mutated at full sample rate by the packet handlers and read by the
 * canvas on requestAnimationFrame — never via React state, so the UI is not
 * re-rendered per sample (§2.4).
 */
export class WaveBuffer {
  private ts: Float64Array;
  private vs: Float32Array;
  private head = 0;
  private filled = 0;

  constructor(public readonly capacity: number) {
    this.ts = new Float64Array(capacity);
    this.vs = new Float32Array(capacity);
  }

  push(t: number, v: number): void {
    this.ts[this.head] = t;
    this.vs[this.head] = v;
    this.head = (this.head + 1) % this.capacity;
    if (this.filled < this.capacity) this.filled++;
  }

  get length(): number {
    return this.filled;
  }

  latestT(): number | null {
    if (this.filled === 0) return null;
    return this.ts[(this.head - 1 + this.capacity) % this.capacity];
  }

  /** Points with timestamp ≥ tFrom, in chronological order. */
  window(tFrom: number): { t: number[]; v: number[] } {
    const t: number[] = [];
    const v: number[] = [];
    for (let i = 0; i < this.filled; i++) {
      const idx = (this.head - this.filled + i + this.capacity * 2) % this.capacity;
      if (this.ts[idx] >= tFrom) {
        t.push(this.ts[idx]);
        v.push(this.vs[idx]);
      }
    }
    return { t, v };
  }

  clear(): void {
    this.head = 0;
    this.filled = 0;
  }
}
