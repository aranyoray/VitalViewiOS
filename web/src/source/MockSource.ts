/**
 * Synthetic data source (§8): drives realistic packets on timers with no hardware, so
 * the entire app — dashboard, recording, calibration, gating, export — is demoable.
 * Emits typed packets with already-monotonic device timestamps.
 */
import type { BiozPacket, EcgPacket, MetricsPacket, PpgPacket } from '../ble/packets';
import { DEFAULT_K, DEFAULT_RATE_HZ, StreamBit, type StreamKind } from '../ble/protocol';
import { ContactMotionEstimator } from '../dsp/bioz';
import { US_PER_S } from '../dsp/constants';
import { BaseDataSource, type ConnectionState } from './DataSource';
import { MockSignal, type MockParams } from './mockSignal';

const TICK_MS = 40;
const METRICS_MS = 500;

interface StreamState {
  rateHz: number;
  k: number;
  nextIndex: number;
  seq: number;
}

export class MockSource extends BaseDataSource {
  readonly isMock = true;
  clockOffsetUs: number | null = null;
  deviceName = 'VitalView Mock';

  private signal: MockSignal;
  private streams: Record<StreamKind, StreamState>;
  private enabledMask = 0;
  private running = false;
  private startPerfMs = 0;
  private batteryPct = 100;
  private timer: ReturnType<typeof setInterval> | null = null;
  private metricsTimer: ReturnType<typeof setInterval> | null = null;
  private statusTimer: ReturnType<typeof setInterval> | null = null;
  private lastMetricsDeviceUs = 0;
  private readonly contact: ContactMotionEstimator;

  constructor(params: Partial<MockParams> = {}) {
    super();
    this.signal = new MockSignal(params);
    this.contact = new ContactMotionEstimator(this.signal.p.biozRateHz);
    this.streams = {
      ecg: { rateHz: DEFAULT_RATE_HZ.ecg, k: DEFAULT_K.ecg, nextIndex: 0, seq: 0 },
      bioz: { rateHz: DEFAULT_RATE_HZ.bioz, k: DEFAULT_K.bioz, nextIndex: 0, seq: 0 },
      ppg: { rateHz: DEFAULT_RATE_HZ.ppg, k: DEFAULT_K.ppg, nextIndex: 0, seq: 0 },
    };
  }

  /** Live-adjust the synthetic signal (HR/PAT/SpO2/etc.) from Settings. */
  setParams(params: Partial<MockParams>): void {
    Object.assign(this.signal.p, params);
  }

  getParams(): MockParams {
    return this.signal.p;
  }

  /** Inject a motion burst now (drives the motion/gating demo). */
  injectMotion(durationMs = 2000, severity = 4): void {
    const now = this.deviceNowUs();
    this.signal.p.motionBursts.push({
      startUs: now,
      endUs: now + durationMs * 1000,
      severity,
    });
  }

  async connect(): Promise<void> {
    this.setState('connecting');
    await delay(150);
    this.setState('connected');
    this.startPerfMs = now();
    this.getInfoSync();
    this.statusTimer = setInterval(() => this.emitStatus(), 1000);
  }

  async disconnect(): Promise<void> {
    await this.stop();
    clearTimer(this.statusTimer);
    this.statusTimer = null;
    this.setState('disconnected');
  }

  async start(streamMask: number): Promise<void> {
    this.enabledMask = streamMask;
    this.startPerfMs = now();
    this.lastMetricsDeviceUs = 0;
    for (const s of Object.values(this.streams)) {
      s.nextIndex = 0;
      s.seq = 0;
    }
    this.contact.reset();
    this.running = true;
    this.timer = setInterval(() => this.tick(), TICK_MS);
    this.metricsTimer = setInterval(() => this.emitMetrics(), METRICS_MS);
  }

  async stop(): Promise<void> {
    this.running = false;
    clearTimer(this.timer);
    clearTimer(this.metricsTimer);
    this.timer = null;
    this.metricsTimer = null;
  }

  async setRate(stream: StreamKind, hz: number): Promise<void> {
    const s = this.streams[stream];
    s.rateHz = hz;
    if (this.running) s.nextIndex = Math.floor(this.elapsedS() * hz);
    if (stream === 'bioz') this.signal.p.biozRateHz = hz;
    if (stream === 'ecg') this.signal.p.ecgRateHz = hz;
    if (stream === 'ppg') this.signal.p.ppgRateHz = hz;
  }

  async syncClock(): Promise<void> {
    await delay(20);
    const deviceTus = this.deviceNowUs();
    this.clockOffsetUs = Date.now() * 1000 - deviceTus;
  }

  async getInfo(): Promise<void> {
    this.getInfoSync();
  }

  // ---- internals ----

  private getInfoSync(): void {
    this.emitter.emit('info', {
      kind: 'info',
      firmwareVersion: '1.0.0-mock',
      deviceId: 'mock00000001',
      capabilities: StreamBit.ecg | StreamBit.bioz | StreamBit.ppg,
    });
    this.emitter.emit('battery', this.batteryPct);
  }

  private elapsedS(): number {
    return (now() - this.startPerfMs) / 1000;
  }

