import { useEffect, useRef, useState } from 'react';
import { useAppStore } from '../store/appStore';
import { fitCalibration, predictor, type RefPair } from '../dsp/calibration';

export function CalibrationScreen() {
  const subject = useAppStore((s) => s.currentSubjectCode);
  const pairs = useAppStore((s) => s.calibrationPairs);
  const live = useAppStore((s) => s.liveMetrics);
  const model = useAppStore((s) => s.settings.calibModel);
  const saved = useAppStore((s) => s.currentCalibration);
  const addPair = useAppStore((s) => s.addCalibrationPair);
  const removePair = useAppStore((s) => s.removeCalibrationPair);
  const clearPairs = useAppStore((s) => s.clearCalibrationPairs);
  const saveFit = useAppStore((s) => s.saveCalibrationFit);

  const [sbp, setSbp] = useState('120');
  const [dbp, setDbp] = useState('80');
  const [msg, setMsg] = useState<string | null>(null);

  const livePatMs = live?.patUs != null ? Math.round(live.patUs / 1000) : null;
  const fit = fitCalibration(pairs, model);

  const s = Number(sbp);
  const d = Number(dbp);
  const bpValid = Number.isFinite(s) && Number.isFinite(d) && s > 40 && s < 260 && d > 20 && d < 200 && d < s;

  const onAdd = () => {
    if (!bpValid) {
      setMsg('Enter a plausible cuff reading (SBP 40–260, DBP 20–200, DBP < SBP).');
      return;
    }
    const ok = addPair(s, d);
    setMsg(ok ? null : 'No PAT available yet — start streaming and wait for a stable PAT.');
  };

  return (
    <>
      {!subject && <div className="card"><p className="muted">Select a subject on the Record tab to calibrate.</p></div>}

      <div className="card">
        <div className="row between">
          <h2>PAT → BP calibration {subject ? `· ${subject}` : ''}</h2>
          <span className="badge">{model}</span>
        </div>
        <p className="muted small">
          Collect simultaneous (PAT, cuff SBP/DBP) pairs across a range of pressures, then fit a
          per-subject model: <code>BP = a + b·(1/PAT)</code>. Estimated BP stays “uncalibrated” until
          a model with ≥ 3 pairs is saved. This is an educational fit, not a clinical model.
        </p>
        <div className="row" style={{ marginTop: 8 }}>
          <div className="tile" style={{ minWidth: 120 }}>
            <div className="label">Live PAT</div>
            <div className="value">{livePatMs ?? '—'}<span className="unit">ms</span></div>
          </div>
          <label className="field">Cuff SBP<input inputMode="numeric" value={sbp} onChange={(e) => setSbp(e.target.value)} /></label>
          <label className="field">Cuff DBP<input inputMode="numeric" value={dbp} onChange={(e) => setDbp(e.target.value)} /></label>
          <button className="btn" disabled={!subject || livePatMs == null || !bpValid} onClick={onAdd}>Capture pair</button>
        </div>
        {msg && <p className="small" style={{ color: 'var(--warn-text)' }}>{msg}</p>}
      </div>

      <div className="card">
        <div className="row between">
          <h3>Reference pairs ({pairs.length})</h3>
          {pairs.length > 0 && <button className="btn secondary" onClick={clearPairs}>Clear</button>}
        </div>
        {pairs.length === 0 ? (
          <p className="muted small">No pairs yet.</p>
        ) : (
          <table>
            <thead><tr><th>#</th><th>PAT (ms)</th><th>1/PAT (s⁻¹)</th><th>SBP</th><th>DBP</th><th /></tr></thead>
            <tbody>
              {pairs.map((p, i) => (
                <tr key={i}>
                  <td>{i + 1}</td>
                  <td>{Math.round(p.patUs / 1000)}</td>
                  <td>{(1 / (p.patUs / 1e6)).toFixed(2)}</td>
                  <td>{p.sbp}</td>
                  <td>{p.dbp}</td>
                  <td><button className="btn secondary" aria-label={`Remove pair ${i + 1}`} onClick={() => removePair(i)}>✕</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card">
        <h3>Fit</h3>
        {fit ? (
          <>
            <div className="tiles">
              <div className="tile"><div className="label">Pearson R (SBP)</div><div className="value">{fit.r.toFixed(2)}</div></div>
              <div className="tile"><div className="label">RMSE SBP</div><div className="value">{fit.rmseSbp.toFixed(1)}<span className="unit">mmHg</span></div></div>
              <div className="tile"><div className="label">RMSE DBP</div><div className="value">{fit.rmseDbp.toFixed(1)}<span className="unit">mmHg</span></div></div>
              <div className="tile"><div className="label">Pairs</div><div className="value">{fit.n}</div></div>
            </div>
            <Scatter pairs={pairs} model={model} coeffs={fit.coeffs.sbp} />
            <div className="row" style={{ marginTop: 12 }}>
              <button className="btn" disabled={pairs.length < 3} onClick={() => void saveFit()}>
                Save calibration {pairs.length < 3 ? '(need ≥ 3 pairs)' : ''}
              </button>
            </div>
          </>
        ) : (
          <p className="muted small">Add at least 2 pairs with differing PAT to fit a line.</p>
        )}
      </div>

      {saved && (
        <div className="card">
          <h3>Active calibration</h3>
          <table>
            <tbody>
              <tr><th>Model</th><td>{saved.model}</td></tr>
              <tr><th>SBP</th><td>{saved.coeffs.sbp[0].toFixed(1)} + {saved.coeffs.sbp[1].toFixed(1)}·x</td></tr>
              <tr><th>DBP</th><td>{saved.coeffs.dbp[0].toFixed(1)} + {saved.coeffs.dbp[1].toFixed(1)}·x</td></tr>
              <tr><th>R / RMSE</th><td>R={saved.r.toFixed(2)} · SBP {saved.rmseSbp.toFixed(1)} / DBP {saved.rmseDbp.toFixed(1)} mmHg</td></tr>
              <tr><th>Saved</th><td>{new Date(saved.createdAt).toLocaleString()}</td></tr>
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

function Scatter({ pairs, model, coeffs }: { pairs: RefPair[]; model: 'linear_invPAT' | 'linear_PAT'; coeffs: [number, number] }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const dpr = window.devicePixelRatio || 1;
    const W = canvas.clientWidth || 600;
    const H = 220;
    canvas.width = W * dpr;
    canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const pad = 36;
    const xs = pairs.map((p) => predictor(p.patUs, model));
    const ys = pairs.map((p) => p.sbp);
    if (xs.length === 0) return;
    const xlo = Math.min(...xs), xhi = Math.max(...xs);
    const ylo = Math.min(...ys) - 5, yhi = Math.max(...ys) + 5;
    const sx = (x: number) => pad + ((x - xlo) / (xhi - xlo || 1)) * (W - pad - 10);
    const sy = (y: number) => H - pad - ((y - ylo) / (yhi - ylo || 1)) * (H - pad - 10);

    ctx.strokeStyle = 'rgba(38,26,100,0.20)';
    ctx.beginPath(); ctx.moveTo(pad, 10); ctx.lineTo(pad, H - pad); ctx.lineTo(W - 10, H - pad); ctx.stroke();
    ctx.fillStyle = 'rgba(38,26,100,0.65)'; ctx.font = '11px sans-serif';
    ctx.fillText(model === 'linear_invPAT' ? '1/PAT (s⁻¹)' : 'PAT (s)', W / 2 - 30, H - 8);
    ctx.save(); ctx.translate(12, H / 2); ctx.rotate(-Math.PI / 2); ctx.fillText('SBP (mmHg)', -30, 0); ctx.restore();

    // Fit line.
    ctx.strokeStyle = '#4da3ff'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(sx(xlo), sy(coeffs[0] + coeffs[1] * xlo)); ctx.lineTo(sx(xhi), sy(coeffs[0] + coeffs[1] * xhi)); ctx.stroke();

    // Points.
    ctx.fillStyle = '#38d39f';
    for (let i = 0; i < xs.length; i++) { ctx.beginPath(); ctx.arc(sx(xs[i]), sy(ys[i]), 4, 0, Math.PI * 2); ctx.fill(); }
  }, [pairs, model, coeffs]);
  return <canvas ref={ref} className="wave" style={{ height: 220, marginTop: 12 }} role="img" aria-label="Scatter of SBP versus the PAT predictor with the fitted regression line" />;
}
