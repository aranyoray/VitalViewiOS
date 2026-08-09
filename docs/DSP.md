# Signal processing — algorithm specification

These algorithms are implemented **identically** in TypeScript (`web/src/dsp`) and Swift
(`ios/MoniVitals/DSP`). Constants live in one place per platform (`dsp/constants.ts`,
`DSP/DSPConstants.swift`) and must match this document. The web implementation is
**unit-tested against the mock generator's known ground truth** (especially PAT).

Firmware may also compute these; a setting selects the source (firmware vs app) so the
algorithms can be iterated without reflashing.

## Constants

| Name               | Value      | Meaning                                                        |
|--------------------|------------|----------------------------------------------------------------|
| `ECG_BP_LOW_HZ`    | 5.0        | R-peak detector bandpass low cutoff                            |
| `ECG_BP_HIGH_HZ`   | 15.0       | R-peak detector bandpass high cutoff                           |
| `QRS_INTEG_MS`     | 150        | Moving-window integration width                                |
| `QRS_REFRACTORY_MS`| 200        | Minimum spacing between R-peaks                                |
| `QRS_THRESH_FRAC`  | 0.25       | Adaptive threshold = `frac` between running noise & signal est |
| `PAT_MIN_MS`       | 50         | Reject PAT below this (implausible)                            |
| `PAT_MAX_MS`       | 400        | Reject PAT above this (implausible)                            |
| `PAT_MEDIAN_N`     | 7          | Rolling-median window for reported PAT                         |
| `HR_MEDIAN_N`      | 5          | Rolling-median window for reported HR                          |
| `HR_MIN_BPM`       | 30         | Reject R-R intervals outside [30,220] bpm                      |
| `HR_MAX_BPM`       | 220        |                                                                |
| `SPO2_A`           | 110.0      | SpO₂ estimate: `SpO2 = SPO2_A − SPO2_B · R`                     |
| `SPO2_B`           | 25.0       | (R = ratio-of-ratios). **Estimate only — needs calibration.**  |
| `MOTION_WINDOW_MS` | 500        | Window for ΔZ-variance motion metric & gating                  |
| `MOTION_THRESH`    | 4.0e6      | ΔZ variance above this ⇒ motion / bad window (ADC counts²)     |
| `CONTACT_THRESH`   | 5_000_000  | \|Z₀ − Z₀_baseline\| (milliohm) above this ⇒ bad contact        |
| `Z0_GOOD_MOHM`     | 200_000    | Z₀ at/below this maps to contact quality 100                   |
| `Z0_BAD_MOHM`      | 1_500_000  | Z₀ at/above this maps to contact quality 0                     |

`MOTION_THRESH` / `CONTACT_THRESH` are adjustable in Settings; the others are fixed.

## R-peak detection (Pan–Tompkins-style)

Streaming detector over the ECG signal at its native `sample_rate_hz`:

1. **Bandpass 5–15 Hz** — 2nd-order Butterworth bandpass (biquad, Direct Form II
   transposed), coefficients computed from cutoffs and `fs`. Isolates QRS energy.
2. **Derivative** — 5-point derivative `y[n] = (2x[n] + x[n-1] − x[n-3] − 2x[n-4]) / 8`
   (scaled for `fs`). Emphasizes slope.
3. **Square** — `y[n]²`. Makes everything positive, boosts large slopes.
4. **Moving-window integration** — width `QRS_INTEG_MS` (≈150 ms). Produces a smooth
   feature whose peaks mark QRS complexes.
5. **Adaptive threshold + refractory** — track running estimates of signal peak
   (`SPK`) and noise peak (`NPK`); threshold `= NPK + QRS_THRESH_FRAC·(SPK − NPK)`.
   A local maximum above threshold and ≥ `QRS_REFRACTORY_MS` after the last peak is an
   R-peak. The integration introduces a known group delay (≈ window/2 + filter delay)
   which is **subtracted** so the reported R-peak `t_us` aligns with the raw ECG peak.

