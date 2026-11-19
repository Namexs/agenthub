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
  theme: { extend: {} },
  plugins: [],
};
