/**
 * Binary → typed-packet parsers. Little-endian throughout. `K` (samples-per-packet)
 * is derived from the payload length so the firmware may batch any count that fits.
 * See docs/BLE_PROTOCOL.md.
 */
import { Sentinel, StatusMsg } from './protocol';
import type {
  BiozPacket,
  ClockMessage,
  ControlMessage,
  EcgPacket,
  InfoMessage,
  MetricsPacket,
  PpgPacket,
  StatusMessage,
} from './packets';

const LE = true;

export function parseEcg(view: DataView): EcgPacket {
  const seq = view.getUint16(0, LE);
  const tUs = view.getUint32(2, LE);
  const sampleRateHz = view.getUint16(6, LE);
  const k = Math.max(0, (view.byteLength - 8) >> 2);
  const samples = new Int32Array(k);
  for (let i = 0; i < k; i++) samples[i] = view.getInt32(8 + i * 4, LE);
  return { kind: 'ecg', seq, tUs, sampleRateHz, samples };
}

export function parseBioz(view: DataView): BiozPacket {
  const seq = view.getUint16(0, LE);
  const tUs = view.getUint32(2, LE);
  const sampleRateHz = view.getUint16(6, LE);
  const z0Milliohm = view.getInt32(8, LE);
  const k = Math.max(0, (view.byteLength - 12) >> 2);
  const dz = new Int32Array(k);
  for (let i = 0; i < k; i++) dz[i] = view.getInt32(12 + i * 4, LE);
  return { kind: 'bioz', seq, tUs, sampleRateHz, z0Milliohm, dz };
}

export function parsePpg(view: DataView): PpgPacket {
  const seq = view.getUint16(0, LE);
  const tUs = view.getUint32(2, LE);
  const sampleRateHz = view.getUint16(6, LE);
  const k = Math.max(0, Math.floor((view.byteLength - 8) / 12));
  const green = new Uint32Array(k);
  const red = new Uint32Array(k);
  const ir = new Uint32Array(k);
  for (let i = 0; i < k; i++) {
    const o = 8 + i * 12;
    green[i] = view.getUint32(o, LE);
    red[i] = view.getUint32(o + 4, LE);
    ir[i] = view.getUint32(o + 8, LE);
  }
  return { kind: 'ppg', seq, tUs, sampleRateHz, green, red, ir };
}

export function parseMetrics(view: DataView): MetricsPacket {
  const tUs = view.getUint32(0, LE);
  const hrRaw = view.getUint16(4, LE);
  const spo2Raw = view.getUint16(6, LE);
  const contactQuality = view.getUint8(8);
  const motion = view.getUint8(9);
  const patRaw = view.getInt32(10, LE);
  const sbpRaw = view.getInt16(14, LE);
  const dbpRaw = view.getInt16(16, LE);
  const rpeakFlags = view.getUint16(18, LE);
  return {
    kind: 'metrics',
    tUs,
    hrBpm: hrRaw === Sentinel.U16 ? null : hrRaw / 10,
    spo2Pct: spo2Raw === Sentinel.U16 ? null : spo2Raw / 10,
    contactQuality,
    motion,
    patUs: patRaw === Sentinel.I32_MIN ? null : patRaw,
    sbpMmHg: sbpRaw === Sentinel.I16_MIN ? null : sbpRaw,
    dbpMmHg: dbpRaw === Sentinel.I16_MIN ? null : dbpRaw,
    rpeak: (rpeakFlags & 0x01) !== 0,
  };
}

export function parseControl(view: DataView): ControlMessage | null {
  if (view.byteLength < 1) return null;
  const msgType = view.getUint8(0);
  switch (msgType) {
    case StatusMsg.STATUS: {
      const m: StatusMessage = {
        kind: 'status',
        streamingMask: view.getUint8(1),
        ecgRateCode: view.getUint8(2),
        biozRateCode: view.getUint8(3),
        ppgRateCode: view.getUint8(4),
        tUs: view.getUint32(5, LE),
        batteryPct: view.getUint8(9),
        errorFlags: view.getUint8(10),
      };
      return m;
    }
    case StatusMsg.INFO: {
      const fw = `${view.getUint8(1)}.${view.getUint8(2)}.${view.getUint8(3)}`;
      let id = '';
      for (let i = 0; i < 6; i++) id += view.getUint8(4 + i).toString(16).padStart(2, '0');
      const m: InfoMessage = {
        kind: 'info',
        firmwareVersion: fw,
        deviceId: id,
        capabilities: view.getUint16(10, LE),
      };
      return m;
    }
    case StatusMsg.CLOCK: {
      const m: ClockMessage = { kind: 'clock', tUs: view.getUint32(1, LE) };
      return m;
    }
    default:
      return null;
  }
}
