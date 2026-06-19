/**
 * Typed-packet → binary encoders. Used by the mock source to emit firmware-identical
 * byte payloads and by round-trip parser tests. Little-endian throughout.
 */
import { StatusMsg } from './protocol';
import type {
  BiozPacket,
  EcgPacket,
  InfoMessage,
  MetricsPacket,
  PpgPacket,
  StatusMessage,
} from './packets';
import { Sentinel } from './protocol';

const LE = true;

export function encodeEcg(p: EcgPacket): DataView {
  const view = new DataView(new ArrayBuffer(8 + p.samples.length * 4));
  view.setUint16(0, p.seq & 0xffff, LE);
  view.setUint32(2, p.tUs >>> 0, LE);
  view.setUint16(6, p.sampleRateHz, LE);
  for (let i = 0; i < p.samples.length; i++) view.setInt32(8 + i * 4, p.samples[i], LE);
  return view;
}

export function encodeBioz(p: BiozPacket): DataView {
  const view = new DataView(new ArrayBuffer(12 + p.dz.length * 4));
  view.setUint16(0, p.seq & 0xffff, LE);
  view.setUint32(2, p.tUs >>> 0, LE);
  view.setUint16(6, p.sampleRateHz, LE);
  view.setInt32(8, p.z0Milliohm, LE);
  for (let i = 0; i < p.dz.length; i++) view.setInt32(12 + i * 4, p.dz[i], LE);
  return view;
}

export function encodePpg(p: PpgPacket): DataView {
  const k = p.green.length;
  const view = new DataView(new ArrayBuffer(8 + k * 12));
  view.setUint16(0, p.seq & 0xffff, LE);
  view.setUint32(2, p.tUs >>> 0, LE);
  view.setUint16(6, p.sampleRateHz, LE);
  for (let i = 0; i < k; i++) {
    const o = 8 + i * 12;
    view.setUint32(o, p.green[i] >>> 0, LE);
    view.setUint32(o + 4, p.red[i] >>> 0, LE);
    view.setUint32(o + 8, p.ir[i] >>> 0, LE);
  }
  return view;
}

export function encodeMetrics(p: MetricsPacket): DataView {
  const view = new DataView(new ArrayBuffer(20));
  view.setUint32(0, p.tUs >>> 0, LE);
  view.setUint16(4, p.hrBpm == null ? Sentinel.U16 : Math.round(p.hrBpm * 10), LE);
  view.setUint16(6, p.spo2Pct == null ? Sentinel.U16 : Math.round(p.spo2Pct * 10), LE);
  view.setUint8(8, p.contactQuality & 0xff);
  view.setUint8(9, p.motion & 0xff);
  view.setInt32(10, p.patUs == null ? Sentinel.I32_MIN : Math.round(p.patUs), LE);
  view.setInt16(14, p.sbpMmHg == null ? Sentinel.I16_MIN : Math.round(p.sbpMmHg), LE);
  view.setInt16(16, p.dbpMmHg == null ? Sentinel.I16_MIN : Math.round(p.dbpMmHg), LE);
  view.setUint16(18, p.rpeak ? 0x01 : 0x00, LE);
  return view;
}

export function encodeStatus(m: StatusMessage): DataView {
  const view = new DataView(new ArrayBuffer(11));
  view.setUint8(0, StatusMsg.STATUS);
  view.setUint8(1, m.streamingMask);
  view.setUint8(2, m.ecgRateCode);
  view.setUint8(3, m.biozRateCode);
  view.setUint8(4, m.ppgRateCode);
  view.setUint32(5, m.tUs >>> 0, LE);
  view.setUint8(9, m.batteryPct);
  view.setUint8(10, m.errorFlags);
  return view;
}

export function encodeInfo(m: InfoMessage): DataView {
  const view = new DataView(new ArrayBuffer(12));
  view.setUint8(0, StatusMsg.INFO);
  const parts = m.firmwareVersion.split('.').map((n) => parseInt(n, 10) || 0);
  view.setUint8(1, parts[0] ?? 0);
  view.setUint8(2, parts[1] ?? 0);
  view.setUint8(3, parts[2] ?? 0);
  for (let i = 0; i < 6; i++) {
    const byte = parseInt(m.deviceId.slice(i * 2, i * 2 + 2), 16) || 0;
    view.setUint8(4 + i, byte);
  }
  view.setUint16(10, m.capabilities, LE);
  return view;
}
