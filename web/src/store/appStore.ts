/**
 * Central application store (Zustand). Orchestrates the data source, the live runtime
 * (ring buffers + MetricsEngine), recording, and settings. High-rate sample data lives
 * in the runtime (non-reactive); only throttled metrics/counts/connection state are
 * reactive here.
 */
import { create } from 'zustand';
import type { MetricsPacket } from '../ble/packets';
import { ALL_STREAMS_MASK, type StreamKind } from '../ble/protocol';
import { fitCalibration, type CalibModel, type RefPair } from '../dsp/calibration';
import { CONTACT_THRESH, MOTION_THRESH, MOTION_WINDOW_MS } from '../dsp/constants';
import type { MetricsSnapshot } from '../dsp/engine';
import { buffers, engine, resetRuntime } from '../live/runtime';
import { exportSession } from '../model/csv';
import {
  addAnnotation,
  addMetrics,
  createSession,
  endSession,
  latestCalibration,
  listSubjects,
  Recorder,
  saveCalibration,
  upsertSubject,
} from '../model/repository';
import type { AnnotationType, AppSettings, Calibration, Session, SessionLabel, Subject } from '../model/types';
import { BleSource } from '../source/BleSource';
import type { ConnectionState, DataSource } from '../source/DataSource';
import { MockSource } from '../source/MockSource';
import type { MockParams } from '../source/mockSignal';
import { downloadBlob } from '../util/download';

const SETTINGS_KEY = 'vitalview.settings';
const TICK_MS = 250;

function loadSettings(): AppSettings {
  const defaults: AppSettings = {
    metricsSource: 'app',
    motionThresh: MOTION_THRESH,
    contactThresh: CONTACT_THRESH,
    gatingWindowMs: MOTION_WINDOW_MS,
    calibModel: 'linear_invPAT',
    streamRates: { ecg: 256, bioz: 64, ppg: 100 },
    theme: 'system',
    consentAccepted: false,
    disclaimerAcknowledged: false,
  };
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    return raw ? { ...defaults, ...JSON.parse(raw) } : defaults;
  } catch {
    return defaults;
  }
}

interface AppState {
  settings: AppSettings;
  updateSettings: (partial: Partial<AppSettings>) => void;

  source: DataSource | null;
  isMock: boolean;
  connectionState: ConnectionState;
  deviceName: string | null;
  batteryPct: number | null;
  errorFlags: number;
  dropped: Record<StreamKind, number>;
  clockOffsetUs: number | null;
  streaming: boolean;

  appMetrics: MetricsSnapshot | null;
  firmwareMetrics: MetricsPacket | null;
  liveMetrics: MetricsSnapshot | null;

  subjects: Subject[];
  currentSubjectCode: string | null;
  currentCalibration: Calibration | null;

  recording: { session: Session; startedAtMs: number } | null;
  recordCounts: Record<StreamKind, number>;
  recordDurationMs: number;
  cuffReadingCount: number;

  calibrationPairs: RefPair[];

  // actions
  connectMock: () => Promise<void>;
  connectBle: () => Promise<void>;
  disconnect: () => Promise<void>;
  startStreaming: () => Promise<void>;
  stopStreaming: () => Promise<void>;
  setMockParams: (p: Partial<MockParams>) => void;
  injectMockMotion: () => void;

  refreshSubjects: () => Promise<void>;
  saveSubject: (s: Subject) => Promise<void>;
  selectSubject: (code: string | null) => Promise<void>;

  startRecording: (label: SessionLabel, notes: string) => Promise<void>;
  stopRecording: () => Promise<void>;
  addCuffReading: (sbp: number, dbp: number) => Promise<void>;
  addMarker: (type: AnnotationType, text?: string) => Promise<void>;
  exportSessionZip: (sessionId: string) => Promise<void>;

  addCalibrationPair: (sbp: number, dbp: number) => boolean;
  removeCalibrationPair: (index: number) => void;
  clearCalibrationPairs: () => void;
  saveCalibrationFit: () => Promise<boolean>;
}

