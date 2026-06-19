interface Props {
  label: string;
  value: string | number | null;
  unit?: string;
  sub?: string;
  status?: 'good' | 'warn' | 'bad';
}

export function MetricTile({ label, value, unit, sub, status }: Props) {
  return (
    <div className={`tile ${status ?? ''}`}>
      <div className="label">{label}</div>
      <div className="value">
        {value == null || value === '' ? <span className="muted">—</span> : value}
        {value != null && value !== '' && unit ? <span className="unit">{unit}</span> : null}
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
