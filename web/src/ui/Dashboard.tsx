import { useState } from 'react';
import { useAppStore } from '../store/appStore';
import { buffers, engine } from '../live/runtime';
import { WaveformCanvas } from './components/WaveformCanvas';
import { Gauge, MetricTile, TileBadge } from './components/MetricTile';

export function DashboardScreen() {
  const live = useAppStore((s) => s.liveMetrics);
  const streaming = useAppStore((s) => s.streaming);
  const modelName = useAppStore((s) => s.modelName);
  const metricsSource = useAppStore((s) => s.settings.metricsSource);
  const calibrated = useAppStore((s) => s.currentCalibration != null);
  const recordingName = useAppStore((s) => s.recordingName);
  const referenceHR = useAppStore((s) => s.referenceHR);
  const referenceSpO2 = useAppStore((s) => s.referenceSpO2);
  const loadError = useAppStore((s) => s.loadError);
  const retry = useAppStore((s) => s.retryAutoStart);
  const [ppgCh, setPpgCh] = useState<'green' | 'red' | 'ir'>('green');

  const contact = live?.contactQuality ?? 0;
  const motion = live?.motion ?? 0;
  const ppgBuffer = ppgCh === 'green' ? buffers.ppgGreen : ppgCh === 'red' ? buffers.ppgRed : buffers.ppgIr;
  const ppgColor = ppgCh === 'red' ? '#e5484d' : ppgCh === 'ir' ? '#6d3fb8' : 'var(--ppg)';

  // Warmup = streaming but the DSP hasn't locked onto the pulse yet (first ~2s while
  // ring buffers fill and enough beats accumulate). Keyed off HR availability rather
  // than the snapshot object, which is non-null after the very first 250 ms tick.
  const warming = streaming && live?.hrBpm == null;

  // Graceful error: the bundled recording failed to load.
  if (loadError) {
    return (
      <div className="card empty-state">
        <div className="empty-badge bad" aria-hidden="true">⚠️</div>
        <h2 style={{ margin: '0 0 4px' }}>Couldn’t load the recording</h2>
        <p className="muted small" style={{ maxWidth: 420 }}>
          The bundled biosignal recording didn’t load, so there’s nothing to stream.
          Check your connection and try again — everything runs locally once it loads.
        </p>
        <p className="muted small" style={{ fontFamily: 'monospace', fontSize: 12, opacity: 0.7 }}>{loadError}</p>
        <button className="btn" onClick={() => void retry()} style={{ marginTop: 4 }}>Try again</button>
      </div>
    );
  }

  return (
    <>
      {warming && (
        <div className="card warmup-card" aria-live="polite">
          <span className="spinner" aria-hidden="true" />
          <div>
            <div style={{ fontWeight: 600 }}>Warming up…</div>
            <div className="small muted">Filling the signal buffers and locking onto the pulse.</div>
          </div>
        </div>
      )}

      {recordingName && (
        <div className="card">
          <div className="row between">
            <h3>Real recording</h3>
            <span className="badge good">Real data</span>
          </div>
          <p className="small" style={{ margin: '2px 0 4px' }}>{recordingName}</p>
          <p className="small muted" style={{ margin: 0 }}>
            Recorded reference: {referenceHR != null ? Math.round(referenceHR) : '—'} bpm ·{' '}
            {referenceSpO2 != null ? Math.round(referenceSpO2) : '—'}% SpO₂
          </p>
        </div>
      )}

      <div className="card">
        <div className="row between">
          <h2>Live metrics</h2>
          <span className="badge">{metricsSource === 'app' ? 'on-device' : 'recording'}</span>
        </div>
        <p className="small muted" style={{ marginTop: 2 }}>Model: {modelName}</p>
        <div className="tiles">
          <MetricTile label="Heart rate" value={live?.hrBpm != null ? Math.round(live.hrBpm) : null} unit="bpm" icon="❤️" tint="var(--accent)" loading={warming} />
          <MetricTile label="SpO₂" value={live?.spo2Pct != null ? Math.round(live.spo2Pct) : null} unit="%" sub="Estimate" icon="🩸" tint="var(--navy)" loading={warming} />
          <MetricTile label="PAT" value={live?.patUs != null ? Math.round(live.patUs / 1000) : null} unit="ms" sub="R–pulse interval" icon="⏱️" tint="var(--navy)" loading={warming} />
          <MetricTile
            label="Blood pressure"
            value={live?.sbpMmHg != null && live?.dbpMmHg != null ? `${live.sbpMmHg}/${live.dbpMmHg}` : null}
            unit="mmHg"
            sub={calibrated ? 'estimate' : 'uncalibrated — calibrate first'}
            icon="🩺"
            tint="var(--warn)"
            loading={warming}
          />
          <div className="tile">
            <div className="tile-head">
              <TileBadge icon="👆" tint="var(--bioz)" />
              <div className="label">Contact quality</div>
            </div>
            <div className="value">{contact}<span className="unit">/100</span></div>
            <div style={{ marginTop: 8 }}>
              <Gauge value={contact} color={contact > 70 ? 'var(--good)' : contact > 40 ? 'var(--warn)' : 'var(--bad)'} />
            </div>
          </div>
          <div className="tile">
            <div className="tile-head">
              <TileBadge icon="🚶" tint="var(--pink)" />
              <div className="label">Motion</div>
            </div>
            <div className="value">{motion}<span className="unit">/255</span></div>
            <div className="sub">{motion < 40 ? 'still' : motion < 120 ? 'some motion' : 'high motion'}</div>
            <div style={{ marginTop: 6 }}>
              <Gauge value={motion} max={255} color={motion < 40 ? 'var(--good)' : motion < 120 ? 'var(--warn)' : 'var(--bad)'} />
            </div>
          </div>
        </div>
      </div>

      <div className="card">
        <h3>ECG — single-arm lead ≈ Lead I</h3>
        <WaveformCanvas
          buffer={buffers.ecg}
          windowSec={5}
          color="var(--ecg)"
          label="ECG (R-peaks marked)"
          getMarkers={() => engine.recentRPeaks}
          markerColor="rgba(214,35,109,0.30)"
        />
      </div>

      <div className="card">
        <div className="row between">
          <h3>PPG</h3>
          <div className="row" role="group" aria-label="PPG channel">
            {(['green', 'red', 'ir'] as const).map((c) => (
              <button
                key={c}
                className={`btn ${ppgCh === c ? '' : 'secondary'}`}
                aria-pressed={ppgCh === c}
                aria-label={`Show ${c.toUpperCase()} PPG channel`}
                onClick={() => setPpgCh(c)}
              >
                {c.toUpperCase()}
              </button>
            ))}
          </div>
        </div>
        <WaveformCanvas buffer={ppgBuffer} windowSec={5} color={ppgColor} label={`PPG (${ppgCh})`} />
      </div>

      <div className="card">
        <h3>BioZ — pulsatile ΔZ &amp; baseline Z₀ (contact)</h3>
        <WaveformCanvas buffer={buffers.biozDz} windowSec={8} color="var(--bioz)" label="ΔZ" height={110} />
        <div className="row" style={{ marginTop: 10, alignItems: 'center' }}>
          <span className="small muted" style={{ minWidth: 130 }}>Contact (from Z₀)</span>
          <span className="grow"><Gauge value={contact} color={contact > 70 ? 'var(--good)' : contact > 40 ? 'var(--warn)' : 'var(--bad)'} /></span>
          <span className="small">{contact}/100</span>
        </div>
      </div>
    </>
  );
}
