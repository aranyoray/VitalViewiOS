/**
 * Synthetic biosignal generator (mock mode, §8). Produces realistic ECG (QRS
 * morphology), PPG (pulse wave whose FOOT is phase-lagged from the R-peak by an exact
 * PAT), and BioZ (stable Z₀ + small pulsatile ΔZ, with injectable motion bursts).
 *
 * Ground truth is exact and deterministic: R-peaks occur at k·RR and PPG feet at
 * k·RR + PAT, so the DSP can be unit-tested against known HR / PAT / SpO₂.
 */
import { US_PER_S } from '../dsp/constants';

export interface MockParams {
  hrBpm: number;
  patMs: number;
  ecgRateHz: number;
  ppgRateHz: number;
  biozRateHz: number;
  ecgAmplitude: number;
  ecgNoise: number;
  ppgGreenDc: number;
  ppgGreenAc: number;
  /** Target SpO₂ used to set the red/IR AC ratio (ground truth for the SpO₂ test). */
  spo2Target: number;
  z0Baseline: number;
  z0Noise: number;
  dzAmplitude: number;
  dzNoise: number;
  seed: number;
  /** Motion bursts inject high-variance ΔZ (drives the motion/gating logic). */
  motionBursts: { startUs: number; endUs: number; severity: number }[];
}

export const DEFAULT_MOCK_PARAMS: MockParams = {
  hrBpm: 70,
  patMs: 220,
  ecgRateHz: 256,
  ppgRateHz: 100,
  biozRateHz: 64,
  ecgAmplitude: 1200,
  ecgNoise: 8,
  ppgGreenDc: 120000,
  ppgGreenAc: 9000,
  spo2Target: 98,
  z0Baseline: 300000,
  z0Noise: 1500,
  dzAmplitude: 400,
  dzNoise: 60,
  seed: 1,
  motionBursts: [],
};

/** Deterministic value-noise in [-1, 1] from a real-valued coordinate. */
function valNoise(x: number): number {
  const s = Math.sin(x * 12.9898) * 43758.5453;
  return 2 * (s - Math.floor(s)) - 1;
}

export class MockSignal {
  readonly p: MockParams;
  private readonly rrUs: number;

  constructor(params: Partial<MockParams> = {}) {
    this.p = { ...DEFAULT_MOCK_PARAMS, ...params };
    this.rrUs = (60 / this.p.hrBpm) * US_PER_S;
  }

  get rrMicros(): number {
    return this.rrUs;
  }

  /** R-peak timestamps (µs) within [t0, t1) — the exact PAT/HR ground truth. */
  rPeakTimes(t0: number, t1: number): number[] {
    const out: number[] = [];
    const kStart = Math.ceil(t0 / this.rrUs);
    const kEnd = Math.floor((t1 - 1) / this.rrUs);
    for (let k = kStart; k <= kEnd; k++) out.push(k * this.rrUs);
    return out;
  }

  /** PPG foot timestamps (µs) within [t0, t1). */
  footTimes(t0: number, t1: number): number[] {
    const patUs = this.p.patMs * 1000;
    return this.rPeakTimes(t0 - patUs, t1 - patUs).map((r) => r + patUs);
  }

  ecgAt(tUs: number): number {
    const k0 = Math.floor(tUs / this.rrUs);
    let v = 0;
    for (let k = k0 - 1; k <= k0 + 1; k++) {
      v += qrs((tUs - k * this.rrUs) / US_PER_S);
    }
    return v * this.p.ecgAmplitude + this.p.ecgNoise * valNoise(this.p.seed + tUs * 1e-3);
  }

  greenAt(tUs: number): number {
    return this.p.ppgGreenDc + this.p.ppgGreenAc * this.pulseSum(tUs) +
      this.p.ppgGreenAc * 0.01 * valNoise(this.p.seed + 7 + tUs * 1e-3);
  }

  redAt(tUs: number): number {
    // R = (AC_red/DC_red)/(AC_ir/DC_ir); with equal DCs, AC_red/AC_ir = R = (110-SpO2)/25.
    const r = (110 - this.p.spo2Target) / 25;
    const ac = this.p.ppgGreenAc * r;
    return this.p.ppgGreenDc + ac * this.pulseSum(tUs) +
      ac * 0.01 * valNoise(this.p.seed + 11 + tUs * 1e-3);
  }

  irAt(tUs: number): number {
    const ac = this.p.ppgGreenAc;
    return this.p.ppgGreenDc + ac * this.pulseSum(tUs) +
      ac * 0.01 * valNoise(this.p.seed + 13 + tUs * 1e-3);
  }

  z0At(tUs: number): number {
    const drift = 4000 * Math.sin((2 * Math.PI * tUs) / (20 * US_PER_S));
    return this.p.z0Baseline + drift + this.p.z0Noise * valNoise(this.p.seed + 17 + tUs * 1e-3);
  }

  dzAt(tUs: number): number {
    const patUs = this.p.patMs * 1000;
    const pulsatile = this.p.dzAmplitude * this.pulseSum(tUs - patUs);
    let motion = 0;
    for (const b of this.p.motionBursts) {
      if (tUs >= b.startUs && tUs < b.endUs) {
        motion += b.severity * 3000 * valNoise(this.p.seed + 23 + tUs * 1e-3);
      }
    }
    return pulsatile + this.p.dzNoise * valNoise(this.p.seed + 19 + tUs * 1e-3) + motion;
  }

  /** Sum of the pulse waveform over nearby beats; foot of beat k is at k·RR + PAT. */
  private pulseSum(tUs: number): number {
    const patUs = this.p.patMs * 1000;
    const k0 = Math.floor((tUs - patUs) / this.rrUs);
    let v = 0;
    for (let k = k0 - 1; k <= k0 + 1; k++) {
      const foot = k * this.rrUs + patUs;
      v += pulse((tUs - foot) / US_PER_S);
    }
    return v;
  }
}

/** QRS-ish morphology: dominant R at τ=0, flanking Q/S, broad T, small P. τ in seconds. */
function qrs(tau: number): number {
  const g = (a: number, c: number, w: number) => a * Math.exp(-(((tau - c) / w) ** 2));
  return (
    g(1.0, 0.0, 0.012) + // R
    g(-0.15, -0.022, 0.012) + // Q
    g(-0.2, 0.022, 0.014) + // S
    g(0.22, 0.3, 0.06) + // T
    g(0.08, -0.18, 0.04) // P
  );
}

/** Alpha-function pulse with onset (foot) exactly at τ=0, plus a small dicrotic bump. */
function pulse(tau: number): number {
  if (tau < 0) return 0;
  const t0 = 0.12; // systolic peak time (s)
  const alpha = (t: number, k: number) => (t < 0 ? 0 : (t / k) * Math.exp(1 - t / k));
  return alpha(tau, t0) + 0.25 * alpha(tau - 0.32, 0.1);
}
