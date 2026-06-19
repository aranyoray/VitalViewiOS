import { describe, expect, it } from 'vitest';
import { SeqTracker, TimebaseExtender } from './timebase';

describe('TimebaseExtender', () => {
  it('passes through monotonic values', () => {
    const ext = new TimebaseExtender();
    expect(ext.extend(100)).toBe(100);
    expect(ext.extend(200)).toBe(200);
  });

  it('extends across a uint32 wrap', () => {
    const ext = new TimebaseExtender();
    const nearMax = 0xfffffff0;
    expect(ext.extend(nearMax)).toBe(nearMax);
    // wraps to a small value ⇒ should add 2^32
    expect(ext.extend(0x10)).toBe(0x1_0000_0000 + 0x10);
  });
});

describe('SeqTracker', () => {
  it('counts dropped packets and handles the uint16 wrap', () => {
    const t = new SeqTracker();
    expect(t.update(10)).toBe(0); // first
    expect(t.update(11)).toBe(0); // contiguous
    expect(t.update(14)).toBe(2); // dropped 12,13
    expect(t.dropped).toBe(2);
    t.update(65535);
    expect(t.update(1)).toBe(1); // wrapped 65535 -> 0(dropped) -> 1
  });
});
