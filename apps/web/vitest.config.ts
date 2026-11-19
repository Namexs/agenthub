import { createRequire } from 'node:module';
import path from 'node:path';
import { defineConfig } from 'vitest/config';

// The hook tests (hooks/**/*.test.tsx) need jsdom + @testing-library/react.
// Those deps cannot be installed by pnpm on the dev VM — chown is blocked
// on the VM filesystem, so every pnpm install fails at the lockfile write
// (see FRONTEND_INTEGRATION_REPORT.md §Phase 8). They are therefore NOT in
// package.json: on a normal machine run
//   pnpm add -D @testing-library/react jsdom
// and the hook tests join the default suite automatically. Where the deps
// do not resolve, the hook tests are simply not collected and the default
// suite stays green — never a failure.
const require = createRequire(import.meta.url);
function resolvable(specifier: string): boolean {
  try {
    require.resolve(specifier);
    return true;
  } catch {
    return false;
  }
}
const hookTestsAvailable = resolvable('jsdom') && resolvable('@testing-library/react');

export default defineConfig({
  resolve: {
    // Mirror tsconfig paths (@/* -> ./*); vitest does not read them.
    alias: { '@': path.resolve(__dirname) },
  },
  test: {
    include: hookTestsAvailable
      ? ['lib/**/*.test.ts', 'hooks/**/*.test.tsx']
      : ['lib/**/*.test.ts'],
    environment: 'node',
    // Hook tests render React components, so they need a DOM. This glob
    // only ever matches when the deps above resolved (see include).
    environmentMatchGlobs: [['hooks/**', 'jsdom']],
  },
});
