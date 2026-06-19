import { describe, expect, it } from 'vitest';
import { clamp, mapRange, mean, median, RollingMedian, stddev, variance } from './rollingStats';

describe('rollingStats', () => {
  it('median handles odd and even lengths without mutating input', () => {
    const a = [3, 1, 2];
    expect(median(a)).toBe(2);
    expect(a).toEqual([3, 1, 2]); // unchanged
    expect(median([4, 1, 3, 2])).toBe(2.5);
  });

  it('mean and variance/stddev', () => {
    expect(mean([2, 4, 6])).toBe(4);
    expect(variance([2, 4, 6])).toBeCloseTo(8 / 3, 6);
    expect(stddev([2, 4, 6])).toBeCloseTo(Math.sqrt(8 / 3), 6);
  });

  it('clamp and mapRange', () => {
    expect(clamp(5, 0, 3)).toBe(3);
    expect(clamp(-1, 0, 3)).toBe(0);
    expect(mapRange(5, 0, 10, 0, 100)).toBe(50);
    expect(mapRange(0, 0, 0, 7, 9)).toBe(7); // degenerate input range
  });

  it('RollingMedian keeps a fixed capacity', () => {
    const rm = new RollingMedian(3);
    rm.push(10);
    rm.push(20);
    rm.push(30);
    rm.push(40); // evicts 10
    expect(rm.count).toBe(3);
    expect(rm.value()).toBe(30); // median of [20,30,40]
  });
});
