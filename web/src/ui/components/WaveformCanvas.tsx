import { useEffect, useRef } from 'react';
import type { WaveBuffer } from '../../live/ringBuffer';

interface Props {
  buffer: WaveBuffer;
  windowSec: number;
  color: string;
  label: string;
  height?: number;
  /** Fixed y-range; if omitted the trace auto-scales to the visible window. */
  yRange?: [number, number];
  /** Optional event timestamps (device µs) drawn as vertical markers (e.g. R-peaks). */
  getMarkers?: () => number[];
  markerColor?: string;
}

/**
 * Scrolling waveform strip. Reads the ring buffer directly on requestAnimationFrame and
 * draws a downsampled polyline; it never triggers React re-renders per sample (§2.4).
 */
export function WaveformCanvas({
  buffer,
  windowSec,
  color,
  label,
  height = 140,
  yRange,
  getMarkers,
  markerColor = 'rgba(255,255,255,0.35)',
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    let raf = 0;

    const draw = () => {
      const dpr = window.devicePixelRatio || 1;
      const cssW = canvas.clientWidth || 600;
      const cssH = height;
      if (canvas.width !== Math.round(cssW * dpr) || canvas.height !== Math.round(cssH * dpr)) {
        canvas.width = Math.round(cssW * dpr);
        canvas.height = Math.round(cssH * dpr);
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, cssW, cssH);

      const now = buffer.latestT();
      const windowUs = windowSec * 1_000_000;
      // Midline.
      ctx.strokeStyle = 'rgba(255,255,255,0.08)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, cssH / 2);
      ctx.lineTo(cssW, cssH / 2);
      ctx.stroke();

      if (now == null) {
        raf = requestAnimationFrame(draw);
        return;
      }
      const tFrom = now - windowUs;
      const { t, v } = buffer.window(tFrom);
      if (t.length >= 2) {
        let lo = yRange ? yRange[0] : Infinity;
        let hi = yRange ? yRange[1] : -Infinity;
        if (!yRange) {
          for (const val of v) {
            if (val < lo) lo = val;
            if (val > hi) hi = val;
          }
          if (lo === hi) {
            lo -= 1;
            hi += 1;
          }
          const pad = (hi - lo) * 0.1;
          lo -= pad;
          hi += pad;
        }
        const xOf = (ts: number) => ((ts - tFrom) / windowUs) * cssW;
        const yOf = (val: number) => cssH - ((val - lo) / (hi - lo)) * cssH;

        // Markers behind the trace.
        if (getMarkers) {
          ctx.strokeStyle = markerColor;
          ctx.lineWidth = 1;
          for (const m of getMarkers()) {
            if (m < tFrom || m > now) continue;
            const x = xOf(m);
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, cssH);
            ctx.stroke();
          }
        }

        ctx.strokeStyle = color;
        ctx.lineWidth = 1.5;
        ctx.lineJoin = 'round';
        ctx.beginPath();
        ctx.moveTo(xOf(t[0]), yOf(v[0]));
        for (let i = 1; i < t.length; i++) ctx.lineTo(xOf(t[i]), yOf(v[i]));
        ctx.stroke();
      }
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, [buffer, windowSec, color, height, yRange, getMarkers, markerColor]);

  return (
    <div className="wave-wrap">
      <span className="wave-label">{label}</span>
      <canvas ref={canvasRef} className="wave" style={{ height }} />
    </div>
  );
}
