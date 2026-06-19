/**
 * DSP constants — must match docs/DSP.md and ios/VitalView/DSP/DSPConstants.swift.
 * MOTION_THRESH / CONTACT_THRESH are user-adjustable in Settings; the rest are fixed.
 */
export const ECG_BP_LOW_HZ = 5.0;
export const ECG_BP_HIGH_HZ = 15.0;
export const QRS_INTEG_MS = 150;
export const QRS_REFRACTORY_MS = 200;
export const QRS_THRESH_FRAC = 0.25;

export const PAT_MIN_MS = 50;
export const PAT_MAX_MS = 400;
export const PAT_MEDIAN_N = 7;

export const HR_MEDIAN_N = 5;
export const HR_MIN_BPM = 30;
export const HR_MAX_BPM = 220;

export const SPO2_A = 110.0;
export const SPO2_B = 25.0;

export const MOTION_WINDOW_MS = 500;
export const MOTION_THRESH = 4.0e6;
export const CONTACT_THRESH = 5_000_000;
export const Z0_GOOD_MOHM = 200_000;
export const Z0_BAD_MOHM = 1_500_000;

/** Microseconds per second — used everywhere we convert device time. */
export const US_PER_S = 1_000_000;
