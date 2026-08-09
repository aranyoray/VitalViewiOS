//
//  MockSignal.kt
//  MoniVitals (Android)
//
//  Synthetic biosignal generator (mock mode). Produces realistic ECG (QRS morphology),
//  PPG (pulse wave whose FOOT is phase-lagged from the R-peak by an exact PAT), and BioZ
//  (stable Z0 + small pulsatile ΔZ, with injectable motion bursts).
//
//  Ground truth is exact and deterministic: R-peaks occur at k·RR and PPG feet at
//  k·RR + PAT, so the DSP can be unit-tested against known HR / PAT / SpO2.
//
//  Ported from ios/MoniVitals/Source/MockSignal.swift (== web/src/source/mockSignal.ts).
//

package com.monivitals.source

import com.monivitals.dsp.DSPConstants
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.sin

/** A high-variance ΔZ injection window driving the motion/gating logic. */
data class MotionBurst(
    val startUs: Double,
    val endUs: Double,
    val severity: Double,
)

/** Tunable parameters of the synthetic signal. */
data class MockParams(
    var hrBpm: Double,
    var patMs: Double,
    var ecgRateHz: Int,
    var ppgRateHz: Int,
    var biozRateHz: Int,
    var ecgAmplitude: Double,
    var ecgNoise: Double,
    var ppgGreenDc: Double,
    var ppgGreenAc: Double,
    /** Target SpO2 used to set the red/IR AC ratio (ground truth for the SpO2 test). */
    var spo2Target: Double,
    var z0Baseline: Double,
    var z0Noise: Double,
    var dzAmplitude: Double,
    var dzNoise: Double,
    var seed: Double,
    /** Motion bursts inject high-variance ΔZ (drives the motion/gating logic). */
    var motionBursts: MutableList<MotionBurst>,
) {
    companion object {
        val default: MockParams
            get() = MockParams(
                hrBpm = 70.0,
                patMs = 220.0,
                ecgRateHz = 256,
                ppgRateHz = 100,
                biozRateHz = 64,
                ecgAmplitude = 1200.0,
                ecgNoise = 8.0,
                ppgGreenDc = 120_000.0,
                ppgGreenAc = 9000.0,
                spo2Target = 98.0,
                z0Baseline = 300_000.0,
                z0Noise = 1500.0,
                dzAmplitude = 400.0,
                dzNoise = 60.0,
                seed = 1.0,
                motionBursts = mutableListOf(),
            )
    }
}

/** Deterministic value-noise in [-1, 1] from a real-valued coordinate. */
private fun valNoise(x: Double): Double {
    val s = sin(x * 12.9898) * 43758.5453
    return 2 * (s - floor(s)) - 1
}

class MockSignal(var p: MockParams = MockParams.default) {

    /** R–R interval (µs); recomputed from the current HR so it tracks live changes. */
    private val rrUs: Double
        get() = (60 / p.hrBpm) * DSPConstants.usPerS

    val rrMicros: Double get() = rrUs

    /** R-peak timestamps (µs) within `[t0, t1)` — the exact PAT/HR ground truth. */
    fun rPeakTimes(t0: Double, t1: Double): List<Double> {
        val out = mutableListOf<Double>()
        val kStart = ceil(t0 / rrUs).toInt()
        val kEnd = floor((t1 - 1) / rrUs).toInt()
        if (kEnd >= kStart) {
            for (k in kStart..kEnd) out.add(k * rrUs)
        }
        return out
    }

    /** PPG foot timestamps (µs) within `[t0, t1)`. */
    fun footTimes(t0: Double, t1: Double): List<Double> {
        val patUs = p.patMs * 1000
        return rPeakTimes(t0 - patUs, t1 - patUs).map { it + patUs }
    }

    fun ecgAt(tUs: Double): Double {
        val k0 = floor(tUs / rrUs).toInt()
        var v = 0.0
        for (k in (k0 - 1)..(k0 + 1)) {
            v += qrs((tUs - k * rrUs) / DSPConstants.usPerS)
        }
        return v * p.ecgAmplitude + p.ecgNoise * valNoise(p.seed + tUs * 1e-3)
    }

    fun greenAt(tUs: Double): Double {
        return p.ppgGreenDc + p.ppgGreenAc * pulseSum(tUs) +
            p.ppgGreenAc * 0.01 * valNoise(p.seed + 7 + tUs * 1e-3)
    }

    fun redAt(tUs: Double): Double {
        // R = (AC_red/DC_red)/(AC_ir/DC_ir); with equal DCs, AC_red/AC_ir = R = (110-SpO2)/25.
        val r = (110 - p.spo2Target) / 25
        val ac = p.ppgGreenAc * r
        return p.ppgGreenDc + ac * pulseSum(tUs) +
            ac * 0.01 * valNoise(p.seed + 11 + tUs * 1e-3)
    }

    fun irAt(tUs: Double): Double {
        val ac = p.ppgGreenAc
        return p.ppgGreenDc + ac * pulseSum(tUs) +
            ac * 0.01 * valNoise(p.seed + 13 + tUs * 1e-3)
    }

    fun z0At(tUs: Double): Double {
        val drift = 4000 * sin((2 * PI * tUs) / (20 * DSPConstants.usPerS))
        return p.z0Baseline + drift + p.z0Noise * valNoise(p.seed + 17 + tUs * 1e-3)
    }

    fun dzAt(tUs: Double): Double {
        val patUs = p.patMs * 1000
        val pulsatile = p.dzAmplitude * pulseSum(tUs - patUs)
        var motion = 0.0
        for (b in p.motionBursts) {
            if (tUs >= b.startUs && tUs < b.endUs) {
                motion += b.severity * 3000 * valNoise(p.seed + 23 + tUs * 1e-3)
            }
        }
        return pulsatile + p.dzNoise * valNoise(p.seed + 19 + tUs * 1e-3) + motion
    }

    /** Sum of the pulse waveform over nearby beats; foot of beat k is at k·RR + PAT. */
    private fun pulseSum(tUs: Double): Double {
        val patUs = p.patMs * 1000
        val k0 = floor((tUs - patUs) / rrUs).toInt()
        var v = 0.0
        for (k in (k0 - 1)..(k0 + 1)) {
            val foot = k * rrUs + patUs
            v += pulse((tUs - foot) / DSPConstants.usPerS)
        }
        return v
    }
}

/** QRS-ish morphology: dominant R at τ=0, flanking Q/S, broad T, small P. τ in seconds. */
private fun qrs(tau: Double): Double {
    fun g(a: Double, c: Double, w: Double): Double = a * exp(-((tau - c) / w).pow(2))
    return g(1.0, 0.0, 0.012) +      // R
        g(-0.15, -0.022, 0.012) +    // Q
        g(-0.2, 0.022, 0.014) +      // S
        g(0.22, 0.3, 0.06) +         // T
        g(0.08, -0.18, 0.04)         // P
}

/** Alpha-function pulse with onset (foot) exactly at τ=0, plus a small dicrotic bump. */
private fun pulse(tau: Double): Double {
    if (tau < 0) return 0.0
    val t0 = 0.12 // systolic peak time (s)
    fun alpha(t: Double, k: Double): Double = if (t < 0) 0.0 else (t / k) * exp(1 - t / k)
    return alpha(tau, t0) + 0.25 * alpha(tau - 0.32, 0.1)
}
