/**
 * Non-reactive live runtime: waveform ring buffers and the app-side MetricsEngine.
 * These are mutated at full sample rate by the store's packet handlers and read by
 * the canvases directly, keeping high-rate data out of React state.
 */
import { MetricsEngine } from '../dsp/engine';
import { WaveBuffer } from './ringBuffer';

export const buffers = {
  ecg: new WaveBuffer(4096),
  ppgGreen: new WaveBuffer(8192),
  ppgRed: new WaveBuffer(8192),
  ppgIr: new WaveBuffer(8192),
  biozDz: new WaveBuffer(2048),
  z0: new WaveBuffer(1024),
};

export const engine = new MetricsEngine();

export function resetRuntime(): void {
  for (const b of Object.values(buffers)) b.clear();
  engine.reset();
}
