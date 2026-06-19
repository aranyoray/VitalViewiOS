/**
 * BLE GATT protocol constants — the single source of truth is docs/BLE_PROTOCOL.md.
 * Firmware, the web app, and the iOS app must all agree with that document.
 * All multi-byte fields are little-endian.
 */

/** Base 128-bit UUID; characteristic index is substituted into `f001000X-...`. */
export const SERVICE_UUID = 'f0010000-1a2b-4c3d-8e5f-000000000000';

export const CHAR_UUID = {
  control: 'f0010001-1a2b-4c3d-8e5f-000000000000',
  ecg: 'f0010002-1a2b-4c3d-8e5f-000000000000',
  bioz: 'f0010003-1a2b-4c3d-8e5f-000000000000',
  ppg: 'f0010004-1a2b-4c3d-8e5f-000000000000',
  metrics: 'f0010005-1a2b-4c3d-8e5f-000000000000',
} as const;

/** Standard Battery Service. */
export const BATTERY_SERVICE_UUID = 0x180f;
export const BATTERY_LEVEL_UUID = 0x2a19;

/** Control characteristic opcodes (first payload byte on write). */
export const Opcode = {
  START: 0x01,
  STOP: 0x02,
  SET_RATE: 0x03,
  SYNC_CLOCK: 0x04,
  GET_INFO: 0x05,
} as const;

/** Status notification message types (first payload byte). */
export const StatusMsg = {
  STATUS: 0x10,
  INFO: 0x11,
  CLOCK: 0x12,
} as const;

export type StreamKind = 'ecg' | 'bioz' | 'ppg';

/** Stream ids and START bitmask bits. */
export const StreamId: Record<StreamKind, number> = { ecg: 0, bioz: 1, ppg: 2 };
export const StreamBit: Record<StreamKind, number> = { ecg: 0x01, bioz: 0x02, ppg: 0x04 };

export const ALL_STREAMS_MASK = StreamBit.ecg | StreamBit.bioz | StreamBit.ppg;

/** Rate-code → Hz tables, per docs/BLE_PROTOCOL.md. */
export const RATE_CODES: Record<StreamKind, number[]> = {
  ecg: [128, 256, 512],
  bioz: [32, 64, 128],
  ppg: [50, 100, 200, 400],
};

export const DEFAULT_RATE_HZ: Record<StreamKind, number> = { ecg: 256, bioz: 64, ppg: 100 };

/** Default samples-per-packet used by the firmware / mock encoder (parsers derive K). */
export const DEFAULT_K: Record<StreamKind, number> = { ecg: 20, bioz: 16, ppg: 12 };

/** Error-flag bits in the STATUS message. */
export const ErrorFlag = {
  LEAD_OFF: 0x01,
  PPG_SATURATION: 0x02,
  BUFFER_OVERFLOW: 0x04,
} as const;

/** Invalid sentinels used in the metrics packet. */
export const Sentinel = {
  U16: 0xffff,
  I32_MIN: -2147483648,
  I16_MIN: -32768,
} as const;

/** Resolve a rate code to Hz, falling back to the stream default. */
export function rateFromCode(stream: StreamKind, code: number): number {
  return RATE_CODES[stream][code] ?? DEFAULT_RATE_HZ[stream];
}

/** Resolve a Hz value to its rate code (nearest match), for SET_RATE. */
export function codeFromRate(stream: StreamKind, hz: number): number {
  const codes = RATE_CODES[stream];
  let best = 0;
  let bestErr = Infinity;
  for (let i = 0; i < codes.length; i++) {
    const err = Math.abs(codes[i] - hz);
    if (err < bestErr) {
      bestErr = err;
      best = i;
    }
  }
  return best;
}
