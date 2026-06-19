import { useEffect, useRef, useState } from 'react';
import { useAppStore } from '../store/appStore';
import {
  deleteSession,
  listAnnotations,
  listMetrics,
  listSessions,
  readSessionStreams,
  type SessionStreams,
} from '../model/repository';
import type { Annotation, MetricsRecord, Session } from '../model/types';
import { median } from '../dsp/rollingStats';

export function ReviewScreen() {
  const exportZip = useAppStore((s) => s.exportSessionZip);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [selected, setSelected] = useState<Session | null>(null);
  const [streams, setStreams] = useState<SessionStreams | null>(null);
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [metrics, setMetrics] = useState<MetricsRecord[]>([]);

  const refresh = () => void listSessions().then(setSessions);
  useEffect(refresh, []);

  const open = async (s: Session) => {
    setSelected(s);
    const [st, an, me] = await Promise.all([readSessionStreams(s.id), listAnnotations(s.id), listMetrics(s.id)]);
    setStreams(st);
    setAnnotations(an);
    setMetrics(me);
  };

  const remove = async (s: Session) => {
    if (!confirm(`Delete session ${s.label} (${s.id.slice(0, 8)})? This cannot be undone.`)) return;
    await deleteSession(s.id);
    if (selected?.id === s.id) { setSelected(null); setStreams(null); }
    refresh();
  };

  const hrValues = metrics.map((m) => m.hrBpm).filter((v): v is number => v != null);
  const patValues = metrics.map((m) => m.patUs).filter((v): v is number => v != null);

  return (
    <>
      <div className="card">
        <h2>Sessions</h2>
        {sessions.length === 0 ? (
          <p className="muted small">No recordings yet. Record a session on the Record tab (mock mode works).</p>
        ) : (
          <table>
            <thead><tr><th>Started</th><th>Subject</th><th>Condition</th><th>Duration</th><th /></tr></thead>
            <tbody>
              {sessions.map((s) => (
                <tr key={s.id}>
                  <td className="small">{new Date(s.startedAt).toLocaleString()}</td>
                  <td>{s.subjectCode}</td>
                  <td>{s.label}</td>
                  <td>{durationOf(s)}</td>
                  <td>
                    <div className="row">
                      <button className="btn secondary" onClick={() => void open(s)}>View</button>
                      <button className="btn secondary" onClick={() => void exportZip(s.id)}>Export CSV</button>
                      <button className="btn danger" onClick={() => void remove(s)}>Delete</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {selected && streams && (
        <div className="card">
          <div className="row between">
            <h3>{selected.label} · {selected.subjectCode} · {selected.id.slice(0, 8)}</h3>
            <button className="btn" onClick={() => void exportZip(selected.id)}>Export CSV bundle</button>
          </div>
          <div className="tiles" style={{ marginBottom: 12 }}>
            <div className="tile"><div className="label">ECG samples</div><div className="value">{streams.ecg.t.length.toLocaleString()}</div></div>
            <div className="tile"><div className="label">PPG samples</div><div className="value">{streams.ppg.t.length.toLocaleString()}</div></div>
            <div className="tile"><div className="label">BioZ samples</div><div className="value">{streams.bioz.t.length.toLocaleString()}</div></div>
            <div className="tile"><div className="label">Median HR</div><div className="value">{hrValues.length ? Math.round(median(hrValues)) : '—'}<span className="unit">bpm</span></div></div>
            <div className="tile"><div className="label">Median PAT</div><div className="value">{patValues.length ? Math.round(median(patValues) / 1000) : '—'}<span className="unit">ms</span></div></div>
            <div className="tile"><div className="label">Annotations</div><div className="value">{annotations.length}</div></div>
          </div>

          <h3>ECG (full session)</h3>
          <StaticPlot t={streams.ecg.t} v={streams.ecg.ecg} color="var(--ecg)" />
          <h3 style={{ marginTop: 12 }}>PPG green (full session)</h3>
          <StaticPlot t={streams.ppg.t} v={streams.ppg.green} color="var(--ppg)" />

          {annotations.length > 0 && (
            <>
              <h3 style={{ marginTop: 12 }}>Annotations</h3>
              <table>
                <thead><tr><th>t (s)</th><th>Type</th><th>SBP/DBP</th><th>Text</th></tr></thead>
                <tbody>
                  {annotations.map((a) => (
                    <tr key={a.id}>
                      <td>{relSeconds(a.tUs, streams)}</td>
                      <td>{a.type}</td>
                      <td>{a.sbp != null ? `${a.sbp}/${a.dbp}` : '—'}</td>
                      <td>{a.text ?? ''}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          )}
        </div>
      )}
    </>
  );
}

function durationOf(s: Session): string {
  if (!s.endedAt) return '—';
  const ms = new Date(s.endedAt).getTime() - new Date(s.startedAt).getTime();
  const sec = Math.round(ms / 1000);
  return `${Math.floor(sec / 60)}m ${sec % 60}s`;
}

function relSeconds(tUs: number, streams: SessionStreams): string {
  const t0 = streams.ecg.t[0] ?? streams.ppg.t[0] ?? 0;
  return ((tUs - t0) / 1e6).toFixed(1);
}

/** Static downsampled plot of an entire recorded stream. */
function StaticPlot({ t, v, color }: { t: Float64Array; v: Int32Array | Uint32Array; color: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const dpr = window.devicePixelRatio || 1;
    const W = canvas.clientWidth || 600;
    const H = 130;
    canvas.width = W * dpr;
    canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (t.length < 2) { ctx.fillStyle = 'var(--muted)'; ctx.fillText('no data', 8, H / 2); return; }
    const target = Math.min(W * 2, t.length);
    const stride = Math.max(1, Math.floor(t.length / target));
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < v.length; i += stride) { const x = v[i]; if (x < lo) lo = x; if (x > hi) hi = x; }
    if (lo === hi) { lo -= 1; hi += 1; }
    const t0 = t[0], t1 = t[t.length - 1];
    const xOf = (ts: number) => ((ts - t0) / (t1 - t0 || 1)) * W;
    const yOf = (val: number) => H - ((val - lo) / (hi - lo)) * (H - 6) - 3;
    ctx.strokeStyle = color; ctx.lineWidth = 1; ctx.beginPath();
    let first = true;
    for (let i = 0; i < t.length; i += stride) {
      const x = xOf(t[i]), y = yOf(v[i]);
      if (first) { ctx.moveTo(x, y); first = false; } else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }, [t, v, color]);
  return <canvas ref={ref} className="wave" style={{ height: 130 }} />;
}
