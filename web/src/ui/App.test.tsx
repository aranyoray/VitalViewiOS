import 'fake-indexeddb/auto';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import App from '../App';

// localStorage + matchMedia are polyfilled in src/test/setup.ts (jsdom env
// is selected for src/ui/** via environmentMatchGlobs in vite.config.ts).
beforeAll(() => {
  HTMLCanvasElement.prototype.getContext = (() => null) as unknown as HTMLCanvasElement['getContext'];
  localStorage.clear();
});

afterEach(cleanup);

describe('App integration', () => {
  it('shows the unavoidable disclaimer + consent gate on first run', () => {
    render(<App />);
    expect(screen.getByText(/research \/ educational tool, not a medical device/i)).toBeTruthy();
    // The persistent "Not a medical device" chip is always present in the top bar.
    expect(screen.getByText('Not a medical device')).toBeTruthy();
  });

  it('auto-connects the replay source and streams end-to-end', async () => {
    render(<App />);
    fireEvent.click(screen.getByText(/I understand/i));
    fireEvent.click(screen.getByText(/I agree/i));

    // No Connect screen: the app auto-starts the replay source on mount.
    // The "Live" pill should appear in the top bar once streaming begins.
    const live = await screen.findAllByText('Live', undefined, { timeout: 2000 });
    expect(live.length).toBeGreaterThan(0);
  });
});
