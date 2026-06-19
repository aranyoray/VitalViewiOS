/**
 * Live Web Bluetooth data source. Subscribes to the GATT stream characteristics,
 * parses notifications, extends device timestamps, tracks dropped packets, and
 * reconnects with exponential backoff. See docs/BLE_PROTOCOL.md.
 *
 * Web Bluetooth is unavailable in Safari / iOS — hence the native iOS app. Callers
 * should check `BleSource.isSupported()` and surface an explanation.
 */
import { parseBioz, parseControl, parseEcg, parseMetrics, parsePpg } from '../ble/parsers';
import {
  BATTERY_LEVEL_UUID,
  BATTERY_SERVICE_UUID,
  CHAR_UUID,
  codeFromRate,
  Opcode,
  SERVICE_UUID,
  StreamId,
  type StreamKind,
} from '../ble/protocol';
import { BaseDataSource } from './DataSource';
import { Timebase } from './timebase';

const BACKOFF_MS = [2000, 4000, 8000, 16000];

export class BleSource extends BaseDataSource {
  readonly isMock = false;
  clockOffsetUs: number | null = null;
  deviceName: string | null = null;

  private device: BluetoothDevice | null = null;
  private server: BluetoothRemoteGATTServer | null = null;
  private chars: Partial<Record<string, BluetoothRemoteGATTCharacteristic>> = {};
  private readonly tb = new Timebase();
  private wantConnected = false;
  private lastStreamMask = 0;
  private reconnectAttempt = 0;

  static isSupported(): boolean {
    return typeof navigator !== 'undefined' && !!navigator.bluetooth;
  }

  async connect(): Promise<void> {
    if (!BleSource.isSupported()) {
      this.setState('unsupported', { error: 'Web Bluetooth is not available in this browser.' });
      return;
    }
    this.setState('scanning');
    this.device = await navigator.bluetooth.requestDevice({
      filters: [{ services: [SERVICE_UUID] }],
      optionalServices: [BATTERY_SERVICE_UUID],
    });
    this.deviceName = this.device.name ?? 'VitalView';
    this.device.addEventListener('gattserverdisconnected', this.onDisconnected);
    this.wantConnected = true;
    await this.openGatt();
  }

  private async openGatt(): Promise<void> {
    if (!this.device?.gatt) throw new Error('No GATT');
    this.setState('connecting');
    this.server = await this.device.gatt.connect();
    const service = await this.server.getPrimaryService(SERVICE_UUID);

    this.chars.control = await service.getCharacteristic(CHAR_UUID.control);
    this.chars.ecg = await service.getCharacteristic(CHAR_UUID.ecg);
    this.chars.bioz = await service.getCharacteristic(CHAR_UUID.bioz);
    this.chars.ppg = await service.getCharacteristic(CHAR_UUID.ppg);
    this.chars.metrics = await service.getCharacteristic(CHAR_UUID.metrics);

    await this.subscribe('control', this.onControl);
    await this.subscribe('ecg', this.onEcg);
    await this.subscribe('bioz', this.onBioz);
    await this.subscribe('ppg', this.onPpg);
    await this.subscribe('metrics', this.onMetrics);
    await this.subscribeBattery(this.server);

    this.reconnectAttempt = 0;
    this.setState('connected');
    await this.syncClock();
    await this.getInfo();
    if (this.lastStreamMask) await this.start(this.lastStreamMask);
  }

  private async subscribe(
    key: keyof typeof CHAR_UUID,
    handler: (e: Event) => void,
  ): Promise<void> {
    const c = this.chars[key];
    if (!c) return;
    await c.startNotifications();
    c.addEventListener('characteristicvaluechanged', handler);
  }

  private async subscribeBattery(server: BluetoothRemoteGATTServer): Promise<void> {
    try {
      const svc = await server.getPrimaryService(BATTERY_SERVICE_UUID);
      const c = await svc.getCharacteristic(BATTERY_LEVEL_UUID);
      const read = await c.readValue();
      this.emitter.emit('battery', read.getUint8(0));
      await c.startNotifications();
      c.addEventListener('characteristicvaluechanged', (e) => {
        const v = (e.target as BluetoothRemoteGATTCharacteristic).value;
        if (v) this.emitter.emit('battery', v.getUint8(0));
      });
    } catch {
      /* battery service optional */
    }
  }

