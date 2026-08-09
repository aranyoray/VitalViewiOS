//
//  DSPConstants.kt
//  MoniVitals (Android)
//
//  DSP constants — the single source of truth is docs/DSP.md. These values MUST match
//  that document and the web/iOS implementations exactly so all platforms' DSP produce
//  identical results.
//
//  MOTION_THRESH / CONTACT_THRESH are user-adjustable in Settings; the rest are fixed.
//
//  Ported from ios/MoniVitals/DSP/DSPConstants.swift (== web/src/dsp/constants.ts).
//

package com.monivitals.dsp

object DSPConstants {
    // R-peak detector band-pass cutoffs.
    const val ecgBpLowHz = 5.0
    const val ecgBpHighHz = 15.0
    const val qrsIntegMs = 150.0
    const val qrsRefractoryMs = 200.0
    const val qrsThreshFrac = 0.25

    // PAT plausibility window + reporting.
    const val patMinMs = 50.0
    // Widened from 400 to 600 ms: a recorded monitor's PLETH channel adds ~150 ms of
    // display/processing delay, inflating the measured R→foot (pulse-arrival) interval.
    const val patMaxMs = 600.0
    const val patMedianN = 7

    // Heart-rate reporting.
    const val hrMedianN = 5
    const val hrMinBpm = 30.0
    const val hrMaxBpm = 220.0

    // SpO2 estimate: SpO2 = SPO2_A - SPO2_B * R (R = ratio-of-ratios). Estimate only.
    const val spo2A = 110.0
    const val spo2B = 25.0

    // BioZ motion / contact.
    const val motionWindowMs = 500.0
    const val motionThresh = 4.0e6
    const val contactThresh = 5_000_000.0
    const val z0GoodMohm = 200_000.0
    const val z0BadMohm = 1_500_000.0

    /** Microseconds per second — used everywhere we convert device time. */
    const val usPerS = 1_000_000.0
}
