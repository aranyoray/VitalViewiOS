//
//  DSPConstants.swift
//  MoniVitals
//
//  DSP constants — the single source of truth is docs/DSP.md. These values MUST match
//  that document and the web implementation (web/src/dsp/constants.ts) exactly so the
//  Swift and TypeScript DSP produce identical results.
//
//  MOTION_THRESH / CONTACT_THRESH are user-adjustable in Settings; the rest are fixed.
//

import Foundation

/// Fixed DSP constants. Names mirror `web/src/dsp/constants.ts`.
enum DSPConstants {
    // R-peak detector band-pass cutoffs.
    static let ecgBpLowHz = 5.0
    static let ecgBpHighHz = 15.0
    static let qrsIntegMs = 150.0
    static let qrsRefractoryMs = 200.0
    static let qrsThreshFrac = 0.25

    // PAT plausibility window + reporting. The upper bound is 600 ms (not the ~400 ms
    // physiologic max) because recorded monitor PPG/PLETH channels add internal
    // filtering/display delay (~100–200 ms), inflating the measured R→foot interval.
    static let patMinMs = 50.0
    static let patMaxMs = 600.0
    static let patMedianN = 7

    // Heart-rate reporting.
    static let hrMedianN = 5
    static let hrMinBpm = 30.0
    static let hrMaxBpm = 220.0

    // SpO2 estimate: SpO2 = SPO2_A - SPO2_B * R (R = ratio-of-ratios). Estimate only.
    static let spo2A = 110.0
    static let spo2B = 25.0

    // BioZ motion / contact.
    static let motionWindowMs = 500.0
    static let motionThresh = 4.0e6
    static let contactThresh = 5_000_000.0
    static let z0GoodMohm = 200_000.0
    static let z0BadMohm = 1_500_000.0

    /// Microseconds per second — used everywhere we convert device time.
    static let usPerS = 1_000_000.0
}
