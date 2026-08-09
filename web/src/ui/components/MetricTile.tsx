import type { CSSProperties } from 'react';

interface Props {
  label: string;
  value: string | number | null;
  unit?: string;
  sub?: string;
  status?: 'good' | 'warn' | 'bad';
  /** Emoji/glyph shown in the tinted icon badge (matches iOS metric icons). */
  icon?: string;
  /** CSS color for the icon badge tint, e.g. 'var(--accent)'. */
  tint?: string;
  /** During warmup, show a shimmer placeholder instead of the "—" empty glyph. */
  loading?: boolean;
}

export function TileBadge({ icon, tint }: { icon: string; tint?: string }) {
  return (
    <span
      className="tile-badge"
      aria-hidden="true"
      style={tint ? ({ '--tint': tint } as CSSProperties) : undefined}
    >
      {icon}
    </span>
  );
}

export function MetricTile({ label, value, unit, sub, status, icon, tint, loading }: Props) {
  const empty = value == null || value === '';
  return (
    <div className={`tile ${status ?? ''}`}>
      <div className="tile-head">
        {icon ? <TileBadge icon={icon} tint={tint} /> : null}
        <div className="label">{label}</div>
      </div>
      <div className="value">
        {loading && empty ? (
          <span className="skeleton skeleton-value" aria-hidden="true" />
        ) : empty ? (
          <span className="muted">—</span>
        ) : (
          value
        )}
        {!empty && unit ? <span className="unit">{unit}</span> : null}
      </div>
      {sub ? <div className="sub">{sub}</div> : null}
    </div>
  );
}

export function Gauge({ value, max = 100, color }: { value: number; max?: number; color: string }) {
  const pct = Math.max(0, Math.min(100, (value / max) * 100));
  return (
    <div className="gauge" role="meter" aria-valuenow={Math.round(value)} aria-valuemax={max}>
      <div style={{ width: `${pct}%`, background: color }} />
    </div>
  );
}
