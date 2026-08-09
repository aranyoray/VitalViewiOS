# MoniVitals — web app

React + TypeScript + Vite companion app for the MoniVitals ECG/BioZ/PPG wearable. **Not a
medical device** — a research / educational tool.

## Run

```bash
npm install
npm run dev        # open the printed URL in Chrome or Edge (desktop) / Chrome (Android)
npm test           # unit + integration tests
npm run build      # type-check + production build
npm run typecheck  # type-check only
```

> **Web Bluetooth** works in Chrome/Edge (desktop) and Chrome (Android) but **not in
> Safari / iOS** — that's why the native iOS app exists. The app detects this and
> explains it. **Mock mode** makes every screen usable with no hardware: open the app,
> accept the disclaimer/consent, go to **Connect → Connect mock device → Start
> streaming**.

## Architecture

```
src/
  ble/      Protocol constants, typed packets, length-driven parsers, encoders
  source/   DataSource interface; MockSource + BleSource behind it; mock signal generator;
            timebase (uint32 wrap extension, dropped-packet tracking, clock offset)
  dsp/      Shared, unit-tested DSP — R-peak (Pan–Tompkins), PPG foot (intersecting
            tangents), PAT, HR, SpO2, contact/motion, BioZ-gated ECG, PAT→BP calibration,
            and a MetricsEngine wiring them together
  model/    Types, Dexie (IndexedDB) storage, streaming Recorder, CSV/ZIP export
  live/     Non-reactive ring buffers + engine read by the canvas on rAF
  store/    Zustand store orchestrating source → buffers → engine → recorder
  ui/       Onboarding gate, Connect, Dashboard, Recorder, Calibration, Gating, Review,
            Settings, About
```

The BLE / data-model / DSP / UI layers are cleanly separated. High-rate sample data lives
in `live/` ring buffers (mutated at full rate, drawn on `requestAnimationFrame`); only
throttled metrics/counters are in React state, so the UI is never re-rendered per sample.

The DSP module and its constants mirror [`../docs/DSP.md`](../docs/DSP.md) and the iOS
implementation. They are unit-tested against the mock generator's **known ground truth**
(end-to-end PAT recovery within 25 ms; HR, SpO₂, gating, calibration, BLE round-trips).

## Tests

```
npm test
```

Covers: BLE packet round-trips, timebase wrap / dropped-packet tracking, R-peak detection
+ HR, end-to-end PAT vs ground truth, SpO₂ ratio-of-ratios, BioZ gating, PAT→BP
regression, CSV escaping / bundle building / ZIP (CRC32), and a jsdom integration test
that boots the app, clears onboarding, and connects the mock device.

## Notes

- Storage is local-first (IndexedDB via Dexie); export is explicit (CSV ZIP bundle). No
  cloud sync.
- Subjects are identified only by a non-identifying code (no PII).
