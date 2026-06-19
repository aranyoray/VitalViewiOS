import { describe, expect, it } from 'vitest';
import { buildBundleFiles, csvEscape, type BundleData } from './csv';
import { crc32, zipStore } from './zip';

describe('csvEscape', () => {
  it('escapes commas, quotes and newlines; blanks for null', () => {
    expect(csvEscape('plain')).toBe('plain');
    expect(csvEscape(42)).toBe('42');
    expect(csvEscape(null)).toBe('');
    expect(csvEscape('a,b')).toBe('"a,b"');
    expect(csvEscape('say "hi"')).toBe('"say ""hi"""');
    expect(csvEscape('line1\nline2')).toBe('"line1\nline2"');
  });
});

describe('crc32 / zipStore', () => {
  it('crc32 matches the canonical check value', () => {
    expect(crc32(new TextEncoder().encode('123456789'))).toBe(0xcbf43926);
  });

  it('zipStore produces a valid local-header signature and EOCD', () => {
    const data = new TextEncoder().encode('hello');
    const zip = zipStore([{ name: 'a.txt', data }]);
    // Local file header signature PK\x03\x04
    expect([zip[0], zip[1], zip[2], zip[3]]).toEqual([0x50, 0x4b, 0x03, 0x04]);
    // End-of-central-directory signature appears near the end.
    const eocd = zip.subarray(zip.length - 22);
    expect([eocd[0], eocd[1], eocd[2], eocd[3]]).toEqual([0x50, 0x4b, 0x05, 0x06]);
  });
});

describe('buildBundleFiles', () => {
  const bundle: BundleData = {
    session: {
      id: 'abc12345',
      subjectCode: 'S01',
      label: 'rest',
      deviceId: 'dev',
      firmwareVersion: '1.0.0',
      startedAt: '2026-01-01T00:00:00.000Z',
      endedAt: '2026-01-01T00:01:00.000Z',
      notes: '',
      metricsSource: 'app',
      gating: { motionThresh: 4e6, contactThresh: 5e6, windowMs: 500 },
      calibrationSnapshot: null,
    },
    subject: { code: 'S01', ageBand: '18-25', notes: '', createdAt: '2026-01-01T00:00:00.000Z' },
    calibration: null,
    streams: {
      ecg: { t: Float64Array.from([0, 3906]), ecg: Int32Array.from([10, -20]) },
      bioz: { t: Float64Array.from([0]), z0: Int32Array.from([300000]), dz: Int32Array.from([5]) },
      ppg: { t: Float64Array.from([0]), green: Uint32Array.from([1000]), red: Uint32Array.from([1100]), ir: Uint32Array.from([1200]) },
    },
    metrics: [
      { sessionId: 'abc12345', tUs: 1000, hrBpm: 72, spo2Pct: 98, contactQuality: 90, motion: 3, patUs: 215000, sbpMmHg: null, dbpMmHg: null },
    ],
    annotations: [{ sessionId: 'abc12345', tUs: 2000, type: 'cuff_reading', sbp: 120, dbp: 80, text: 'arm' }],
  };

  it('writes fixed headers and forward-filled / blank cells correctly', () => {
    const files = buildBundleFiles(bundle);
    expect(files['ecg.csv'].split('\n')[0]).toBe('t_us,ecg');
    expect(files['ecg.csv'].split('\n')[1]).toBe('0,10');
    expect(files['bioz.csv'].split('\n')[0]).toBe('t_us,z0_milliohm,dz');
    expect(files['metrics.csv'].split('\n')[0]).toBe(
      't_us,hr_bpm,spo2_pct,contact_quality,motion,pat_ms,sbp_est,dbp_est',
    );
    // pat_ms = 215, sbp/dbp blank (uncalibrated)
    expect(files['metrics.csv'].split('\n')[1]).toBe('1000,72,98,90,3,215,,');
    expect(files['annotations.csv'].split('\n')[1]).toBe('2000,cuff_reading,120,80,arm');
    expect(JSON.parse(files['session_meta.json']).session.subjectCode).toBe('S01');
  });
});
