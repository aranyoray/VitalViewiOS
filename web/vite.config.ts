/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    // DSP/model/source unit tests run headless under Node; the React component
    // integration test (src/ui/**) needs a DOM, so it runs under jsdom.
    environment: 'node',
    environmentMatchGlobs: [['src/ui/**', 'jsdom']],
    // Provide browser globals jsdom omits (localStorage, matchMedia) for jsdom tests.
    setupFiles: ['src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
