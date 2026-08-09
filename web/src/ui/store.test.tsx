import 'fake-indexeddb/auto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useAppStore } from '../store/appStore';

// Runs under jsdom (src/ui/** glob) so localStorage + a stubbed fetch are available
// from src/test/setup.ts. These tests exercise the store's load-failure resilience,
// which the UI surfaces as a graceful error card instead of an indefinite spinner.

const realFetch = globalThis.fetch;

describe('store: recording load failure is graceful', () => {
  beforeEach(async () => {
    // Reset any source a prior test may have connected.
    await useAppStore.getState().disconnect();
  });
  afterEach(() => {
    globalThis.fetch = realFetch;
    vi.restoreAllMocks();
  });

  it('surfaces a loadError (not a hang) when the recording fetch fails', async () => {
    globalThis.fetch = (async () =>
      new Response('nope', { status: 500 })) as typeof fetch;

    await useAppStore.getState().autoStart();

    const st = useAppStore.getState();
    expect(st.loadError).toBeTruthy();
    expect(st.streaming).toBe(false);
    expect(st.source).toBeNull();
  });

  it('surfaces a loadError when the recording fetch rejects (offline)', async () => {
    globalThis.fetch = (async () => {
      throw new TypeError('Failed to fetch');
    }) as typeof fetch;

    await useAppStore.getState().autoStart();

    expect(useAppStore.getState().loadError).toContain('fetch');
    expect(useAppStore.getState().streaming).toBe(false);
  });

  it('recovers on retry once the asset is reachable again', async () => {
    globalThis.fetch = (async () => {
      throw new TypeError('Failed to fetch');
    }) as typeof fetch;
    await useAppStore.getState().autoStart();
    expect(useAppStore.getState().loadError).toBeTruthy();

    // Restore the working (stubbed) fetch and retry.
    globalThis.fetch = realFetch;
    await useAppStore.getState().retryAutoStart();

    const st = useAppStore.getState();
    expect(st.loadError).toBeNull();
    expect(st.streaming).toBe(true);
    expect(st.source).not.toBeNull();
    await useAppStore.getState().disconnect();
  });
});

describe('store: corrupt settings JSON resilience', () => {
  it('falls back to defaults when localStorage holds non-object JSON', () => {
    // loadSettings ignores arrays/primitives; verify updateSettings still round-trips.
    localStorage.setItem('monivitals.settings', '"not-an-object"');
    // A fresh update should overwrite with a valid object and not throw.
    expect(() => useAppStore.getState().updateSettings({ theme: 'light' })).not.toThrow();
    const raw = localStorage.getItem('monivitals.settings');
    expect(raw && JSON.parse(raw).theme).toBe('light');
  });
});
