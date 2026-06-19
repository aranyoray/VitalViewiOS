import { useState } from 'react';
import { useAppStore } from '../store/appStore';
import { RATE_CODES, type StreamKind } from '../ble/protocol';
import type { CalibModel, MetricsSource } from '../model/types';
import { db } from '../model/db';
import { DEFAULT_MOCK_PARAMS } from '../source/mockSignal';

export function SettingsScreen() {
  const settings = useAppStore((s) => s.settings);
  const update = useAppStore((s) => s.updateSettings);
  const isMock = useAppStore((s) => s.isMock);
  const setMockParams = useAppStore((s) => s.setMockParams);
  const refreshSubjects = useAppStore((s) => s.refreshSubjects);

  const [mock, setMock] = useState({ hrBpm: DEFAULT_MOCK_PARAMS.hrBpm, patMs: DEFAULT_MOCK_PARAMS.patMs, spo2Target: DEFAULT_MOCK_PARAMS.spo2Target });
  const applyMock = (p: Partial<typeof mock>) => {
    const next = { ...mock, ...p };
    setMock(next);
    setMockParams(next);
  };

  const setRate = (stream: StreamKind, hz: number) =>
    update({ streamRates: { ...settings.streamRates, [stream]: hz } });

  return (
    <>
      <div className="card">
        <h2>Metrics &amp; DSP</h2>
        <label className="field" style={{ maxWidth: 320 }}>
          Metrics source
          <select value={settings.metricsSource} onChange={(e) => update({ metricsSource: e.target.value as MetricsSource })}>
            <option value="app">App-computed (iterate algorithms here)</option>
            <option value="firmware">Firmware-computed (on-device)</option>
          </select>
        </label>
        <label className="field" style={{ maxWidth: 320, marginTop: 12 }}>
          Calibration model
          <select value={settings.calibModel} onChange={(e) => update({ calibModel: e.target.value as CalibModel })}>
            <option value="linear_invPAT">Linear in 1/PAT (default)</option>
            <option value="linear_PAT">Linear in PAT</option>
          </select>
        </label>
      </div>

      <div className="card">
        <h2>Stream sample rates</h2>
        <div className="row">
          {(['ecg', 'bioz', 'ppg'] as StreamKind[]).map((stream) => (
            <label className="field" key={stream}>
              {stream.toUpperCase()} (Hz)
              <select value={settings.streamRates[stream]} onChange={(e) => setRate(stream, Number(e.target.value))}>
                {RATE_CODES[stream].map((hz) => <option key={hz} value={hz}>{hz}</option>)}
              </select>
            </label>
          ))}
        </div>
        <p className="muted small">Changes are sent to a connected device via SET_RATE.</p>
      </div>

      <div className="card">
        <h2>Gating thresholds</h2>
        <label className="field">Motion threshold: {settings.motionThresh.toExponential(1)}
          <input type="range" min={1e6} max={2e7} step={1e5} value={settings.motionThresh} onChange={(e) => update({ motionThresh: Number(e.target.value) })} />
        </label>
        <label className="field">Contact threshold (mΩ): {settings.contactThresh.toExponential(1)}
          <input type="range" min={1e6} max={2e7} step={1e5} value={settings.contactThresh} onChange={(e) => update({ contactThresh: Number(e.target.value) })} />
        </label>
        <label className="field">Gating window (ms): {settings.gatingWindowMs}
          <input type="range" min={200} max={1000} step={50} value={settings.gatingWindowMs} onChange={(e) => update({ gatingWindowMs: Number(e.target.value) })} />
        </label>
      </div>

      <div className="card">
        <h2>Mock generator</h2>
        <p className="muted small">{isMock ? 'Connected to the mock device — changes apply live.' : 'Connect the mock device to apply these.'}</p>
        <label className="field">Heart rate: {mock.hrBpm} bpm
          <input type="range" min={40} max={160} step={1} value={mock.hrBpm} onChange={(e) => applyMock({ hrBpm: Number(e.target.value) })} />
        </label>
        <label className="field">PAT: {mock.patMs} ms
          <input type="range" min={120} max={350} step={5} value={mock.patMs} onChange={(e) => applyMock({ patMs: Number(e.target.value) })} />
        </label>
        <label className="field">SpO₂ target: {mock.spo2Target}%
          <input type="range" min={90} max={100} step={1} value={mock.spo2Target} onChange={(e) => applyMock({ spo2Target: Number(e.target.value) })} />
        </label>
      </div>

      <div className="card">
        <h2>Appearance</h2>
        <label className="field" style={{ maxWidth: 240 }}>
          Theme
          <select value={settings.theme} onChange={(e) => update({ theme: e.target.value as 'dark' | 'light' | 'system' })}>
            <option value="system">System</option>
            <option value="dark">Dark</option>
            <option value="light">Light</option>
          </select>
        </label>
      </div>

      <div className="card">
        <h2>Data management</h2>
        <p className="muted small">Data is stored locally in this browser (IndexedDB). Deletion is permanent.</p>
        <div className="row">
          <button className="btn danger" onClick={async () => {
            if (!confirm('Delete ALL recorded sessions (subjects kept)?')) return;
            await Promise.all([db.chunks.clear(), db.metrics.clear(), db.annotations.clear(), db.sessions.clear()]);
            alert('All sessions deleted.');
          }}>Delete all sessions</button>
          <button className="btn danger" onClick={async () => {
            if (!confirm('Delete ALL data including subjects and calibrations?')) return;
            await Promise.all([db.chunks.clear(), db.metrics.clear(), db.annotations.clear(), db.sessions.clear(), db.subjects.clear(), db.calibrations.clear()]);
            await refreshSubjects();
            alert('All data deleted.');
          }}>Delete everything</button>
        </div>
      </div>
    </>
  );
}
