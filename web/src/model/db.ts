/** IndexedDB storage via Dexie. Local-first; no cloud sync (§4). */
import Dexie, { type Table } from 'dexie';
import type {
  Annotation,
  Calibration,
  MetricsRecord,
  Session,
  StreamChunk,
  Subject,
} from './types';

export class VitalViewDB extends Dexie {
  subjects!: Table<Subject, string>;
  sessions!: Table<Session, string>;
  chunks!: Table<StreamChunk, number>;
  metrics!: Table<MetricsRecord, number>;
  annotations!: Table<Annotation, number>;
  calibrations!: Table<Calibration, number>;

  constructor() {
    super('vitalview');
    this.version(1).stores({
      subjects: 'code, createdAt',
      sessions: 'id, subjectCode, startedAt',
      chunks: '++id, sessionId, [sessionId+stream]',
      metrics: '++id, sessionId',
      annotations: '++id, sessionId',
      calibrations: '++id, subjectCode, createdAt',
    });
  }
}

export const db = new VitalViewDB();
