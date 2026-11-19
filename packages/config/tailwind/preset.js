// AGENTHUB design tokens — single source of truth for the theme.
// Theme: dark navy background, cyan + electric blue accents, glassmorphism,
// clean typography, mobile-first. See docs/ARCHITECTURE.md ("Design system").
//
// Consumed by apps/web/tailwind.config.js via `presets`. Keep this file plain
// JS (no TS) so Tailwind can load it without a compile step.

/** @type {import('tailwindcss').Config} */
module.exports = {
  theme: {
    extend: {
      colors: {
        // Dark navy scale (backgrounds / surfaces)
        navy: {
          950: '#050816', // page background
          900: '#0a0f24', // section background
          850: '#0d1531', // card background (deep)
          800: '#111c3f', // card background
          700: '#1a2a55', // raised surface
          600: '#24386e', // borders (strong)
          500: '#2f4a8f',
        },
        // Cyan accent (primary actions, highlights)
        agent: {
          300: '#67e8f9',
          400: '#22d3ee',
          500: '#06b6d4',
          600: '#0891b2',
        },
        // Electric blue accent (secondary, gradients)
        electric: {
          300: '#93c5fd',
          400: '#60a5fa',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
        },
        // Text
        ink: {
          100: '#f1f5f9',
          200: '#e2e8f0',
          300: '#cbd5e1',
          400: '#94a3b8',
          500: '#64748b',
        },
      },
      fontFamily: {
        // Inter is loaded via next/font in apps/web (see app/layout.tsx).
        // The CSS variable --font-inter is set on <html>.
        sans: ['var(--font-inter)', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      boxShadow: {
        glass: '0 8px 32px 0 rgba(2, 6, 23, 0.45)',
        'glow-cyan': '0 0 24px 0 rgba(34, 211, 238, 0.35)',
        'glow-blue': '0 0 24px 0 rgba(59, 130, 246, 0.35)',
        card: '0 4px 24px 0 rgba(2, 6, 23, 0.4)',
      },
      borderRadius: {
        card: '1rem',
        pill: '9999px',
      },
      backdropBlur: {
        glass: '16px',
      },
      backgroundImage: {
        'hero-glow':
          'radial-gradient(ellipse 80% 50% at 50% -20%, rgba(34, 211, 238, 0.15), transparent)',
        'grid-lines':
          'linear-gradient(to right, rgba(148, 163, 184, 0.06) 1px, transparent 1px), linear-gradient(to bottom, rgba(148, 163, 184, 0.06) 1px, transparent 1px)',
      },
    },
  },
  plugins: [],
};