let recorder: Recorder | null = null;
let tickHandle: ReturnType<typeof setInterval> | null = null;
let unsubscribers: Array<() => void> = [];

export const useAppStore = create<AppState>((set, get) => {
  // ---- packet handlers (mutate the non-reactive runtime only) ----
  function wire(source: DataSource): void {
    unsubscribers.push(
      source.on('ecg', (p) => {
        const dt = 1_000_000 / p.sampleRateHz;
        for (let i = 0; i < p.samples.length; i++) buffers.ecg.push(p.tUs + Math.round(i * dt), p.samples[i]);
        engine.ingestEcg(p);
        recorder?.ingestEcg(p);
      }),
      source.on('bioz', (p) => {
        const dt = 1_000_000 / p.sampleRateHz;
        for (let i = 0; i < p.dz.length; i++) {
          buffers.biozDz.push(p.tUs + Math.round(i * dt), p.dz[i]);
        }
        buffers.z0.push(p.tUs, p.z0Milliohm);
        engine.ingestBioz(p);
        recorder?.ingestBioz(p);
      }),
      source.on('ppg', (p) => {
        const dt = 1_000_000 / p.sampleRateHz;
        for (let i = 0; i < p.green.length; i++) {
          const t = p.tUs + Math.round(i * dt);
          buffers.ppgGreen.push(t, p.green[i]);
          buffers.ppgRed.push(t, p.red[i]);
          buffers.ppgIr.push(t, p.ir[i]);
        }
        engine.ingestPpg(p);
        recorder?.ingestPpg(p);
      }),
      source.on('metrics', (p) => set({ firmwareMetrics: p })),
      source.on('battery', (pct) => set({ batteryPct: pct })),
      source.on('status', (s) => set({ errorFlags: s.errorFlags, batteryPct: s.batteryPct })),
      source.on('dropped', (stream, count) => {
        if (count > 0) set((st) => ({ dropped: { ...st.dropped, [stream]: st.dropped[stream] + count } }));
      }),
      source.on('connection', (state, detail) => {
        set({ connectionState: state, clockOffsetUs: source.clockOffsetUs, deviceName: source.deviceName });
        if (detail?.error) console.warn('connection:', detail.error);
      }),
    );
  }

  function startTick(): void {
    stopTick();
    tickHandle = setInterval(() => {
      const latest = Math.max(
        buffers.ecg.latestT() ?? 0,
        buffers.ppgGreen.latestT() ?? 0,
        buffers.biozDz.latestT() ?? 0,
      );
      const app = engine.snapshot(latest);
      const st = get();
      const live = resolveLive(app, st.firmwareMetrics, st.settings, st.currentCalibration);
      const patch: Partial<AppState> = { appMetrics: app, liveMetrics: live };
      if (recorder && st.recording) {
        patch.recordCounts = { ...recorder.counts };
        patch.recordDurationMs = Date.now() - st.recording.startedAtMs;
        void addMetrics({ sessionId: recorder.sessionId, ...stripKind(live ?? app) });
      }
      set(patch);
    }, TICK_MS);
  }
  function stopTick(): void {
    if (tickHandle != null) clearInterval(tickHandle);
    tickHandle = null;
  }

  async function teardownSource(): Promise<void> {
    stopTick();
    for (const u of unsubscribers) u();
    unsubscribers = [];
    const src = get().source;
    if (src) await src.disconnect();
  }

  return {
    settings: loadSettings(),
    updateSettings: (partial) => {
      const settings = { ...get().settings, ...partial };
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
      engine.setMotionThresh(settings.motionThresh);
      // Push rate changes to a connected device.
      const src = get().source;
      if (src && partial.streamRates) {
        for (const k of Object.keys(partial.streamRates) as StreamKind[]) {
          void src.setRate(k, settings.streamRates[k]);
        }
      }
      set({ settings });
    },

    source: null,
    isMock: false,
    connectionState: 'disconnected',
    deviceName: null,
    batteryPct: null,
    errorFlags: 0,
    dropped: { ecg: 0, bioz: 0, ppg: 0 },
    clockOffsetUs: null,
    streaming: false,

    appMetrics: null,
    firmwareMetrics: null,
    liveMetrics: null,

    subjects: [],
    currentSubjectCode: null,
    currentCalibration: null,

    recording: null,
    recordCounts: { ecg: 0, bioz: 0, ppg: 0 },
    recordDurationMs: 0,
    cuffReadingCount: 0,

    calibrationPairs: [],

    connectMock: async () => {
      await teardownSource();
      const source = new MockSource();
      engine.setMotionThresh(get().settings.motionThresh);
      set({ source, isMock: true, deviceName: source.deviceName });
      wire(source);
      await source.connect();
      await source.syncClock();
      set({ clockOffsetUs: source.clockOffsetUs });
    },

    connectBle: async () => {
      if (!BleSource.isSupported()) {
        set({ connectionState: 'unsupported' });
        return;
      }
      await teardownSource();
      const source = new BleSource();
      set({ source, isMock: false });
      wire(source);
      await source.connect();
    },

    disconnect: async () => {
      await get().stopRecording();
      await teardownSource();
      set({ source: null, streaming: false, connectionState: 'disconnected', firmwareMetrics: null });
    },

    startStreaming: async () => {
      const { source, currentCalibration } = get();
      if (!source) return;
      resetRuntime();
      engine.setMotionThresh(get().settings.motionThresh);
      engine.setCalibration(currentCalibration ?? null);
      set({ dropped: { ecg: 0, bioz: 0, ppg: 0 } });
      await source.start(ALL_STREAMS_MASK);
      startTick();
      set({ streaming: true });
    },

    stopStreaming: async () => {
      const { source } = get();
      if (source) await source.stop();
      stopTick();
      set({ streaming: false });
    },

    setMockParams: (p) => {
      const src = get().source;
      if (src instanceof MockSource) src.setParams(p);
    },
    injectMockMotion: () => {
      const src = get().source;
      if (src instanceof MockSource) src.injectMotion();
    },

    refreshSubjects: async () => set({ subjects: await listSubjects() }),
    saveSubject: async (s) => {
      await upsertSubject(s);
      await get().refreshSubjects();
    },
    selectSubject: async (code) => {
      const cal = code ? ((await latestCalibration(code)) ?? null) : null;
      engine.setCalibration(cal);
      set({ currentSubjectCode: code, currentCalibration: cal, calibrationPairs: [] });
    },

    startRecording: async (label, notes) => {
      const { source, currentSubjectCode, currentCalibration, settings } = get();
      if (!source || !currentSubjectCode) throw new Error('Select a subject and connect first');
      if (!get().streaming) await get().startStreaming();
      const session: Session = {
        id: crypto.randomUUID(),
        subjectCode: currentSubjectCode,
        label,
        deviceId: source.deviceName ?? 'unknown',
        firmwareVersion: get().isMock ? '1.0.0-mock' : 'unknown',
        startedAt: new Date().toISOString(),
        endedAt: null,
        notes,
        metricsSource: settings.metricsSource,
        gating: {
          motionThresh: settings.motionThresh,
          contactThresh: settings.contactThresh,
          windowMs: settings.gatingWindowMs,
        },
        calibrationSnapshot: currentCalibration ?? null,
      };
      await createSession(session);
      recorder = new Recorder(session.id);
      set({
        recording: { session, startedAtMs: Date.now() },
        recordCounts: { ecg: 0, bioz: 0, ppg: 0 },
        recordDurationMs: 0,
        cuffReadingCount: 0,
      });
    },

    stopRecording: async () => {
      const { recording } = get();
      if (!recording || !recorder) return;
      await recorder.flushAll();
      await endSession(recording.session.id, new Date().toISOString());
      recorder = null;
      set({ recording: null });
    },

    addCuffReading: async (sbp, dbp) => {
      const { recording, liveMetrics } = get();
      const tUs = latestDeviceUs();
      if (recording) {
        await addAnnotation({ sessionId: recording.session.id, tUs, type: 'cuff_reading', sbp, dbp });
        set({ cuffReadingCount: get().cuffReadingCount + 1 });
      }
      // Capture a calibration pair if a PAT is currently available.
      if (liveMetrics?.patUs != null) {
        set({ calibrationPairs: [...get().calibrationPairs, { patUs: liveMetrics.patUs, sbp, dbp }] });
      }
    },

    addMarker: async (type, text) => {
      const { recording } = get();
      if (!recording) return;
      await addAnnotation({ sessionId: recording.session.id, tUs: latestDeviceUs(), type, text });
    },

    exportSessionZip: async (sessionId) => {
      const { blob, filename } = await exportSession(sessionId);
      downloadBlob(filename, blob);
    },

    addCalibrationPair: (sbp, dbp) => {
      const pat = get().liveMetrics?.patUs;
      if (pat == null) return false;
      set({ calibrationPairs: [...get().calibrationPairs, { patUs: pat, sbp, dbp }] });
      return true;
    },
    removeCalibrationPair: (index) =>
      set({ calibrationPairs: get().calibrationPairs.filter((_, i) => i !== index) }),
    clearCalibrationPairs: () => set({ calibrationPairs: [] }),

    saveCalibrationFit: async () => {
      const { calibrationPairs, currentSubjectCode, settings } = get();
      if (!currentSubjectCode) return false;
      const fit = fitCalibration(calibrationPairs, settings.calibModel);
      if (!fit) return false;
      const cal: Calibration = {
        subjectCode: currentSubjectCode,
        model: fit.model,
        coeffs: fit.coeffs,
        referencePairs: calibrationPairs,
        rmseSbp: fit.rmseSbp,
        rmseDbp: fit.rmseDbp,
        r: fit.r,
        createdAt: new Date().toISOString(),
      };
      await saveCalibration(cal);
      engine.setCalibration(cal);
      set({ currentCalibration: cal });
      return true;
    },
  };
});

