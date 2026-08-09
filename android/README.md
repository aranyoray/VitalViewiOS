# MoniVitals — Android app

A Jetpack Compose (Kotlin, minSdk 26) companion app for the experimental ECG / BioZ / PPG
wearable. It is a **line-for-line port of the [iOS app](../ios)** and mirrors the
[web app](../web); all three share the algorithm / protocol / export specifications in
[`../docs`](../docs).

> ⚠️ **MoniVitals is a research / science-fair / educational tool, NOT a medical device.**
> It must not be used for diagnosis or any clinical decision. Heart rate, SpO₂, pulse
> arrival time (PAT), and blood-pressure values are uncalibrated *estimates*.

## Building

```bash
cd android
./gradlew assembleDebug        # debug APK  -> app/build/outputs/apk/debug/
./gradlew assembleRelease      # signed release APK (see "Signing")
./gradlew installDebug         # build + install on a connected device/emulator
./gradlew test                 # JVM unit tests (DSP / parser round-trip / calibration)
```

Requirements: **JDK 17** and the Android SDK (compileSdk 35, build-tools 34+). Point Gradle
at your SDK via `local.properties` (`sdk.dir=…`). The Gradle wrapper pins Gradle 8.10.2;
AGP 8.6.1, Kotlin 2.0.21 (with the Compose compiler plugin).

- **BLE requires a real device.** The emulator cannot scan/connect, but **Mock mode**
  makes every screen fully usable without hardware.
- Runtime BLE permissions are requested on demand: `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`
  on Android 12+, `ACCESS_FINE_LOCATION` on Android 8–11 (declared in the manifest).

## Signing

Release builds read `keystore.properties` (gitignored) at the project root:

```properties
storeFile=keystores/monivitals-release.jks
storePassword=…
keyAlias=monivitals
keyPassword=…
```

If `keystore.properties` (or the keystore file) is absent, the release build **falls back
to the debug keystore** so the project always produces a runnable — though not
Play-signable — APK. A dedicated release keystore is included for local builds; rotate it
before any real distribution.

## Architecture

The layers match the iOS app and are kept cleanly separated (package `com.monivitals`):

```
ble/     Protocol (UUIDs / opcodes / rate tables / sentinels), Packets, Parsers,
         Encoders — little-endian via a hand-rolled reader/writer, K derived from length
dsp/     DSPConstants (== docs/DSP.md), Filters (Biquad / derivative / moving avg),
         RollingStats, RPeakDetector (Pan–Tompkins + back-search), PpgFootDetector
         (intersecting tangents), PatEstimator, HeartRateEstimator, Spo2Estimator,
         BioZ (ContactMotion + gateEcg), Calibration (OLS / Pearson / fit / predict),
         MetricsEngine
source/  Timebase (uint32 wrap extender + SeqTracker + clock offset), DataSource
         (interface + SharedFlow event hub + ConnectionState), MockSignal (deterministic
         synthetic ECG/PPG/BioZ + exact PAT/HR truth), MockSource (executor-driven),
         BleSource (BluetoothGatt wrapper with a serial op queue)
model/   Models (@Serializable data classes), Store (dependency-light local JSON
         persistence), Recorder (chunked flush pipeline), CSVExport (docs/CSV_FORMAT.md
         bundle → shareable .zip)
ui/      AppViewModel (state holder), WaveBuffers (RingBuffer), WaveformStrip (Compose
         Canvas + frame tick), UIHelpers, Connect / Dashboard / Recorder / Calibration /
         Gating / Review / Settings screens, Onboarding, RootScreen, Theme
MainActivity  Compose entry point, onboarding gate, BLE permission broker
```

### Data flow

`DataSource` (Mock or BLE) publishes decoded packets on **SharedFlows** (the Combine
`PassthroughSubject` equivalent). `AppViewModel` collects them on the main thread and pushes
high-rate samples into **non-reactive `WaveBuffer` ring buffers** and the `MetricsEngine`,
and (when recording) into `Recorder`. `Canvas`-based live strips read the ring buffers
directly on each animation frame, so high-rate sample data never flows through reactive
state. A 250 ms coroutine tick snapshots the engine and publishes throttled metrics.

### Parity with the iOS / web apps

- BLE UUIDs, opcodes, packet layouts, rate tables, and sentinels come from
  [`docs/BLE_PROTOCOL.md`](../docs/BLE_PROTOCOL.md) and match `ios/MoniVitals/BLE` and
  `web/src/ble`.
- DSP constants and algorithms come from [`docs/DSP.md`](../docs/DSP.md); the Kotlin DSP is
  a direct port of the Swift/TypeScript DSP (`Double` arithmetic matches IEEE-754, so
  synthetic-signal detector outputs are comparable).
- CSV export matches [`docs/CSV_FORMAT.md`](../docs/CSV_FORMAT.md): fixed column order,
  RFC-4180 escaping, blank-for-invalid cells, `z0` forward-fill, JS-style number
  formatting.

### Deviations from iOS

- **Persistence:** iOS uses a JSON-file store under Application Support; Android uses the
  same JSON-file scheme under the app's private `filesDir`. Same operations, local-first.
- **Export container:** iOS writes a bundle *folder*; Android zips the identical files into
  a single `.zip` shared via `FileProvider` (the web app also emits `.zip`).
- **Event delivery:** Combine `PassthroughSubject` → Kotlin `MutableSharedFlow`.
- **CoreBluetooth → BluetoothGatt:** `BleSource` wraps `BluetoothGatt` (scan by service
  UUID, connect, discover, enable notifications through a serial op queue, parse,
  timebase-extend, seq-track, write opcodes, exponential-backoff reconnect).
- **Charts:** Swift Charts static plots (calibration scatter, review waveforms) are drawn
  with a Compose `Canvas` to avoid an extra dependency.
```
