/**
 * The single interface that the UI talks to. Both the live BLE source and the mock
 * source implement it, so every screen works with or without hardware (§8). Packets
 * delivered to consumers carry EXTENDED device timestamps (see timebase.ts).
 */
import type {
  BiozPacket,
  EcgPacket,
  InfoMessage,
  MetricsPacket,
  PpgPacket,
  StatusMessage,
} from '../ble/packets';
import type { StreamKind } from '../ble/protocol';
import { Emitter } from '../util/emitter';

export type ConnectionState =
  | 'disconnected'
  | 'unsupported'
  | 'scanning'
  | 'connecting'
  | 'connected'
  | 'reconnecting';

export interface DataSourceEvents {
  ecg: (p: EcgPacket) => void;
  bioz: (p: BiozPacket) => void;
  ppg: (p: PpgPacket) => void;
  /** Firmware-computed metrics (optional; the app computes its own in parallel). */
  metrics: (p: MetricsPacket) => void;
  status: (s: StatusMessage) => void;
  info: (i: InfoMessage) => void;
  battery: (pct: number) => void;
  /** Newly dropped packet count for a stream (from seq gaps). */
  dropped: (stream: StreamKind, count: number) => void;
  connection: (state: ConnectionState, detail?: { error?: string }) => void;
}

export interface DataSource {
  readonly isMock: boolean;
  readonly state: ConnectionState;
  /** offset = hostNowUs − deviceTus, or null before SYNC_CLOCK. */
  readonly clockOffsetUs: number | null;
  readonly deviceName: string | null;

  connect(): Promise<void>;
  disconnect(): Promise<void>;
  start(streamMask: number): Promise<void>;
  stop(): Promise<void>;
  setRate(stream: StreamKind, hz: number): Promise<void>;
  syncClock(): Promise<void>;
  getInfo(): Promise<void>;

  on<K extends keyof DataSourceEvents>(event: K, cb: DataSourceEvents[K]): () => void;
}

/** Shared base providing the emitter plumbing. */
export abstract class BaseDataSource implements DataSource {
  protected readonly emitter = new Emitter<DataSourceEvents>();
  protected _state: ConnectionState = 'disconnected';

  abstract readonly isMock: boolean;
  abstract clockOffsetUs: number | null;
  abstract deviceName: string | null;

  get state(): ConnectionState {
    return this._state;
  }

  protected setState(state: ConnectionState, detail?: { error?: string }): void {
    this._state = state;
    this.emitter.emit('connection', state, detail);
  }

  on<K extends keyof DataSourceEvents>(event: K, cb: DataSourceEvents[K]): () => void {
    return this.emitter.on(event, cb);
  }

  abstract connect(): Promise<void>;
  abstract disconnect(): Promise<void>;
  abstract start(streamMask: number): Promise<void>;
  abstract stop(): Promise<void>;
  abstract setRate(stream: StreamKind, hz: number): Promise<void>;
  abstract syncClock(): Promise<void>;
  abstract getInfo(): Promise<void>;
}
