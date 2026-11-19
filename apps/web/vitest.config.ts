import path from 'node:path';
import { defineConfig } from 'vitest/config';

// Test dependencies (@testing-library/react, jsdom, playwright) are
// declared in package.json (Phase C) and installed from the frozen
// lockfile. If they are missing, the suite MUST fail loudly — the
// previous graceful-skip fallback (which silently dropped the 58 hook
// tests when the deps did not resolve) was removed deliberately: a
// green suite must mean the full suite ran.
//
// Hook tests render React components, so they need a DOM. Each hook
// test file sets it with a `// @vitest-environment jsdom` docblock
// (Vitest 4 removed the `environmentMatchGlobs` config option).
export default defineConfig({
  resolve: {
    // Mirror tsconfig paths (@/* -> ./*); vitest does not read them.
    alias: { '@': path.resolve(__dirname) },
  },
  test: {
    include: ['lib/**/*.test.ts', 'hooks/**/*.test.tsx'],
    environment: 'node',
  },
});
