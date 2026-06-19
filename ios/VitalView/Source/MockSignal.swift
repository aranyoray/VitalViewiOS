//
//  MockSignal.swift
//  VitalView
//
//  Synthetic biosignal generator (mock mode). Produces realistic ECG (QRS morphology),
//  PPG (pulse wave whose FOOT is phase-lagged from the R-peak by an exact PAT), and BioZ
//  (stable Z0 + small pulsatile ΔZ, with injectable motion bursts).
//
//  Ground truth is exact and deterministic: R-peaks occur at k·RR and PPG feet at
//  k·RR + PAT, so the DSP can be unit-tested against known HR / PAT / SpO2.
//
//  Ported line-for-line from web/src/source/mockSignal.ts. Double arithmetic (incl. sin
//  and floor) matches JavaScript IEEE-754, so the synthetic signal is bit-comparable.
//

import Foundation

/// A high-variance ΔZ injection window driving the motion/gating logic.
struct MotionBurst {
    var startUs: Double
    var endUs: Double
    var severity: Double
}

/// Tunable parameters of the synthetic signal.
struct MockParams {
    var hrBpm: Double
    var patMs: Double
    var ecgRateHz: Int
    var ppgRateHz: Int
    var biozRateHz: Int
    var ecgAmplitude: Double
    var ecgNoise: Double
    var ppgGreenDc: Double
    var ppgGreenAc: Double
    /// Target SpO2 used to set the red/IR AC ratio (ground truth for the SpO2 test).
    var spo2Target: Double
    var z0Baseline: Double
    var z0Noise: Double
    var dzAmplitude: Double
    var dzNoise: Double
    var seed: Double
    /// Motion bursts inject high-variance ΔZ (drives the motion/gating logic).
    var motionBursts: [MotionBurst]

    static let `default` = MockParams(
        hrBpm: 70,
        patMs: 220,
        ecgRateHz: 256,
        ppgRateHz: 100,
        biozRateHz: 64,
        ecgAmplitude: 1200,
        ecgNoise: 8,
        ppgGreenDc: 120_000,
        ppgGreenAc: 9000,
        spo2Target: 98,
        z0Baseline: 300_000,
        z0Noise: 1500,
        dzAmplitude: 400,
        dzNoise: 60,
        seed: 1,
        motionBursts: []
    )
}

/// Deterministic value-noise in [-1, 1] from a real-valued coordinate.
private func valNoise(_ x: Double) -> Double {
    let s = sin(x * 12.9898) * 43758.5453
    return 2 * (s - floor(s)) - 1
}

final class MockSignal {
    var p: MockParams

    init(_ params: MockParams = .default) {
        self.p = params
    }

    /// R–R interval (µs); recomputed from the current HR so it tracks live changes.
    private var rrUs: Double {
        (60 / p.hrBpm) * DSPConstants.usPerS
    }

    var rrMicros: Double { rrUs }

    /// R-peak timestamps (µs) within `[t0, t1)` — the exact PAT/HR ground truth.
    func rPeakTimes(_ t0: Double, _ t1: Double) -> [Double] {
        var out: [Double] = []
        let kStart = Int((t0 / rrUs).rounded(.up))
        let kEnd = Int(((t1 - 1) / rrUs).rounded(.down))
        if kEnd >= kStart {
            for k in kStart...kEnd { out.append(Double(k) * rrUs) }
        }
        return out
    }

    /// PPG foot timestamps (µs) within `[t0, t1)`.
    func footTimes(_ t0: Double, _ t1: Double) -> [Double] {
        let patUs = p.patMs * 1000
        return rPeakTimes(t0 - patUs, t1 - patUs).map { $0 + patUs }
    }

    func ecgAt(_ tUs: Double) -> Double {
        let k0 = Int((tUs / rrUs).rounded(.down))
        var v = 0.0
        for k in (k0 - 1)...(k0 + 1) {
            v += qrs((tUs - Double(k) * rrUs) / DSPConstants.usPerS)
        }
        return v * p.ecgAmplitude + p.ecgNoise * valNoise(p.seed + tUs * 1e-3)
    }

    func greenAt(_ tUs: Double) -> Double {
        p.ppgGreenDc + p.ppgGreenAc * pulseSum(tUs)
            + p.ppgGreenAc * 0.01 * valNoise(p.seed + 7 + tUs * 1e-3)
    }

    func redAt(_ tUs: Double) -> Double {
        // R = (AC_red/DC_red)/(AC_ir/DC_ir); with equal DCs, AC_red/AC_ir = R = (110-SpO2)/25.
        let r = (110 - p.spo2Target) / 25
        let ac = p.ppgGreenAc * r
        return p.ppgGreenDc + ac * pulseSum(tUs)
            + ac * 0.01 * valNoise(p.seed + 11 + tUs * 1e-3)
    }

    func irAt(_ tUs: Double) -> Double {
        let ac = p.ppgGreenAc
        return p.ppgGreenDc + ac * pulseSum(tUs)
            + ac * 0.01 * valNoise(p.seed + 13 + tUs * 1e-3)
    }

    func z0At(_ tUs: Double) -> Double {
        let drift = 4000 * sin((2 * Double.pi * tUs) / (20 * DSPConstants.usPerS))
        return p.z0Baseline + drift + p.z0Noise * valNoise(p.seed + 17 + tUs * 1e-3)
    }

    func dzAt(_ tUs: Double) -> Double {
        let patUs = p.patMs * 1000
        let pulsatile = p.dzAmplitude * pulseSum(tUs - patUs)
        var motion = 0.0
        for b in p.motionBursts {
            if tUs >= b.startUs && tUs < b.endUs {
                motion += b.severity * 3000 * valNoise(p.seed + 23 + tUs * 1e-3)
            }
        }
        return pulsatile + p.dzNoise * valNoise(p.seed + 19 + tUs * 1e-3) + motion
    }

    /// Sum of the pulse waveform over nearby beats; foot of beat k is at k·RR + PAT.
    private func pulseSum(_ tUs: Double) -> Double {
        let patUs = p.patMs * 1000
        let k0 = Int(((tUs - patUs) / rrUs).rounded(.down))
        var v = 0.0
        for k in (k0 - 1)...(k0 + 1) {
            let foot = Double(k) * rrUs + patUs
            v += pulse((tUs - foot) / DSPConstants.usPerS)
        }
        return v
    }
}

/// QRS-ish morphology: dominant R at τ=0, flanking Q/S, broad T, small P. τ in seconds.
private func qrs(_ tau: Double) -> Double {
    func g(_ a: Double, _ c: Double, _ w: Double) -> Double {
        a * exp(-pow((tau - c) / w, 2))
    }
    return g(1.0, 0.0, 0.012)      // R
        + g(-0.15, -0.022, 0.012)  // Q
        + g(-0.2, 0.022, 0.014)    // S
        + g(0.22, 0.3, 0.06)       // T
        + g(0.08, -0.18, 0.04)     // P
}

/// Alpha-function pulse with onset (foot) exactly at τ=0, plus a small dicrotic bump.
private func pulse(_ tau: Double) -> Double {
    if tau < 0 { return 0 }
    let t0 = 0.12 // systolic peak time (s)
    func alpha(_ t: Double, _ k: Double) -> Double {
        t < 0 ? 0 : (t / k) * exp(1 - t / k)
    }
    return alpha(tau, t0) + 0.25 * alpha(tau - 0.32, 0.1)
}
