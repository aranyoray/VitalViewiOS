/**
 * CSV session export (§9 / docs/CSV_FORMAT.md). Pure builders (testable without a DB)
 * plus a DB-reading entry point that produces a downloadable ZIP bundle.
 */
import { readSessionStreams, type SessionStreams } from './repository';
import { db } from './db';
import { zipStore } from './zip';
import type { Annotation, Calibration, MetricsRecord, Session, Subject } from './types';

export interface BundleData {
  session: Session;
  subject: Subject | null;
  calibration: Calibration | null;
  streams: SessionStreams;
  metrics: MetricsRecord[];
  annotations: Annotation[];
}

/** RFC-4180 field escaping; null/undefined → empty cell. */
export function csvEscape(v: string | number | null | undefined): string {
  if (v == null) return '';
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function toCsv(header: string[], rows: (string | number | null | undefined)[][]): string {
  const lines = [header.join(',')];
  for (const row of rows) lines.push(row.map(csvEscape).join(','));
  return lines.join('\n') + '\n';
}

export function buildSessionMeta(d: BundleData): string {
  return JSON.stringify(
    {
      schemaVersion: 1,
      session: {
        id: d.session.id,
        subjectCode: d.session.subjectCode,
        label: d.session.label,
        deviceId: d.session.deviceId,
        firmwareVersion: d.session.firmwareVersion,
        startedAt: d.session.startedAt,
        endedAt: d.session.endedAt,
        notes: d.session.notes,
        metricsSource: d.session.metricsSource,
        gating: d.session.gating,
      },
      subject: d.subject
        ? { code: d.subject.code, ageBand: d.subject.ageBand, sex: d.subject.sex ?? null, notes: d.subject.notes }
        : { code: d.session.subjectCode },
      calibration: d.calibration
        ? {
            model: d.calibration.model,
            coeffs: d.calibration.coeffs,
            rmseSbp: d.calibration.rmseSbp,
            rmseDbp: d.calibration.rmseDbp,
            r: d.calibration.r,
            createdAt: d.calibration.createdAt,
          }
        : null,
    },
    null,
    2,
  );
}

export function buildBundleFiles(d: BundleData): Record<string, string> {
  const { streams } = d;

  const ecgRows: (string | number)[][] = [];
  for (let i = 0; i < streams.ecg.t.length; i++) ecgRows.push([streams.ecg.t[i], streams.ecg.ecg[i]]);

  const biozRows: (string | number)[][] = [];
  for (let i = 0; i < streams.bioz.t.length; i++)
    biozRows.push([streams.bioz.t[i], streams.bioz.z0[i], streams.bioz.dz[i]]);

  const ppgRows: (string | number)[][] = [];
  for (let i = 0; i < streams.ppg.t.length; i++)
    ppgRows.push([streams.ppg.t[i], streams.ppg.green[i], streams.ppg.red[i], streams.ppg.ir[i]]);

  const metricsRows = d.metrics.map((m) => [
    m.tUs,
    m.hrBpm ?? '',
    m.spo2Pct ?? '',
    m.contactQuality,
    m.motion,
    m.patUs == null ? '' : m.patUs / 1000,
    m.sbpMmHg ?? '',
    m.dbpMmHg ?? '',
  ]);

  const annoRows = d.annotations.map((a) => [a.tUs, a.type, a.sbp ?? '', a.dbp ?? '', a.text ?? '']);

  return {
    'session_meta.json': buildSessionMeta(d),
    'ecg.csv': toCsv(['t_us', 'ecg'], ecgRows),
    'bioz.csv': toCsv(['t_us', 'z0_milliohm', 'dz'], biozRows),
    'ppg.csv': toCsv(['t_us', 'green', 'red', 'ir'], ppgRows),
    'metrics.csv': toCsv(
      ['t_us', 'hr_bpm', 'spo2_pct', 'contact_quality', 'motion', 'pat_ms', 'sbp_est', 'dbp_est'],
      metricsRows,
    ),
    'annotations.csv': toCsv(['t_us', 'type', 'sbp', 'dbp', 'text'], annoRows),
  };
}

/** Read a session from the DB and produce a downloadable ZIP bundle. */
export async function exportSession(sessionId: string): Promise<{ blob: Blob; filename: string }> {
  const session = await db.sessions.get(sessionId);
  if (!session) throw new Error(`Session ${sessionId} not found`);
  const subject = (await db.subjects.get(session.subjectCode)) ?? null;
  const [streams, metrics, annotations] = await Promise.all([
    readSessionStreams(sessionId),
    db.metrics.where('sessionId').equals(sessionId).sortBy('tUs'),
    db.annotations.where('sessionId').equals(sessionId).sortBy('tUs'),
  ]);
  const files = buildBundleFiles({
    session,
    subject,
    calibration: session.calibrationSnapshot,
    streams,
    metrics,
    annotations,
  });
  const enc = new TextEncoder();
  const zip = zipStore(Object.entries(files).map(([name, content]) => ({ name, data: enc.encode(content) })));
  const folder = `${session.label}_${session.id.slice(0, 8)}`;
  // zipStore returns a Uint8Array view; copy into a fresh ArrayBuffer for the Blob.
  const blob = new Blob([zip.slice()], { type: 'application/zip' });
  return { blob, filename: `monivitals_${folder}.zip` };
}
