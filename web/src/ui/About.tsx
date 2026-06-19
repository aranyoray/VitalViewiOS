import { SERVICE_UUID } from '../ble/protocol';
import { ConsentText, DisclaimerText } from './Disclaimer';

export function AboutScreen() {
  return (
    <>
      <div className="card">
        <h2>About VitalView</h2>
        <DisclaimerText />
      </div>
      <div className="card">
        <h3>Consent &amp; data handling</h3>
        <ConsentText />
      </div>
      <div className="card">
        <h3>How it works</h3>
        <p className="small muted">
          VitalView connects to an ESP32-based wearable (MAX30001 ECG/BioZ + MAX30101 PPG) over
          Bluetooth Low Energy and visualizes the live waveforms. It detects R-peaks (Pan–Tompkins)
          and PPG feet (intersecting tangents) on a shared device clock to compute Pulse Arrival
          Time, derives heart rate and an SpO₂ estimate, gauges contact and motion from the BioZ
          channel, and demonstrates BioZ-gated ECG cleaning. A per-subject linear PAT→BP model can
          be calibrated against a reference cuff. All processing is documented in
          <code> docs/DSP.md</code> and shared with the iOS app.
        </p>
        <table>
          <tbody>
            <tr><th>BLE service UUID</th><td><code>{SERVICE_UUID}</code></td></tr>
            <tr><th>Transport</th><td>Bluetooth Low Energy (Web Bluetooth)</td></tr>
            <tr><th>Storage</th><td>Local only (IndexedDB) — no cloud sync</td></tr>
          </tbody>
        </table>
      </div>
    </>
  );
}
