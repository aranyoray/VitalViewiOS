# VitalView

Companion apps — **web** and **native iOS** — for a battery-powered wrist/forearm
wearable that streams biosignals over Bluetooth Low Energy (BLE):

- **ECG** (single-arm bipolar lead ≈ Lead I) and **bioimpedance (BioZ)** from a
  MAX30001 analog front-end, co-sampled off one clock.
- **PPG** (green primary; red + IR for SpO₂) from a MAX30101 optical sensor.
- Driven by an ESP32 (Adafruit HUZZAH32).

The apps connect over BLE, visualize live waveforms, run recording sessions for a
validation study, compute derived metrics (HR, SpO₂, **Pulse Arrival Time**, a
**cuffless blood-pressure estimate**, signal-quality / motion indicators), support
**per-subject PAT→BP calibration** against a reference cuff, and **export CSV** for
offline analysis in Python.

> ⚠️ **This is a research / science-fair / educational tool, not a medical device.**
> It must not be used for diagnosis or any clinical decision. SpO₂ and blood-pressure
> values are uncalibrated *estimates*.

---

## Repository layout

```
docs/            Shared specifications — the single source of truth for both apps
  BLE_PROTOCOL.md  GATT service, characteristics, packet layouts, opcodes
  CSV_FORMAT.md    Session export bundle (one CSV per stream + metadata JSON)
  DSP.md           Signal-processing algorithms + constants (mirrored in TS & Swift)

web/             React + TypeScript + Vite web app (Web Bluetooth)
  src/ble/         GATT client + packet parsers/encoders + protocol constants
  src/source/      DataSource interface; BleSource + MockSource behind it
  src/dsp/         Shared DSP (R-peak, PPG foot, PAT, HR, SpO₂, gating, calibration)
  src/model/       Types + Dexie (IndexedDB) storage + CSV export
  src/store/       Zustand app state
  src/ui/          Onboarding, Connect, Dashboard, Recorder, Calibration, Gating,
                   Review, Settings
  src/**/*.test.ts Vitest unit tests (DSP validated against mock ground truth)

ios/             SwiftUI (iOS 16+) app, CoreBluetooth — mirrors the web architecture
  VitalView/BLE/   CBCentralManager wrapper + parsers + protocol constants
  VitalView/Source/ DataSource protocol; BleSource + MockSource
  VitalView/DSP/   Same algorithms / constants as the web DSP module
  VitalView/Model/ Models + persistence + CSV export
  VitalView/Views/ SwiftUI screens mirroring the web UI
  project.yml      XcodeGen spec (generate the .xcodeproj with `xcodegen generate`)
```

The three layers — **BLE / data model / DSP / UI** — are kept cleanly separated on
both platforms. The DSP algorithms and their constants are defined once in
[`docs/DSP.md`](docs/DSP.md) and implemented identically in TypeScript and Swift.

## Build status / how this was authored

This monorepo was built "shared-core first": the BLE/CSV/DSP contracts were locked in
`docs/`, then the **web app** was implemented and unit-tested, and the **iOS app** was
authored to mirror it.

- **Web** — buildable, runnable, and unit-tested. See [`web/README.md`](web/README.md).
- **iOS** — authored as a complete, idiomatic SwiftUI/CoreBluetooth project but **not
  compiled in CI** (no Swift toolchain in the build environment). Open in Xcode 15+
  after generating the project (`cd ios && xcodegen generate`). See
  [`ios/README.md`](ios/README.md).

## Quick start (web)

```bash
cd web
npm install
npm run dev        # open the printed URL in Chrome or Edge (desktop) / Chrome (Android)
npm test           # run the DSP + parser unit tests
npm run build      # production build
```

Web Bluetooth is **not available in Safari / iOS** — which is exactly why a native iOS
app exists. The web app detects unsupported browsers and explains. Every screen is
reachable without hardware via **Mock mode** (toggle in the Connect screen).

## Milestones

The project is built in the order M1→M5 (MVP → PPG/BioZ dashboard → PAT/BP/calibration →
gated ECG + review + iOS parity → settings/robustness/polish). See the task brief for
details.
