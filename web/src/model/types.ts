/** Local-first data model (§4). Identify subjects only by a non-PII code. */
import type { CalibModel } from '../dsp/calibration';
import type { StreamKind } from '../ble/protocol';

export type SessionLabel = 'rest' | 'seated' | 'walking' | 'post-exercise' | 'other';
export type AnnotationType = 'cuff_reading' | 'motion_start' | 'motion_stop' | 'artifact' | 'marker';
export type MetricsSource = 'app' | 'firmware';

export interface Subject {
  code: string; // primary key, non-identifying
  ageBand: string;
  sex?: string;
  notes: string;
  createdAt: string; // ISO-8601
}

export interface Session {
  id: string;
  subjectCode: string;
  label: SessionLabel;
  deviceId: string;
  firmwareVersion: string;
  startedAt: string;
  endedAt: string | null;
  notes: string;
  metricsSource: MetricsSource;
  gating: { motionThresh: number; contactThresh: number; windowMs: number };
  /** Calibration snapshot at session start (or null). */
  calibrationSnapshot: Calibration | null;
}

/** One stored block of samples; timestamps are explicit (extended device µs). */
export interface StreamChunk {
  id?: number;
  sessionId: string;
  stream: StreamKind;
  tStartUs: number;
  sampleRateHz: number;
  /** Per-sample device timestamps (µs). */
  t: Float64Array;
  /** ECG only. */
  ecg?: Int32Array;
  /** BioZ only (z0 forward-filled per sample). */
  z0?: Int32Array;
  dz?: Int32Array;
  /** PPG only. */
  green?: Uint32Array;
  red?: Uint32Array;
  ir?: Uint32Array;
}

export interface MetricsRecord {
  id?: number;
  sessionId: string;
  tUs: number;
  hrBpm: number | null;
  spo2Pct: number | null;
  contactQuality: number;
  motion: number;
  patUs: number | null;
  sbpMmHg: number | null;
  dbpMmHg: number | null;
}

export interface Annotation {
  id?: number;
  sessionId: string;
  tUs: number;
  type: AnnotationType;
  sbp?: number;
  dbp?: number;
  text?: string;
}

export interface Calibration {
  id?: number;
  subjectCode: string;
  model: CalibModel;
  coeffs: { sbp: [number, number]; dbp: [number, number] };
  referencePairs: { patUs: number; sbp: number; dbp: number }[];
  rmseSbp: number;
  rmseDbp: number;
  r: number;
  createdAt: string;
}

/** App settings (persisted in localStorage). */
export interface AppSettings {
  metricsSource: MetricsSource;
  motionThresh: number;
  contactThresh: number;
  gatingWindowMs: number;
  calibModel: CalibModel;
  streamRates: Record<StreamKind, number>;
  theme: 'dark' | 'light' | 'system';
  consentAccepted: boolean;
  disclaimerAcknowledged: boolean;
}
