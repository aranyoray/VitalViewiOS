// @vitest-environment jsdom
import 'fake-indexeddb/auto';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import App from '../App';

beforeAll(() => {
  // jsdom lacks these; stub so the app boots headless.
  if (!window.matchMedia) {
    window.matchMedia = (q: string) =>
      ({ matches: false, media: q, onchange: null, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {}, dispatchEvent: () => false }) as MediaQueryList;
  }
  HTMLCanvasElement.prototype.getContext = (() => null) as unknown as HTMLCanvasElement['getContext'];
  localStorage.clear();
});

afterEach(cleanup);

describe('App integration (mock mode)', () => {
  it('shows the unavoidable disclaimer + consent gate on first run', () => {
    render(<App />);
    expect(screen.getByText(/research \/ educational tool, not a medical device/i)).toBeTruthy();
    // The persistent "Not a medical device" chip is always present in the top bar.
    expect(screen.getByText('Not a medical device')).toBeTruthy();
  });

  it('passes onboarding and connects the mock device end-to-end', async () => {
    render(<App />);
    fireEvent.click(screen.getByText(/I understand/i));
    fireEvent.click(screen.getByText(/I agree/i));

    // Onboarding dismissed → Connect screen visible.
    fireEvent.click(screen.getByText('Connect mock device'));

    // Mock connects after a short delay; "connected" should appear.
    const connected = await screen.findAllByText('connected', undefined, { timeout: 2000 });
    expect(connected.length).toBeGreaterThan(0);

    // Tidy up timers started by the mock source.
    fireEvent.click(screen.getByText('Disconnect'));
  });
});