  async disconnect(): Promise<void> {
    this.wantConnected = false;
    try {
      await this.write(new Uint8Array([Opcode.STOP]));
    } catch {
      /* ignore */
    }
    this.device?.gatt?.disconnect();
    this.setState('disconnected');
  }

  async start(streamMask: number): Promise<void> {
    this.lastStreamMask = streamMask;
    this.tb.reset();
    await this.write(new Uint8Array([Opcode.START, streamMask]));
  }

  async stop(): Promise<void> {
    await this.write(new Uint8Array([Opcode.STOP]));
  }

  async setRate(stream: StreamKind, hz: number): Promise<void> {
    await this.write(new Uint8Array([Opcode.SET_RATE, StreamId[stream], codeFromRate(stream, hz)]));
  }

  async syncClock(): Promise<void> {
    await this.write(new Uint8Array([Opcode.SYNC_CLOCK]));
  }

  async getInfo(): Promise<void> {
    await this.write(new Uint8Array([Opcode.GET_INFO]));
  }

  private async write(bytes: Uint8Array): Promise<void> {
    const c = this.chars.control;
    if (!c) throw new Error('Control characteristic not ready');
    // Cast for the lib.dom BufferSource typing (typed-array generic quirk in TS ≥5.7).
    const buf = bytes as unknown as BufferSource;
    if (c.writeValueWithResponse) await c.writeValueWithResponse(buf);
    else await c.writeValue(buf);
  }

  // ---- notification handlers (bound for add/removeEventListener parity) ----

  private onEcg = (e: Event): void => {
    const v = (e.target as BluetoothRemoteGATTCharacteristic).value;
    if (!v) return;
    const p = parseEcg(v);
    this.emitter.emit('dropped', 'ecg', this.tb.trackers.ecg.update(p.seq));
    p.tUs = this.tb.extenders.ecg.extend(p.tUs);
    this.emitter.emit('ecg', p);
  };

  private onBioz = (e: Event): void => {
    const v = (e.target as BluetoothRemoteGATTCharacteristic).value;
    if (!v) return;
    const p = parseBioz(v);
    this.emitter.emit('dropped', 'bioz', this.tb.trackers.bioz.update(p.seq));
    p.tUs = this.tb.extenders.bioz.extend(p.tUs);
    this.emitter.emit('bioz', p);
  };

  private onPpg = (e: Event): void => {
    const v = (e.target as BluetoothRemoteGATTCharacteristic).value;
    if (!v) return;
    const p = parsePpg(v);
    this.emitter.emit('dropped', 'ppg', this.tb.trackers.ppg.update(p.seq));
    p.tUs = this.tb.extenders.ppg.extend(p.tUs);
    this.emitter.emit('ppg', p);
  };

  private onMetrics = (e: Event): void => {
    const v = (e.target as BluetoothRemoteGATTCharacteristic).value;
    if (!v) return;
    this.emitter.emit('metrics', parseMetrics(v));
  };

  private onControl = (e: Event): void => {
    const v = (e.target as BluetoothRemoteGATTCharacteristic).value;
    if (!v) return;
    const msg = parseControl(v);
    if (!msg) return;
    if (msg.kind === 'clock') {
      this.tb.setOffsetFromDevice(msg.tUs);
      this.clockOffsetUs = this.tb.offsetUs;
    } else if (msg.kind === 'status') {
      this.emitter.emit('status', msg);
      this.emitter.emit('battery', msg.batteryPct);
    } else if (msg.kind === 'info') {
      this.emitter.emit('info', msg);
    }
  };

  private onDisconnected = (): void => {
    this.chars = {};
    this.server = null;
    if (!this.wantConnected) return;
    void this.attemptReconnect();
  };

  private async attemptReconnect(): Promise<void> {
    this.setState('reconnecting');
    while (this.wantConnected) {
      const wait = BACKOFF_MS[Math.min(this.reconnectAttempt, BACKOFF_MS.length - 1)];
      this.reconnectAttempt++;
      await delay(wait);
      if (!this.wantConnected) return;
      try {
        await this.openGatt();
        return;
      } catch (err) {
        this.setState('reconnecting', { error: String(err) });
      }
    }
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
