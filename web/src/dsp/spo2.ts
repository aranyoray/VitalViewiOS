/**
 * SpO₂ ESTIMATE via ratio-of-ratios on red/IR over a sliding window. This is an
 * uncalibrated estimate and must be labeled as such in the UI. See docs/DSP.md.
 */
import { SPO2_A, SPO2_B } from './constants';
import { clamp } from './rollingStats';

export class Spo2Estimator {
  private red: number[] = [];
  private ir: number[] = [];
  private readonly capacity: number;

  constructor(fs: number, windowSec = 2) {
    this.capacity = Math.max(8, Math.round(fs * windowSec));
  }

  /** Feed one co-sampled red/IR pair. */
  push(red: number, ir: number): void {
    this.red.push(red);
    this.ir.push(ir);
    if (this.red.length > this.capacity) {
      this.red.shift();
      this.ir.shift();
    }
  }

  /** Current SpO₂ estimate (%) clamped to [70,100], or null if the window isn't ready. */
  estimate(): number | null {
    if (this.red.length < this.capacity) return null;
    const r = ratioOfRatios(this.red, this.ir);
    if (r == null) return null;
    return clamp(SPO2_A - SPO2_B * r, 70, 100);
  }

  reset(): void {
    this.red = [];
    this.ir = [];
  }
}

/** R = (AC_red/DC_red)/(AC_ir/DC_ir), where AC = peak-to-peak and DC = window mean. */
export function ratioOfRatios(red: readonly number[], ir: readonly number[]): number | null {
  const acRed = peakToPeak(red);
  const acIr = peakToPeak(ir);
  const dcRed = avg(red);
  const dcIr = avg(ir);
  if (dcRed <= 0 || dcIr <= 0 || acIr <= 0) return null;
  const num = acRed / dcRed;
  const den = acIr / dcIr;
  if (den <= 0) return null;
  return num / den;
}

function peakToPeak(v: readonly number[]): number {
  let lo = Infinity;
  let hi = -Infinity;
  for (const x of v) {
    if (x < lo) lo = x;
    if (x > hi) hi = x;
  }
  return hi - lo;
}

function avg(v: readonly number[]): number {
  let s = 0;
  for (const x of v) s += x;
  return v.length ? s / v.length : 0;
}
