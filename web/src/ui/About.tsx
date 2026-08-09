import { useAppStore } from '../store/appStore';
import { ConsentText, DisclaimerText } from './Disclaimer';

export function AboutScreen() {
  const modelName = useAppStore((s) => s.modelName);
  return (
    <>
      <div className="card">
        <h2>About MoniVitals</h2>
        <DisclaimerText />
      </div>
      <div className="card">
        <h3>Consent &amp; data handling</h3>
        <ConsentText />
      </div>
      <div className="card">
        <h3>How it works</h3>
        <p className="small muted">
          MoniVitals runs entirely in your browser on a real recorded biosignal (a PhysioNet
          BIDMC ECG + PPG recording) — no network. The on-device model detects R-peaks
          (Pan–Tompkins) and PPG feet (intersecting tangents) on a shared clock to compute Pulse
          Arrival Time, derives heart rate and an SpO₂ estimate, gauges contact and motion from the
          BioZ channel, and demonstrates BioZ-gated ECG cleaning. A per-subject linear PAT→BP model
          can be calibrated against a reference cuff. All processing is documented in
          <code>docs/DSP.md</code> and shared with the iOS app.
        </p>
        <table>
          <tbody>
            <tr><th>Model</th><td><code>{modelName}</code></td></tr>
            <tr><th>Data</th><td>Real recorded biosignal (PhysioNet BIDMC) — replayed locally in-browser</td></tr>
            <tr><th>Storage</th><td>Local only (IndexedDB) — no cloud sync</td></tr>
          </tbody>
        </table>
      </div>
    </>
  );
}
