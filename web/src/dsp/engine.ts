/**
 * Ties the detectors together into a live metrics engine. Ingests decoded stream
 * packets (with extended device timestamps) and produces a metrics snapshot — the
 * app-side equivalent of the firmware Metrics packet, so algorithms can be iterated
 * without reflashing.
 */
import type { BiozPacket, EcgPacket, MetricsPacket, PpgPacket } from '../ble/packets';
import { US_PER_S } from './constants';
import { ContactMotionEstimator } from './bioz';
import { HeartRateEstimator } from './hr';
import { PatEstimator } from './pat';
import { PpgFootDetector } from './ppgFoot';
import { RPeakDetector } from './rpeak';
import { Spo2Estimator } from './spo2';
import { predictBp, type CalibCoeffs } from './calibration';

export interface MetricsSnapshot extends Omit<MetricsPacket, 'kind'> {}

export class MetricsEngine {
  private rpeak?: RPeakDetector;
  private foot?: PpgFootDetector;
  private contact?: ContactMotionEstimator;
  private spo2?: Spo2Estimator;
  private readonly pat = new PatEstimator();
  private readonly hr = new HeartRateEstimator();
  private ecgFs = 0;
  private ppgFs = 0;
  private biozFs = 0;
  private rpeakFlag = false;
  private calib: CalibCoeffs | null = null;
  private motionThresh?: number;

  /** Recent detected event times (µs), capped — for waveform markers. */
  readonly recentRPeaks: number[] = [];
  readonly recentFeet: number[] = [];

  setCalibration(fit: CalibCoeffs | null): void {
    this.calib = fit;
  }

  setMotionThresh(thresh: number): void {
    this.motionThresh = thresh;
    this.contact?.setMotionThresh(thresh);
  }

  ingestEcg(p: EcgPacket): void {
    if (!this.rpeak || this.ecgFs !== p.sampleRateHz) {
      this.rpeak = new RPeakDetector(p.sampleRateHz);
      this.ecgFs = p.sampleRateHz;
    }
    const dt = US_PER_S / p.sampleRateHz;
    for (let i = 0; i < p.samples.length; i++) {
      const t = p.tUs + Math.round(i * dt);
      const r = this.rpeak.process(p.samples[i], t);
      if (r != null) {
        this.hr.addRPeak(r);
        this.pat.addRPeak(r);
        this.rpeakFlag = true;
        pushCapped(this.recentRPeaks, r);
      }
    }
  }

  ingestBioz(p: BiozPacket): void {
    if (!this.contact || this.biozFs !== p.sampleRateHz) {
      this.contact = new ContactMotionEstimator(p.sampleRateHz, this.motionThresh);
      this.biozFs = p.sampleRateHz;
    }
    this.contact.pushZ0(p.z0Milliohm);
    for (let i = 0; i < p.dz.length; i++) this.contact.pushDz(p.dz[i]);
  }

  ingestPpg(p: PpgPacket): void {
    if (!this.foot || this.ppgFs !== p.sampleRateHz) {
      this.foot = new PpgFootDetector(p.sampleRateHz);
      this.spo2 = new Spo2Estimator(p.sampleRateHz);
      this.ppgFs = p.sampleRateHz;
    }
    const dt = US_PER_S / p.sampleRateHz;
    for (let i = 0; i < p.green.length; i++) {
      const t = p.tUs + Math.round(i * dt);
      const f = this.foot.process(p.green[i], t);
      if (f != null) {
        this.pat.addFoot(f);
        pushCapped(this.recentFeet, f);
      }
      this.spo2!.push(p.red[i], p.ir[i]);
    }
  }

  /** Produce a metrics snapshot at the given device timestamp. */
  snapshot(tUs: number): MetricsSnapshot {
    const patUs = this.pat.medianUs();
    let sbp: number | null = null;
    let dbp: number | null = null;
    if (patUs != null && this.calib) {
      const bp = predictBp(patUs, this.calib);
      sbp = Math.round(bp.sbp);
      dbp = Math.round(bp.dbp);
    }
    const snap: MetricsSnapshot = {
      tUs,
      hrBpm: this.hr.bpm(),
      spo2Pct: this.spo2?.estimate() ?? null,
      contactQuality: this.contact?.contactQuality() ?? 0,
      motion: this.contact?.motion() ?? 0,
      patUs,
      sbpMmHg: sbp,
      dbpMmHg: dbp,
      rpeak: this.rpeakFlag,
    };
    this.rpeakFlag = false;
    return snap;
  }

  reset(): void {
    this.rpeak = undefined;
    this.foot = undefined;
    this.contact = undefined;
    this.spo2 = undefined;
    this.pat.reset();
    this.hr.reset();
    this.ecgFs = this.ppgFs = this.biozFs = 0;
    this.rpeakFlag = false;
    this.recentRPeaks.length = 0;
    this.recentFeet.length = 0;
  }
}

function pushCapped(arr: number[], v: number, cap = 64): void {
  arr.push(v);
  if (arr.length > cap) arr.shift();
}
