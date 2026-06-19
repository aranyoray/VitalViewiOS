/**
 * Device-clock handling. `t_us` is a uint32 microsecond counter that wraps every
 * ≈71.6 min; the extender turns it into a monotonic 64-bit-safe value per stream.
 * See docs/BLE_PROTOCOL.md#clock-synchronization.
 */
import type { StreamKind } from '../ble/protocol';

const WRAP = 0x1_0000_0000; // 2^32

/** Extends a wrapping uint32 µs counter to a monotonically increasing value. */
export class TimebaseExtender {
  private epoch = 0;
  private lastRaw: number | null = null;

  extend(raw: number): number {
    if (this.lastRaw != null && raw < this.lastRaw && this.lastRaw - raw > WRAP / 2) {
      this.epoch += 1; // a genuine wrap (large backward jump), not jitter
    }
    this.lastRaw = raw;
    return this.epoch * WRAP + raw;
  }

  reset(): void {
    this.epoch = 0;
    this.lastRaw = null;
  }
}

/** Per-stream sequence tracking to count dropped packets (seq is uint16). */
export class SeqTracker {
  private last: number | null = null;
  dropped = 0;

  /** Update with a new packet seq; returns the number of packets dropped before it. */
  update(seq: number): number {
    if (this.last == null) {
      this.last = seq;
      return 0;
    }
    const gap = (seq - this.last - 1 + 0x10000) % 0x10000;
    this.last = seq;
    this.dropped += gap;
    return gap;
  }

  reset(): void {
    this.last = null;
    this.dropped = 0;
  }
}

/** Holds the per-stream extenders + trackers and the host↔device clock offset. */
export class Timebase {
  readonly extenders: Record<StreamKind, TimebaseExtender> = {
    ecg: new TimebaseExtender(),
    bioz: new TimebaseExtender(),
    ppg: new TimebaseExtender(),
  };
  readonly trackers: Record<StreamKind, SeqTracker> = {
    ecg: new SeqTracker(),
    bioz: new SeqTracker(),
    ppg: new SeqTracker(),
  };
  /** offset = hostNowUs − deviceTus, set on SYNC_CLOCK. */
  offsetUs: number | null = null;

  setOffsetFromDevice(deviceTus: number): void {
    this.offsetUs = Date.now() * 1000 - deviceTus;
  }

  reset(): void {
    for (const k of ['ecg', 'bioz', 'ppg'] as StreamKind[]) {
      this.extenders[k].reset();
      this.trackers[k].reset();
    }
    this.offsetUs = null;
  }
}