**Output:** R-peak timestamps in device microseconds.

## PPG foot detection

Detect the **foot (onset)** of each PPG pulse on the green channel:

1. Lightly low-pass the green signal (moving average ≈ 1/20 of a pulse period).
2. Compute the first derivative; find the **maximum-upslope** point of each pulse
   (steepest rise) using peak detection on the derivative with a refractory of
   `QRS_REFRACTORY_MS`.
3. **Intersecting tangents:** the foot is the intersection of (a) the horizontal line at
   the pre-upstroke minimum and (b) the tangent line through the max-upslope point.
   This is robust to baseline wander and matches the standard PAT foot definition.

**Output:** foot timestamps in device microseconds.

## PAT (Pulse Arrival Time)

```
for each PPG foot f:
    r = last R-peak with t(r) ≤ t(f) and (t(f) − t(r)) ∈ [PAT_MIN_MS, PAT_MAX_MS]
    if r exists:
        PAT = t(f) − t(r)            # device microseconds
        push PAT to a rolling buffer of size PAT_MEDIAN_N
report median(PAT_buffer)            # invalid until the buffer has ≥ 3 samples
```

## HR (heart rate)

From consecutive R-peaks: `RR = t(rₙ) − t(rₙ₋₁)`; `bpm = 60·10⁶ / RR_us`. Reject RR
outside `[HR_MIN_BPM, HR_MAX_BPM]`. Report `median` over the last `HR_MEDIAN_N` beats.

## SpO₂ (estimate — clearly labeled)

Ratio-of-ratios on red/IR over a sliding window (≈ 2 s):
```
R = (AC_red / DC_red) / (AC_ir / DC_ir)
SpO2_est = SPO2_A − SPO2_B · R            # clamped to [70, 100]
```
where `AC` is peak-to-peak and `DC` is the window mean of each channel. **This is an
uncalibrated estimate and must be labeled as such in the UI.**

## Contact quality (from BioZ Z₀)

```
level   = clamp(map(Z0, Z0_GOOD_MOHM→100, Z0_BAD_MOHM→0), 0, 100)
stability = 100 · (1 − clamp(stddev(Z0_window)/Z0_mean, 0, 1))
contact_quality = round(0.6·level + 0.4·stability)      # 0..100
```

## Motion (from BioZ ΔZ)

```
v = variance(dZ over MOTION_WINDOW_MS)
motion = clamp(round(255 · v / MOTION_THRESH), 0, 255)   # 0 = still
```

## BioZ-gated ECG cleaning (the project's core thesis)

Slide a `MOTION_WINDOW_MS` window over the co-sampled ECG/BioZ:
```
window_bad = variance(dZ in window) > MOTION_THRESH
          or |Z0 − Z0_baseline| > CONTACT_THRESH
gated_ecg  = ecg samples whose window is good (bad windows blanked / flagged)
good_pct   = good_windows / total_windows · 100
```
`Z0_baseline` is a slow running median of `Z0`. The Gating view shows **raw vs gated ECG
side-by-side** plus the good-segment percentage; thresholds are adjustable in Settings.

## PAT → BP calibration

Per-subject linear regression. Default model `linear_invPAT`:
```
SBP = a_sbp + b_sbp · (1 / PAT_seconds)
DBP = a_dbp + b_dbp · (1 / PAT_seconds)
```
(An alternate `linear_PAT` model regresses on `PAT` directly; selectable in Settings.)

Fit by ordinary least squares over the collected `(PAT, cuff SBP/DBP)` reference pairs.
Report **Pearson R** and **RMSE (mmHg)** for SBP and DBP, and show a scatter plot with
the fit line. Estimated BP is labeled **"uncalibrated"** until a model with ≥ 3 pairs
exists for the subject. Re-calibration replaces the model.

### Why 1/PAT?
PAT relates inversely to pulse-wave velocity and hence to BP over physiological ranges,
so BP is approximately linear in `1/PAT`. This is a coarse, per-subject empirical fit for
an educational demonstration — **not** a validated clinical model.