  private deviceNowUs(): number {
    return Math.round(this.elapsedS() * US_PER_S);
  }

  private tick(): void {
    if (!this.running) return;
    const elapsed = this.elapsedS();
    if (this.enabledMask & StreamBit.ecg) this.tickEcg(elapsed);
    if (this.enabledMask & StreamBit.bioz) this.tickBioz(elapsed);
    if (this.enabledMask & StreamBit.ppg) this.tickPpg(elapsed);
  }

  private tickEcg(elapsedS: number): void {
    const s = this.streams.ecg;
    const target = Math.floor(elapsedS * s.rateHz);
    while (s.nextIndex < target) {
      const count = Math.min(s.k, target - s.nextIndex);
      const first = s.nextIndex;
      const tUs = Math.round((first * US_PER_S) / s.rateHz);
      const samples = new Int32Array(count);
      for (let i = 0; i < count; i++) {
        const t = Math.round(((first + i) * US_PER_S) / s.rateHz);
        samples[i] = Math.round(this.signal.ecgAt(t));
      }
      const p: EcgPacket = { kind: 'ecg', seq: s.seq, tUs, sampleRateHz: s.rateHz, samples };
      this.emitter.emit('ecg', p);
      s.nextIndex += count;
      s.seq = (s.seq + 1) & 0xffff;
    }
  }

  private tickBioz(elapsedS: number): void {
    const s = this.streams.bioz;
    const target = Math.floor(elapsedS * s.rateHz);
    while (s.nextIndex < target) {
      const count = Math.min(s.k, target - s.nextIndex);
      const first = s.nextIndex;
      const tUs = Math.round((first * US_PER_S) / s.rateHz);
      const z0 = Math.round(this.signal.z0At(tUs));
      const dz = new Int32Array(count);
      for (let i = 0; i < count; i++) {
        const t = Math.round(((first + i) * US_PER_S) / s.rateHz);
        dz[i] = Math.round(this.signal.dzAt(t));
        this.contact.pushDz(dz[i]);
      }
      this.contact.pushZ0(z0);
      const p: BiozPacket = { kind: 'bioz', seq: s.seq, tUs, sampleRateHz: s.rateHz, z0Milliohm: z0, dz };
      this.emitter.emit('bioz', p);
      s.nextIndex += count;
      s.seq = (s.seq + 1) & 0xffff;
    }
  }

  private tickPpg(elapsedS: number): void {
    const s = this.streams.ppg;
    const target = Math.floor(elapsedS * s.rateHz);
    while (s.nextIndex < target) {
      const count = Math.min(s.k, target - s.nextIndex);
      const first = s.nextIndex;
      const tUs = Math.round((first * US_PER_S) / s.rateHz);
      const green = new Uint32Array(count);
      const red = new Uint32Array(count);
      const ir = new Uint32Array(count);
      for (let i = 0; i < count; i++) {
        const t = Math.round(((first + i) * US_PER_S) / s.rateHz);
        green[i] = Math.max(0, Math.round(this.signal.greenAt(t)));
        red[i] = Math.max(0, Math.round(this.signal.redAt(t)));
        ir[i] = Math.max(0, Math.round(this.signal.irAt(t)));
      }
      const p: PpgPacket = { kind: 'ppg', seq: s.seq, tUs, sampleRateHz: s.rateHz, green, red, ir };
      this.emitter.emit('ppg', p);
      s.nextIndex += count;
      s.seq = (s.seq + 1) & 0xffff;
    }
  }

  private emitMetrics(): void {
    if (!this.running) return;
    const tUs = this.deviceNowUs();
    const beats = this.signal.rPeakTimes(this.lastMetricsDeviceUs, tUs);
    this.lastMetricsDeviceUs = tUs;
    const p: MetricsPacket = {
      kind: 'metrics',
      tUs,
      hrBpm: this.signal.p.hrBpm,
      spo2Pct: this.signal.p.spo2Target,
      contactQuality: this.contact.contactQuality(),
      motion: this.contact.motion(),
      patUs: this.signal.p.patMs * 1000,
      sbpMmHg: null, // firmware reports BP uncalibrated; calibration is per-subject in-app
      dbpMmHg: null,
      rpeak: beats.length > 0,
    };
    this.emitter.emit('metrics', p);
  }

  private emitStatus(): void {
    // Slow battery drain for realism.
    this.batteryPct = Math.max(0, this.batteryPct - 0.05);
    this.emitter.emit('battery', Math.round(this.batteryPct));
    this.emitter.emit('status', {
      kind: 'status',
      streamingMask: this.running ? this.enabledMask : 0,
      ecgRateCode: 1,
      biozRateCode: 1,
      ppgRateCode: 1,
      tUs: this.deviceNowUs(),
      batteryPct: Math.round(this.batteryPct),
      errorFlags: 0,
    });
  }
}

function now(): number {
  return typeof performance !== 'undefined' ? performance.now() : Date.now();
}
function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
function clearTimer(t: ReturnType<typeof setInterval> | null): void {
  if (t != null) clearInterval(t);
}

export type { ConnectionState };
