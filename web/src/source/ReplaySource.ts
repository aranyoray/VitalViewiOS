/**
 * Replays a REAL recorded biosignal (PhysioNet BIDMC: ECG lead II + PPG) served from
 * /bidmc_sample.json, so the DSP computes heart rate and pulse-arrival-time from genuine
 * waveforms instead of a self-encoding synthetic signal. The recording loops seamlessly
 * with monotonically increasing device timestamps.
 *
 * Mirrors ios/MoniVitals/Source/ReplaySource.swift.
 *
 * Notes on fidelity:
 *   • ECG + PPG are the real recording.
 *   • The dataset has single-wavelength PPG, so red/IR are synthesized from the real PPG
 *     shape at the AC ratio implied by the recording's own SpO2 reading — the SpO2 tile
 *     therefore reflects the RECORDED reference value, and is labeled as such.
 *   • Bioimpedance has no open real counterpart, so a light synthetic ΔZ drives the
 *     contact/movement indicators (clearly a simulated channel).
 *
 * MoniVitals is a research / educational tool, NOT a medical device.
 *
 * Async note: unlike iOS (which decodes the bundled JSON synchronously in init), the web
 * app must fetch the asset over HTTP. The recording is loaded lazily on first connect()
 * (or start()) via `await`; a `loaded` guard ensures the tick loop only begins emitting
 * once the samples are in memory, so the otherwise-synchronous source lifecycle is safe.
 */
import type { BiozPacket, EcgPacket, MetricsPacket } from '../ble/packets';
import { StreamBit } from '../ble/protocol';
import { US_PER_S } from '../dsp/constants';
import { BaseDataSource } from './DataSource';

const TICK_MS = 40;
const METRICS_MS = 500;
const ASSET_URL = '/bidmc_sample.json';

/** Shape of the bundled recording (public/bidmc_sample.json, from PhysioNet BIDMC). */
interface Recording {
  source: string;
  fs: number;
  refHR: number;
  refSpO2: number;
  spo2Ratio: number;
  ppgMean: number;
  ecg: number[];
  ppg: number[];
}

const PPG_DC = 120_000;
const PPG_GAIN = 100_000;

export class ReplaySource extends BaseDataSource {
  readonly isMock = true;
  clockOffsetUs: number | null = null;
  deviceName: string | null = 'MoniVitals Replay';

  /** Recorded reference values (for display as ground-truth comparison). */
  referenceHR = 0;
  referenceSpO2 = 0;
  recordingName = '';

  private rec: Recording | null = null;
  private loaded = false;
  private loadPromise: Promise<void> | null = null;
  private fs = 125;
  private n = 0;

  private emitted = 0; // total ECG/PPG samples emitted (monotonic)
  private running = false;
  private startPerfMs = 0;
  private seqEcg = 0;
  private seqPpg = 0;
  private seqBioz = 0;
  private batteryPct = 100;
  private timer: ReturnType<typeof setInterval> | null = null;
  private metricsTimer: ReturnType<typeof setInterval> | null = null;
  private statusTimer: ReturnType<typeof setInterval> | null = null;

  /** Fetch + decode the recording once. Safe to await concurrently. */
  async load(): Promise<void> {
    if (this.loaded) return;
    if (this.loadPromise) return this.loadPromise;
    this.loadPromise = (async () => {
      const res = await fetch(ASSET_URL);
      if (!res.ok) throw new Error(`bidmc_sample.json fetch failed: ${res.status}`);
      const rec = (await res.json()) as Recording;
      this.rec = rec;
      this.fs = rec.fs;
      this.n = rec.ecg.length;
      this.referenceHR = rec.refHR;
      this.referenceSpO2 = rec.refSpO2;
      this.recordingName = rec.source;
      this.deviceName = rec.source;
      this.loaded = true;
    })();
    return this.loadPromise;
  }

