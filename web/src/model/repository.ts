/** CRUD helpers and the recording pipeline over the Dexie database. */
import type { BiozPacket, EcgPacket, PpgPacket } from '../ble/packets';
import type { StreamKind } from '../ble/protocol';
import { US_PER_S } from '../dsp/constants';
import { db } from './db';
import type {
  Annotation,
  Calibration,
  MetricsRecord,
  Session,
  StreamChunk,
  Subject,
} from './types';

// ---- subjects ----
export async function upsertSubject(s: Subject): Promise<void> {
  await db.subjects.put(s);
}
export const listSubjects = () => db.subjects.orderBy('createdAt').reverse().toArray();
export const getSubject = (code: string) => db.subjects.get(code);
export async function deleteSubject(code: string): Promise<void> {
  const sessions = await db.sessions.where('subjectCode').equals(code).toArray();
  await Promise.all(sessions.map((s) => deleteSession(s.id)));
  await db.calibrations.where('subjectCode').equals(code).delete();
  await db.subjects.delete(code);
}

// ---- sessions ----
export async function createSession(s: Session): Promise<void> {
  await db.sessions.put(s);
}
export async function endSession(id: string, endedAt: string): Promise<void> {
  await db.sessions.update(id, { endedAt });
}
export const getSession = (id: string) => db.sessions.get(id);
export const listSessions = () => db.sessions.orderBy('startedAt').reverse().toArray();
export async function deleteSession(id: string): Promise<void> {
  await db.transaction('rw', db.chunks, db.metrics, db.annotations, db.sessions, async () => {
    await db.chunks.where('sessionId').equals(id).delete();
    await db.metrics.where('sessionId').equals(id).delete();
    await db.annotations.where('sessionId').equals(id).delete();
    await db.sessions.delete(id);
  });
}

// ---- annotations ----
export async function addAnnotation(a: Annotation): Promise<number> {
  return db.annotations.add(a);
}
export const listAnnotations = (sessionId: string) =>
  db.annotations.where('sessionId').equals(sessionId).sortBy('tUs');

// ---- calibrations ----
export async function saveCalibration(c: Calibration): Promise<number> {
  return db.calibrations.add(c);
}
export async function latestCalibration(subjectCode: string): Promise<Calibration | undefined> {
  const all = await db.calibrations.where('subjectCode').equals(subjectCode).sortBy('createdAt');
  return all[all.length - 1];
}
export const listCalibrations = (subjectCode: string) =>
  db.calibrations.where('subjectCode').equals(subjectCode).sortBy('createdAt');

// ---- metrics ----
export async function addMetrics(m: MetricsRecord): Promise<void> {
  await db.metrics.add(m);
}
export const listMetrics = (sessionId: string) =>
  db.metrics.where('sessionId').equals(sessionId).sortBy('tUs');

// ---- reading streams back (replay / export) ----
export interface SessionStreams {
  ecg: { t: Float64Array; ecg: Int32Array };
  bioz: { t: Float64Array; z0: Int32Array; dz: Int32Array };
  ppg: { t: Float64Array; green: Uint32Array; red: Uint32Array; ir: Uint32Array };
}

export async function readSessionStreams(sessionId: string): Promise<SessionStreams> {
  const chunks = await db.chunks.where('sessionId').equals(sessionId).sortBy('tStartUs');
  const byStream = (s: StreamKind) => chunks.filter((c) => c.stream === s);
  return {
    ecg: {
      t: concatF64(byStream('ecg').map((c) => c.t)),
      ecg: concatI32(byStream('ecg').map((c) => c.ecg!)),
    },
    bioz: {
      t: concatF64(byStream('bioz').map((c) => c.t)),
      z0: concatI32(byStream('bioz').map((c) => c.z0!)),
      dz: concatI32(byStream('bioz').map((c) => c.dz!)),
    },
    ppg: {
      t: concatF64(byStream('ppg').map((c) => c.t)),
      green: concatU32(byStream('ppg').map((c) => c.green!)),
      red: concatU32(byStream('ppg').map((c) => c.red!)),
      ir: concatU32(byStream('ppg').map((c) => c.ir!)),
    },
  };
}

/**
 * Buffers live samples and flushes them to the DB in ~2 s chunks. One instance per
 * active recording session. Robust to mid-stream disconnects (flush on stop / gap).
 */
