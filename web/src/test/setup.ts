/**
 * Vitest setup: polyfills the browser globals that jsdom omits so the React
 * integration test can boot the app headless. Runs per test file in that file's
 * environment, so everything is guarded (Node-env unit tests have no `window`).
 */

// --- localStorage ---------------------------------------------------------
// jsdom does not always expose a working localStorage (depends on URL/version),
// and the app reads/writes settings at import time. Provide an in-memory shim.
function installLocalStorage(target: typeof globalThis): void {
  const hasWorking =
    typeof (target as { localStorage?: Storage }).localStorage !== 'undefined' &&
    typeof (target as { localStorage?: Storage }).localStorage?.clear === 'function';
  if (hasWorking) return;

  const store = new Map<string, string>();
  const shim: Storage = {
    get length() {
      return store.size;
    },
    clear() {
      store.clear();
    },
    getItem(key: string) {
      return store.has(key) ? (store.get(key) as string) : null;
    },
    key(index: number) {
      return Array.from(store.keys())[index] ?? null;
    },
    removeItem(key: string) {
      store.delete(key);
    },
    setItem(key: string, value: string) {
      store.set(key, String(value));
    },
  };

  Object.defineProperty(target, 'localStorage', {
    configurable: true,
    value: shim,
  });
}

// --- matchMedia -----------------------------------------------------------
function installMatchMedia(target: Window & typeof globalThis): void {
  if (typeof target.matchMedia === 'function') return;
  target.matchMedia = (query: string) =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener() {},
      removeEventListener() {},
      addListener() {},
      removeListener() {},
      dispatchEvent: () => false,
    }) as MediaQueryList;
}

// --- fetch (bundled public/ asset) ---------------------------------------
// The ReplaySource fetches /bidmc_sample.json at runtime; jsdom/undici cannot
// resolve a root-relative URL with no server. Serve the one known asset from a
// static import of the same file so the replay path runs end-to-end under test.
import bidmcSample from '../../public/bidmc_sample.json';

const PUBLIC_ASSETS: Record<string, unknown> = {
  '/bidmc_sample.json': bidmcSample,
};

function installAssetFetch(target: typeof globalThis): void {
  const realFetch = target.fetch?.bind(target);
  target.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (typeof url === 'string' && url in PUBLIC_ASSETS) {
      return new Response(JSON.stringify(PUBLIC_ASSETS[url]), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }
    if (realFetch) return realFetch(input as RequestInfo, init);
    throw new Error(`Unstubbed fetch in test: ${String(url)}`);
  }) as typeof fetch;
}

if (typeof window !== 'undefined') {
  installLocalStorage(window as unknown as typeof globalThis);
  installMatchMedia(window as Window & typeof globalThis);
  installAssetFetch(globalThis);
}
