/** Typed representations of the decoded BLE stream packets. */

export interface EcgPacket {
  kind: 'ecg';
  seq: number;
  /** Device timestamp (µs) of the FIRST sample in the packet. */
  tUs: number;
  sampleRateHz: number;
  /** Signed ADC counts. */
  samples: Int32Array;
}

export interface BiozPacket {
  kind: 'bioz';
  seq: number;
  tUs: number;
  sampleRateHz: number;
  /** Baseline magnitude (milliohm), once per packet — contact quality. */
  z0Milliohm: number;
  /** Pulsatile delta-Z samples (ADC counts). */
  dz: Int32Array;
}

export interface PpgPacket {
  kind: 'ppg';
  seq: number;
  tUs: number;
  sampleRateHz: number;
  /** Interleaved green/red/ir (18-bit data right-justified). */
  green: Uint32Array;
  red: Uint32Array;
  ir: Uint32Array;
}

export interface MetricsPacket {
  kind: 'metrics';
  tUs: number;
  /** beats/min, or null if invalid. */
  hrBpm: number | null;
  /** percent (estimate), or null if invalid. */
  spo2Pct: number | null;
  contactQuality: number; // 0..100
  motion: number; // 0..255
  /** Pulse arrival time in microseconds, or null if invalid. */
  patUs: number | null;
  sbpMmHg: number | null;
  dbpMmHg: number | null;
  rpeak: boolean;
}

export type StreamPacket = EcgPacket | BiozPacket | PpgPacket;

/** Decoded STATUS / INFO / CLOCK messages from the control characteristic. */
export interface StatusMessage {
  kind: 'status';
  streamingMask: number;
  ecgRateCode: number;
  biozRateCode: number;
  ppgRateCode: number;
  tUs: number;
  batteryPct: number;
  errorFlags: number;
}

export interface InfoMessage {
  kind: 'info';
  firmwareVersion: string; // "major.minor.patch"
  deviceId: string; // hex
  capabilities: number;
}

export interface ClockMessage {
  kind: 'clock';
  tUs: number;
}

export type ControlMessage = StatusMessage | InfoMessage | ClockMessage;
