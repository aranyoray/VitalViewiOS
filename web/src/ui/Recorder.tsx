import { useState } from 'react';
import { useAppStore } from '../store/appStore';
import type { SessionLabel, Subject } from '../model/types';

const LABELS: SessionLabel[] = ['rest', 'seated', 'walking', 'post-exercise', 'other'];
const AGE_BANDS = ['<18', '18-25', '26-35', '36-50', '51-65', '65+'];

function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

export function RecorderScreen() {
  const subjects = useAppStore((s) => s.subjects);
  const currentSubjectCode = useAppStore((s) => s.currentSubjectCode);
  const selectSubject = useAppStore((s) => s.selectSubject);
  const saveSubject = useAppStore((s) => s.saveSubject);
  const connected = useAppStore((s) => s.connectionState === 'connected');
  const recording = useAppStore((s) => s.recording);
  const counts = useAppStore((s) => s.recordCounts);
  const durationMs = useAppStore((s) => s.recordDurationMs);
  const dropped = useAppStore((s) => s.dropped);
  const cuffCount = useAppStore((s) => s.cuffReadingCount);
  const startRecording = useAppStore((s) => s.startRecording);
  const stopRecording = useAppStore((s) => s.stopRecording);
  const addMarker = useAppStore((s) => s.addMarker);
  const addCuffReading = useAppStore((s) => s.addCuffReading);

  const [label, setLabel] = useState<SessionLabel>('rest');
  const [notes, setNotes] = useState('');
  const [showNew, setShowNew] = useState(false);
  const [showCuff, setShowCuff] = useState(false);

  return (
    <>
      <div className="card">
        <h2>Subject</h2>
        <div className="row">
          <label className="field grow">
            Subject code
            <select value={currentSubjectCode ?? ''} onChange={(e) => void selectSubject(e.target.value || null)}>
              <option value="">— select —</option>
              {subjects.map((s) => (
                <option key={s.code} value={s.code}>{s.code} ({s.ageBand})</option>
              ))}
            </select>
          </label>
          <button className="btn secondary" onClick={() => setShowNew(true)}>New subject</button>
        </div>
        <p className="muted small" style={{ marginTop: 8 }}>Use a non-identifying code (e.g. S01). No names or contact info.</p>
      </div>

      <div className="card">
        <h2>Recording session</h2>
        <div className="row">
          <label className="field">
            Condition
            <select value={label} onChange={(e) => setLabel(e.target.value as SessionLabel)} disabled={!!recording}>
              {LABELS.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </label>
          <label className="field grow">
            Notes
            <input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="optional" disabled={!!recording} />
          </label>
        </div>
        <div className="row" style={{ marginTop: 12 }}>
          {!recording ? (
            <button
              className="btn"
              disabled={!connected || !currentSubjectCode}
              onClick={() => void startRecording(label, notes)}
            >
              ● Start recording
            </button>
          ) : (
            <button className="btn danger" onClick={() => void stopRecording()}>■ Stop recording</button>
          )}
          {!connected && <span className="small muted">Connect a device first.</span>}
          {connected && !currentSubjectCode && <span className="small muted">Select a subject first.</span>}
        </div>

        {recording && (
          <div style={{ marginTop: 16 }}>
            <div className="tiles">
              <div className="tile"><div className="label">Duration</div><div className="value">{fmtDuration(durationMs)}</div></div>
              <div className="tile"><div className="label">ECG samples</div><div className="value">{counts.ecg.toLocaleString()}</div></div>
              <div className="tile"><div className="label">BioZ samples</div><div className="value">{counts.bioz.toLocaleString()}</div></div>
              <div className="tile"><div className="label">PPG samples</div><div className="value">{counts.ppg.toLocaleString()}</div></div>
              <div className="tile"><div className="label">Dropped</div><div className="value">{dropped.ecg + dropped.bioz + dropped.ppg}</div></div>
              <div className="tile"><div className="label">Cuff readings</div><div className="value">{cuffCount}</div></div>
            </div>
            <h3 style={{ marginTop: 16 }}>Annotations</h3>
            <div className="row">
              <button className="btn" onClick={() => setShowCuff(true)}>＋ Cuff reading (ground truth)</button>
              <button className="btn secondary" onClick={() => void addMarker('marker')}>Marker</button>
              <button className="btn secondary" onClick={() => void addMarker('artifact')}>Artifact</button>
              <button className="btn secondary" onClick={() => void addMarker('motion_start')}>Motion start</button>
              <button className="btn secondary" onClick={() => void addMarker('motion_stop')}>Motion stop</button>
            </div>
          </div>
        )}
      </div>

      {showNew && <NewSubjectModal onClose={() => setShowNew(false)} onSave={async (s) => { await saveSubject(s); await selectSubject(s.code); setShowNew(false); }} existing={subjects} />}
      {showCuff && <CuffModal onClose={() => setShowCuff(false)} onSave={async (sbp, dbp) => { await addCuffReading(sbp, dbp); setShowCuff(false); }} />}
    </>
  );
}

function NewSubjectModal({ onClose, onSave, existing }: { onClose: () => void; onSave: (s: Subject) => void; existing: Subject[] }) {
  const [code, setCode] = useState('');
  const [ageBand, setAgeBand] = useState(AGE_BANDS[1]);
  const [sex, setSex] = useState('');
  const [notes, setNotes] = useState('');
  const dup = existing.some((s) => s.code === code.trim());
  return (
    <div className="overlay" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>New subject</h2>
        <div className="row"><label className="field grow">Code (non-identifying)<input value={code} onChange={(e) => setCode(e.target.value)} placeholder="S01" /></label></div>
        <div className="row">
          <label className="field">Age band<select value={ageBand} onChange={(e) => setAgeBand(e.target.value)}>{AGE_BANDS.map((a) => <option key={a}>{a}</option>)}</select></label>
          <label className="field">Sex (optional)<select value={sex} onChange={(e) => setSex(e.target.value)}><option value="">—</option><option>F</option><option>M</option><option>other</option></select></label>
          <label className="field grow">Notes<input value={notes} onChange={(e) => setNotes(e.target.value)} /></label>
        </div>
        {dup && <p className="small" style={{ color: 'var(--bad)' }}>A subject with that code already exists.</p>}
        <div className="row" style={{ marginTop: 16, justifyContent: 'flex-end' }}>
          <button className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn" disabled={!code.trim() || dup} onClick={() => onSave({ code: code.trim(), ageBand, sex: sex || undefined, notes, createdAt: new Date().toISOString() })}>Save</button>
        </div>
      </div>
    </div>
  );
}

function CuffModal({ onClose, onSave }: { onClose: () => void; onSave: (sbp: number, dbp: number) => void }) {
  const [sbp, setSbp] = useState('120');
  const [dbp, setDbp] = useState('80');
  const s = Number(sbp);
  const d = Number(dbp);
  const valid = s > 40 && s < 260 && d > 20 && d < 200 && d < s;
  return (
    <div className="overlay" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>Reference cuff reading</h2>
        <p className="muted small">Enter the reference cuff blood pressure now. It is stored as ground truth at the current device timestamp and added as a calibration pair if a PAT is available.</p>
        <div className="row">
          <label className="field">Systolic (mmHg)<input inputMode="numeric" value={sbp} onChange={(e) => setSbp(e.target.value)} /></label>
          <label className="field">Diastolic (mmHg)<input inputMode="numeric" value={dbp} onChange={(e) => setDbp(e.target.value)} /></label>
        </div>
        <div className="row" style={{ marginTop: 16, justifyContent: 'flex-end' }}>
          <button className="btn secondary" onClick={onClose}>Cancel</button>
          <button className="btn" disabled={!valid} onClick={() => onSave(s, d)}>Save reading</button>
        </div>
      </div>
    </div>
  );
}
