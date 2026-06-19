import { useState } from 'react';
import { useAppStore } from '../store/appStore';
import { buffers, engine } from '../live/runtime';
import { WaveformCanvas } from './components/WaveformCanvas';
import { Gauge, MetricTile } from './components/MetricTile';

export function DashboardScreen() {
  const live = useAppStore((s) => s.liveMetrics);
  const streaming = useAppStore((s) => s.streaming);
  const metricsSource = useAppStore((s) => s.settings.metricsSource);
  const calibrated = useAppStore((s) => s.currentCalibration != null);
  const [ppgCh, setPpgCh] = useState<'green' | 'red' | 'ir'>('green');

  const contact = live?.contactQuality ?? 0;
  const motion = live?.motion ?? 0;
  const ppgBuffer = ppgCh === 'green' ? buffers.ppgGreen : ppgCh === 'red' ? buffers.ppgRed : buffers.ppgIr;
  const ppgColor = ppgCh === 'red' ? '#ff7b7b' : ppgCh === 'ir' ? '#b388ff' : 'var(--ppg)';

  return (
    <>
      {!streaming && (
        <div className="card">
          <p className="muted">Not streaming. Connect a device (or mock) and press “Start streaming”.</p>
        </div>
      )}

      <div className="card">
        <div className="row between">
          <h2>Live metrics</h2>
          <span className="badge">{metricsSource === 'app' ? 'app-computed' : 'firmware'}</span>
        </div>
        <div className="tiles">
          <MetricTile label="Heart rate" value={live?.hrBpm != null ? Math.round(live.hrBpm) : null} unit="bpm" />
          <MetricTile label="SpO₂ (estimate)" value={live?.spo2Pct != null ? Math.round(live.spo2Pct) : null} unit="%" sub="uncalibrated estimate" />
          <MetricTile label="PAT" value={live?.patUs != null ? Math.round(live.patUs / 1000) : null} unit="ms" />
          <MetricTile
            label="Blood pressure"
            value={live?.sbpMmHg != null && live?.dbpMmHg != null ? `${live.sbpMmHg}/${live.dbpMmHg}` : null}
            unit="mmHg"
            sub={calibrated ? 'estimate' : 'uncalibrated — calibrate first'}
          />
          <div className="tile">
            <div className="label">Contact quality</div>
            <div className="value">{contact}<span className="unit">/100</span></div>
            <div style={{ marginTop: 8 }}>
              <Gauge value={contact} color={contact > 70 ? 'var(--good)' : contact > 40 ? 'var(--warn)' : 'var(--bad)'} />
            </div>
          </div>
          <div className="tile">
            <div className="label">Motion</div>
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
          markerColor="rgba(110,231,255,0.30)"
        />
      </div>

      <div className="card">
        <div className="row between">
          <h3>PPG</h3>
          <div className="row">
            {(['green', 'red', 'ir'] as const).map((c) => (
              <button key={c} className={`btn ${ppgCh === c ? '' : 'secondary'}`} onClick={() => setPpgCh(c)}>
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