export class Recorder {
  private buffers: Record<StreamKind, BufferState> = {
    ecg: emptyBuffer(),
    bioz: emptyBuffer(),
    ppg: emptyBuffer(),
  };
  readonly counts: Record<StreamKind, number> = { ecg: 0, bioz: 0, ppg: 0 };
  private readonly flushSamples: Record<StreamKind, number>;

  constructor(public readonly sessionId: string) {
    this.flushSamples = { ecg: 512, bioz: 128, ppg: 800 };
  }

  ingestEcg(p: EcgPacket): void {
    const buf = this.buffers.ecg;
    if (buf.tStartUs == null) buf.tStartUs = p.tUs;
    buf.rate = p.sampleRateHz;
    const dt = US_PER_S / p.sampleRateHz;
    for (let i = 0; i < p.samples.length; i++) {
      buf.t.push(p.tUs + Math.round(i * dt));
      buf.a.push(p.samples[i]);
    }
    this.counts.ecg += p.samples.length;
    if (buf.a.length >= this.flushSamples.ecg) void this.flush('ecg');
  }

  ingestBioz(p: BiozPacket): void {
    const buf = this.buffers.bioz;
    if (buf.tStartUs == null) buf.tStartUs = p.tUs;
    buf.rate = p.sampleRateHz;
    const dt = US_PER_S / p.sampleRateHz;
    for (let i = 0; i < p.dz.length; i++) {
      buf.t.push(p.tUs + Math.round(i * dt));
      buf.a.push(p.z0Milliohm); // forward-filled z0
      buf.b.push(p.dz[i]);
    }
    this.counts.bioz += p.dz.length;
    if (buf.a.length >= this.flushSamples.bioz) void this.flush('bioz');
  }

  ingestPpg(p: PpgPacket): void {
    const buf = this.buffers.ppg;
    if (buf.tStartUs == null) buf.tStartUs = p.tUs;
    buf.rate = p.sampleRateHz;
    const dt = US_PER_S / p.sampleRateHz;
    for (let i = 0; i < p.green.length; i++) {
      buf.t.push(p.tUs + Math.round(i * dt));
      buf.a.push(p.green[i]);
      buf.b.push(p.red[i]);
      buf.c.push(p.ir[i]);
    }
    this.counts.ppg += p.green.length;
    if (buf.a.length >= this.flushSamples.ppg) void this.flush('ppg');
  }

  /** Persist buffered samples for one stream as a StreamChunk. */
  async flush(stream: StreamKind): Promise<void> {
    const buf = this.buffers[stream];
    if (buf.a.length === 0 || buf.tStartUs == null) return;
    const chunk: StreamChunk = {
      sessionId: this.sessionId,
      stream,
      tStartUs: buf.tStartUs,
      sampleRateHz: buf.rate,
      t: Float64Array.from(buf.t),
    };
    if (stream === 'ecg') chunk.ecg = Int32Array.from(buf.a);
    else if (stream === 'bioz') {
      chunk.z0 = Int32Array.from(buf.a);
      chunk.dz = Int32Array.from(buf.b);
    } else {
      chunk.green = Uint32Array.from(buf.a);
      chunk.red = Uint32Array.from(buf.b);
      chunk.ir = Uint32Array.from(buf.c);
    }
    this.buffers[stream] = emptyBuffer();
    await db.chunks.add(chunk);
  }

  async flushAll(): Promise<void> {
    await Promise.all((['ecg', 'bioz', 'ppg'] as StreamKind[]).map((s) => this.flush(s)));
  }
}

interface BufferState {
  tStartUs: number | null;
  rate: number;
  t: number[];
  a: number[];
  b: number[];
  c: number[];
}
function emptyBuffer(): BufferState {
  return { tStartUs: null, rate: 0, t: [], a: [], b: [], c: [] };
}

function concatF64(arrs: Float64Array[]): Float64Array {
  const n = arrs.reduce((s, a) => s + a.length, 0);
  const out = new Float64Array(n);
  let o = 0;
  for (const a of arrs) {
    out.set(a, o);
    o += a.length;
  }
  return out;
}
function concatI32(arrs: Int32Array[]): Int32Array {
  const n = arrs.reduce((s, a) => s + a.length, 0);
  const out = new Int32Array(n);
  let o = 0;
  for (const a of arrs) {
    out.set(a, o);
    o += a.length;
  }
  return out;
}
function concatU32(arrs: Uint32Array[]): Uint32Array {
  const n = arrs.reduce((s, a) => s + a.length, 0);
  const out = new Uint32Array(n);
  let o = 0;
  for (const a of arrs) {
    out.set(a, o);
    o += a.length;
  }
  return out;
}
