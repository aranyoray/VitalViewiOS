import { useEffect, useRef } from 'react';
import type { WaveBuffer } from '../../live/ringBuffer';
import { resolveCssColor } from '../../util/cssColor';

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
  markerColor = 'rgba(38,26,100,0.25)',
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // Latest props for the rAF loop to read without re-subscribing every render
  // (the loop runs continuously; re-creating it per render would tear down/rebuild
  // the animation frame ~4×/s and reset it to a stale closure over the props).
  const propsRef = useRef({ windowSec, color, height, yRange, getMarkers, markerColor });
  propsRef.current = { windowSec, color, height, yRange, getMarkers, markerColor };

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    let raf = 0;

    const draw = () => {
      const { windowSec, color, height, yRange, getMarkers, markerColor } = propsRef.current;
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

      // Faint vertical time grid (one line per second) for readability.
      const secW = cssW / windowSec;
      if (secW > 12) {
        ctx.strokeStyle = 'rgba(38,26,100,0.05)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (let gx = cssW - secW; gx > 0; gx -= secW) {
          ctx.moveTo(Math.round(gx) + 0.5, 0);
          ctx.lineTo(Math.round(gx) + 0.5, cssH);
        }
        ctx.stroke();
      }

      // Midline.
      ctx.strokeStyle = 'rgba(38,26,100,0.10)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, Math.round(cssH / 2) + 0.5);
      ctx.lineTo(cssW, Math.round(cssH / 2) + 0.5);
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
          ctx.strokeStyle = resolveCssColor(markerColor);
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

        ctx.strokeStyle = resolveCssColor(color);
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
  }, [buffer]);

  return (
    <div className="wave-wrap">
      <span className="wave-label">{label}</span>
      <canvas
        ref={canvasRef}
        className="wave"
        style={{ height }}
        role="img"
        aria-label={`${label} — live scrolling waveform, ${windowSec}-second window`}
      />
    </div>
  );
}
