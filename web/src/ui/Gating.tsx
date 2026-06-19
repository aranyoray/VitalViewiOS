import { useEffect, useRef, useState } from 'react';
import { useAppStore } from '../store/appStore';
import { buffers } from '../live/runtime';
import { gateEcg } from '../dsp/bioz';

const WINDOW_SEC = 8;

export function GatingScreen() {
  const settings = useAppStore((s) => s.settings);
  const update = useAppStore((s) => s.updateSettings);
  const isMock = useAppStore((s) => s.isMock);
  const injectMotion = useAppStore((s) => s.injectMockMotion);
  const [goodPct, setGoodPct] = useState<number | null>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const { motionThresh, contactThresh, gatingWindowMs } = settings;

  useEffect(() => {
    const id = setInterval(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      const now = buffers.ecg.latestT();
      const dpr = window.devicePixelRatio || 1;
      const W = canvas.clientWidth || 600;
      const H = 300;
      canvas.width = W * dpr;
      canvas.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, W, H);
      ctx.fillStyle = 'rgba(255,255,255,0.5)';
      ctx.font = '12px sans-serif';
      ctx.fillText('Raw ECG', 8, 16);
      ctx.fillText('BioZ-gated ECG', 8, H / 2 + 16);

      if (now == null) {
        setGoodPct(null);
        return;
      }
      const tFrom = now - WINDOW_SEC * 1e6;
      const ecg = buffers.ecg.window(tFrom);
      const dz = buffers.biozDz.window(tFrom);
      const z0 = buffers.z0.window(tFrom);
      if (ecg.t.length < 4) return;

      const res = gateEcg(
        { t: ecg.t, v: ecg.v },
        { t: dz.t, v: dz.v },
        { t: z0.t, v: z0.v },
        { windowMs: gatingWindowMs, motionThresh, contactThresh },
      );
      setGoodPct(res.goodPct);

      let lo = Infinity, hi = -Infinity;
      for (const v of ecg.v) { if (v < lo) lo = v; if (v > hi) hi = v; }
      if (lo === hi) { lo -= 1; hi += 1; }
      const xOf = (t: number) => ((t - tFrom) / (WINDOW_SEC * 1e6)) * W;

      // Shade windows by good/bad across full height.
      for (const w of res.windows) {
        const x0 = xOf(w.tStartUs);
        const x1 = xOf(w.tEndUs);
        ctx.fillStyle = w.good ? 'rgba(56,211,159,0.07)' : 'rgba(255,107,107,0.16)';
        ctx.fillRect(x0, 0, x1 - x0, H);
      }
      ctx.strokeStyle = 'rgba(255,255,255,0.10)';
      ctx.beginPath(); ctx.moveTo(0, H / 2); ctx.lineTo(W, H / 2); ctx.stroke();

      const drawTrace = (vals: (number | null)[], yTop: number, yH: number, color: string) => {
        const yOf = (v: number) => yTop + yH - ((v - lo) / (hi - lo)) * yH;
        ctx.strokeStyle = color; ctx.lineWidth = 1.4; ctx.beginPath();
        let pen = false;
        for (let i = 0; i < ecg.t.length; i++) {
          const v = vals[i];
          if (v == null) { pen = false; continue; }
          const x = xOf(ecg.t[i]); const y = yOf(v);
          if (!pen) { ctx.moveTo(x, y); pen = true; } else ctx.lineTo(x, y);
        }
        ctx.stroke();
      };
      drawTrace(ecg.v as number[], 24, H / 2 - 32, 'var(--ecg)');
      drawTrace(res.gatedEcg, H / 2 + 24, H / 2 - 40, 'var(--good)');
    }, 200);
    return () => clearInterval(id);
  }, [motionThresh, contactThresh, gatingWindowMs]);

  return (
    <>
      <div className="card">
        <h2>Signal-quality gating</h2>
        <p className="muted small">
          The core thesis: use the co-sampled BioZ channel to reject ECG during motion or poor
          contact. A window is rejected when ΔZ variance exceeds the motion threshold or Z₀ drifts
          beyond the contact threshold. The bottom trace blanks rejected windows.
        </p>
        <div className="row" style={{ marginTop: 8 }}>
          <div className="tile" style={{ minWidth: 160 }}>
            <div className="label">Good segments</div>
            <div className="value">{goodPct == null ? '—' : `${goodPct.toFixed(0)}%`}</div>
          </div>
          {isMock && <button className="btn secondary" onClick={injectMotion}>Inject motion burst</button>}
        </div>
        <div className="legend" style={{ marginTop: 8 }}>
          <span><span className="dot" style={{ background: 'rgba(56,211,159,0.5)' }} />good window</span>
          <span><span className="dot" style={{ background: 'rgba(255,107,107,0.6)' }} />rejected window</span>
        </div>
      </div>

      <div className="card">
        <canvas ref={canvasRef} className="wave" style={{ height: 300 }} />
      </div>

      <div className="card">
        <h3>Thresholds (adjustable)</h3>
        <label className="field">
          Motion threshold (ΔZ variance): {motionThresh.toExponential(1)}
          <input type="range" min={1e6} max={2e7} step={1e5} value={motionThresh} onChange={(e) => update({ motionThresh: Number(e.target.value) })} />
        </label>
        <label className="field">
          Contact threshold (|Z₀ − baseline| mΩ): {contactThresh.toExponential(1)}
          <input type="range" min={1e6} max={2e7} step={1e5} value={contactThresh} onChange={(e) => update({ contactThresh: Number(e.target.value) })} />
        </label>
        <label className="field">
          Window (ms): {gatingWindowMs}
          <input type="range" min={200} max={1000} step={50} value={gatingWindowMs} onChange={(e) => update({ gatingWindowMs: Number(e.target.value) })} />
        </label>
      </div>
    </>
  );
}