  async connect(): Promise<void> {
    this.setState('connecting');
    await this.load();
    await delay(100);
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

  async start(_streamMask: number): Promise<void> {
    // Guard: streaming begins only once the recording is loaded.
    if (!this.loaded) await this.load();
    this.emitted = 0;
    this.seqEcg = 0;
    this.seqPpg = 0;
    this.seqBioz = 0;
    this.startPerfMs = now();
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

  async setRate(): Promise<void> {
    // The recording has a fixed sample rate; rate changes are a no-op.
  }

  async syncClock(): Promise<void> {
    await delay(20);
    this.clockOffsetUs = Date.now() * 1000 - this.deviceUs(this.emitted);
  }

  async getInfo(): Promise<void> {
    this.getInfoSync();
  }

  // ---- internals ----

  private elapsedS(): number {
    return (now() - this.startPerfMs) / 1000;
  }

  private deviceUs(sampleIndex: number): number {
    return Math.round((sampleIndex * US_PER_S) / this.fs);
  }

  private tick(): void {
    if (!this.running || !this.rec) return;
    const elapsed = this.elapsedS();
    const target = Math.floor(elapsed * this.fs); // total samples that should exist by now
    if (target <= this.emitted) return;
    const count = target - this.emitted;
    const firstTus = this.deviceUs(this.emitted);
    const rec = this.rec;
    const n = this.n;

    const ecg = new Int32Array(count);
    const green = new Uint32Array(count);
    const red = new Uint32Array(count);
    const ir = new Uint32Array(count);
    const dz = new Int32Array(count);

    for (let i = 0; i < count; i++) {
      const s = this.emitted + i;
      const j = s % n; // loop the recording
      ecg[i] = Math.round(rec.ecg[j]);
      const ac = (rec.ppg[j] - rec.ppgMean) * PPG_GAIN; // real PPG AC
      green[i] = Math.max(0, Math.round(PPG_DC + ac));
      ir[i] = Math.max(0, Math.round(PPG_DC + ac)); // IR AC == green AC
      red[i] = Math.max(0, Math.round(PPG_DC + ac * rec.spo2Ratio)); // red AC scaled → SpO2 ref
      // Light synthetic bioimpedance ΔZ (pulsatile at the recorded HR) + tiny noise.
      const tSec = s / this.fs;
      dz[i] = Math.round(
        400 * Math.sin(2 * Math.PI * (rec.refHR / 60) * tSec) + 40 * Math.sin(tSec * 53.7),
      );
    }

    const ecgPacket: EcgPacket = {
      kind: 'ecg',
      seq: this.seqEcg,
      tUs: firstTus,
      sampleRateHz: this.fs,
      samples: ecg,
    };
    this.emitter.emit('ecg', ecgPacket);

    this.emitter.emit('ppg', {
      kind: 'ppg',
      seq: this.seqPpg,
      tUs: firstTus,
      sampleRateHz: this.fs,
      green,
      red,
      ir,
    });

    const biozPacket: BiozPacket = {
      kind: 'bioz',
      seq: this.seqBioz,
      tUs: firstTus,
      sampleRateHz: this.fs,
      z0Milliohm: 300_000,
      dz,
    };
    this.emitter.emit('bioz', biozPacket);

    this.seqEcg = (this.seqEcg + 1) & 0xffff;
    this.seqPpg = (this.seqPpg + 1) & 0xffff;
    this.seqBioz = (this.seqBioz + 1) & 0xffff;
    this.emitted = target;
  }

  private emitMetrics(): void {
    if (!this.running || !this.rec) return;
    // Firmware/reference metrics: the recording's own HR + SpO2 readings.
    const p: MetricsPacket = {
      kind: 'metrics',
      tUs: this.deviceUs(this.emitted),
      hrBpm: this.rec.refHR,
      spo2Pct: this.rec.refSpO2,
      contactQuality: 100,
      motion: 0,
      patUs: null,
      sbpMmHg: null,
      dbpMmHg: null,
      rpeak: false,
    };
    this.emitter.emit('metrics', p);
  }

  private getInfoSync(): void {
    this.emitter.emit('info', {
      kind: 'info',
      firmwareVersion: 'bidmc-replay',
      deviceId: 'bidmc00000001',
      capabilities: StreamBit.ecg | StreamBit.bioz | StreamBit.ppg,
    });
    this.emitter.emit('battery', this.batteryPct);
  }

  private emitStatus(): void {
    this.emitter.emit('battery', Math.round(this.batteryPct));
    this.emitter.emit('status', {
      kind: 'status',
      streamingMask: this.running ? StreamBit.ecg | StreamBit.bioz | StreamBit.ppg : 0,
      ecgRateCode: 1,
      biozRateCode: 1,
      ppgRateCode: 1,
      tUs: this.deviceUs(this.emitted),
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
