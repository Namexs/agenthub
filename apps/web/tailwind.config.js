// AGENTHUB theme comes from the shared preset (packages/config/tailwind/preset.js).
// Do NOT redefine colors here — extend the preset so Phase 2 builds on one theme.
/** @type {import('tailwindcss').Config} */
module.exports = {
  presets: [require('@agenthub/config/tailwind/preset')],
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './hooks/**/*.{js,ts,jsx,tsx,mdx}',
    './lib/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        // Space Grotesk is loaded via next/font in app/layout.tsx
        // (CSS variable --font-display on <html>). Display face for
        // headings, wordmark, and large numerals.
        display: [
          'var(--font-display)',
          'var(--font-inter)',
          'ui-sans-serif',
          'system-ui',
          'sans-serif',
        ],
        // IBM Plex Mono via next/font (--font-plex-mono). Used for
        // eyebrows, labels, and on-chain values (addresses, hashes).
        mono: [
          'var(--font-plex-mono)',
          'ui-monospace',
          'SFMono-Regular',
          'Menlo',
          'monospace',
        ],
      },
    },
  },
  plugins: [],
};