// ---- helpers ----

function latestDeviceUs(): number {
  return Math.max(buffers.ecg.latestT() ?? 0, buffers.ppgGreen.latestT() ?? 0, buffers.biozDz.latestT() ?? 0);
}

/** Drop the transient rpeak flag so the object matches the stored MetricsRecord shape. */
function stripKind(m: MetricsSnapshot): Omit<MetricsSnapshot, 'rpeak'> {
  const { rpeak, ...rest } = m;
  return rest;
}

/** Resolve the metrics to display: pick the source per settings, overlay calibrated BP. */
function resolveLive(
  app: MetricsSnapshot,
  firmware: MetricsPacket | null,
  settings: AppSettings,
  calibration: Calibration | null,
): MetricsSnapshot {
  const base: MetricsSnapshot =
    settings.metricsSource === 'firmware' && firmware
      ? {
          tUs: firmware.tUs,
          hrBpm: firmware.hrBpm,
          spo2Pct: firmware.spo2Pct,
          contactQuality: firmware.contactQuality,
          motion: firmware.motion,
          patUs: firmware.patUs,
          sbpMmHg: firmware.sbpMmHg,
          dbpMmHg: firmware.dbpMmHg,
          rpeak: firmware.rpeak,
        }
      : { ...app };
  if (calibration && base.patUs != null) {
    const x = calibration.model === 'linear_PAT' ? base.patUs / 1e6 : 1 / (base.patUs / 1e6);
    base.sbpMmHg = Math.round(calibration.coeffs.sbp[0] + calibration.coeffs.sbp[1] * x);
    base.dbpMmHg = Math.round(calibration.coeffs.dbp[0] + calibration.coeffs.dbp[1] * x);
  }
  return base;
}

export type { CalibModel };
