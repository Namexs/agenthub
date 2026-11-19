# AGENTHUB — Test Infrastructure Report (Phase C)

**Date:** 2026-11-19. **Phase:** C — Test Infrastructure.
**Baseline problem:** the web test suite depended on
`@testing-library/react`, `jsdom`, and `playwright`, but none of them
was declared in `apps/web/package.json`. The suite only ran because a
previous remediation hand-symlinked the packages from a scratch dir
into `node_modules/` — not reproducible, and `vitest.config.ts`
silently skipped the 58 hook tests when the deps were missing
(graceful-skip fallback), so a fresh install would have passed with
58 tests quietly dropped.
**Verdict: GATE C — PASSED.** Clean install from a fresh copy with a
frozen lockfile reproduces the full suite: Foundry 255/255, shared
8/8, web 136 passed + 4 skipped, typecheck 0, lint 0, production
build 0, E2E smoke 23/23, anvil integration 27/27 + 4/4. No manual
symlinks remain. No real test was replaced with a mock.

## 1. Changes made

| File                                | Change                                                                                                                                                                                                                                                                                                                                                     |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/web/package.json`             | Declared test deps in `devDependencies` (exact versions proven in the scratch dir): `@testing-library/react` 16.3.3, `jsdom` 26.1.0, `playwright` 1.65.1. `vitest` 4.1.12 was already declared (Phase B).                                                                                                                                                  |
| `apps/web/vitest.config.ts`         | Removed the graceful-skip fallback: `include` is now always `lib/**/*.test.ts` + `hooks/**/*.test.tsx`. Missing test deps now fail loudly instead of silently dropping the 58 hook tests. Environment `node`, jsdom via per-file `// @vitest-environment jsdom` docblocks (Vitest 4 mechanism; the `environmentMatchGlobs` option was removed in Phase B). |
| `apps/web/scripts/run-e2e-smoke.sh` | Updated the stale comment: playwright is now a declared devDependency, no longer resolved from a symlink. No behavior change.                                                                                                                                                                                                                              |
| `pnpm-lock.yaml`                    | Regenerated (same proven /tmp workaround as Phase B: `git archive` copy + `pnpm install --lockfile-only`, lockfile copied back; exit 0, same 4 pre-existing peer warnings). Test deps verified in the lockfile: jsdom 26.1.0, playwright 1.65.1, `@testing-library/react` 16.3.3, `@testing-library/dom` 10.4.2 (transitive).                              |

No test file was modified, added, or deleted. No test was replaced
with a mock. The 4 skipped web tests are the pre-existing skips from
the baseline (unchanged); the 1 skipped test file is
`lib/anvil-integration.test.ts`, which only runs under the anvil
runner (see §3) and is skipped in the plain suite by design.

## 2. Clean-install proof

Method: fresh copy of the repo at commit `58cdb50` via `git archive`
into `/var/tmp/agenthub-clean` (2 GB tmpfs with working chown;
submodule contents copied in — `git archive` excludes submodules),
then `pnpm install --frozen-lockfile`.

- Install: **exit 0 in 13.1s**, "Lockfile is up to date, resolution
  step is skipped", 952 MB `node_modules`. Log:
  `logs/phase-c-clean-install.log`.
- No manual symlinks: the install is a stock pnpm install; the only
  symlinks are pnpm's own virtual-store links. The repo's stale
  `node_modules` (vitest 3.2.4 + hand-symlinked test deps) was
  replaced afterwards by copying the clean copy's `node_modules`
  (`cp -a`) into the repo, so the working tree matches the new
  lockfile.

## 3. Clean-copy verification results (all exit 0)

| Check                                               | Result                                                                                | Log                                                                   |
| --------------------------------------------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `pnpm -r test` (Foundry)                            | **255 passed, 0 failed** (19 suites)                                                  | `logs/phase-c-clean-test.log`                                         |
| `pnpm -r test` (shared vitest)                      | **8 passed** (1 file)                                                                 | `logs/phase-c-clean-test.log`                                         |
| `pnpm -r test` (web vitest 4.1.12)                  | **136 passed + 4 skipped** (7 files passed, 1 skipped) — includes all 58 hook tests   | `logs/phase-c-clean-test.log`                                         |
| `pnpm -r typecheck`                                 | **exit 0** (the 3 pre-existing `@testing-library/react` errors from Phase B are gone) | `logs/phase-c-clean-typecheck.log`                                    |
| `pnpm -r lint`                                      | **exit 0**                                                                            | `logs/phase-c-clean-lint.log`                                         |
| `pnpm --filter @agenthub/web build`                 | **exit 0**, 8 routes, all static                                                      | `logs/phase-c-clean-build.log`                                        |
| E2E smoke (`run-e2e-smoke.sh`, Playwright chromium) | **23 passed, 0 failed**, no page errors, no console errors                            | `logs/phase-c-e2e-smoke.log`, `logs/phase-c-e2e-runner.log`           |
| Anvil integration (`run-anvil-integration.sh`)      | **27 node checks passed, 0 failed** + **4/4 vitest anvil tests**                      | `logs/phase-c-anvil-integration.log`, `logs/phase-c-anvil-runner.log` |

Note: the E2E and anvil runners write their logs into
`agenthub-final-pretestnet/logs/` inside the clean copy; the logs
were copied out to `agenthub-final-release/logs/` afterwards. The
runners were NOT executed in the repo, so the frozen Phase 4
evidence package is untouched.

## 4. Repo working-tree verification

After syncing the clean `node_modules` into the repo,
`pnpm --filter @agenthub/web test` in the repo itself: \*\*136 passed

- 4 skipped, exit 0\*\*. Log: `logs/phase-c-repo-web-vitest.log`.

One non-issue observed: invoking the vitest binary directly via
`pnpm --filter @agenthub/web exec vitest run` failed with exit 1
and an `undefined` error, because vitest is hoisted at the workspace
root and direct `exec` resolution differs from the package script
context. The package's own `test` script (`vitest run`) works in
both the clean copy and the repo. Not a defect; no action taken.

## 5. Dependency audit after test deps

OSV re-audit with the declared test deps (950 packages):
**33 findings — 3 CRITICAL, 9 HIGH, 18 MODERATE, 3 LOW**, identical
to the Phase B post-remediation count. The test deps introduce no
new findings. JSON: `logs/phase-c-osv-audit.json`. (The audit
script's hardcoded output path was restored to the Phase 4 baseline
afterwards, as in Phase B.)

## 6. Comparison vs baseline (commit 5417787)

| Suite             | Baseline                    | Phase C (clean install)      | Delta                   |
| ----------------- | --------------------------- | ---------------------------- | ----------------------- |
| Foundry           | 255/255                     | 255/255                      | none                    |
| Shared vitest     | 8/8                         | 8/8                          | none                    |
| Web vitest        | 136 + 4 skip (via symlinks) | 136 + 4 skip (declared deps) | none — now reproducible |
| Typecheck         | 0 (after symlink fix)       | 0                            | none                    |
| Lint              | 0                           | 0                            | none                    |
| Production build  | 0                           | 0                            | none                    |
| E2E smoke         | 23/23                       | 23/23                        | none                    |
| Anvil integration | 27/27 + 4/4                 | 27/27 + 4/4                  | none                    |

## 7. Residual notes

- The 4 skipped web tests and the 1 skipped file are pre-existing
  and unchanged; they are documented here, not hidden.
- The vitest-4 config migration (removal of
  `environmentMatchGlobs`) was done in Phase B; Phase C confirms
  the jsdom docblock mechanism works for both hook test files in a
  clean install.
- The CI `audit` job problem from Phase B (12 accepted Next.js
  findings still fail `pnpm audit --audit-level=high`) is
  unchanged and remains Phase G scope.
- Playwright browsers are cached at `~/.cache/ms-playwright/`
  (chromium-1255, ~700 MB) on this VM; CI installs them via
  `playwright install --with-deps chromium` (verify in Phase G).

## 8. Evidence index

- `logs/phase-c-lockfile-regen.log` — lockfile regeneration.
- `logs/phase-c-osv-audit.json`, `logs/phase-c-osv-audit.log` —
  post-test-deps OSV audit.
- `logs/phase-c-clean-install.log` — frozen-lockfile install.
- `logs/phase-c-clean-test.log` — full `pnpm -r test` in clean copy.
- `logs/phase-c-clean-typecheck.log`, `logs/phase-c-clean-lint.log`,
  `logs/phase-c-clean-build.log` — typecheck / lint / build.
- `logs/phase-c-e2e-smoke.log`, `logs/phase-c-e2e-runner.log` —
  E2E smoke 23/23.
- `logs/phase-c-anvil-integration.log`,
  `logs/phase-c-anvil-runner.log` — anvil integration 27/27 + 4/4.
- `logs/phase-c-repo-web-vitest.log` — repo working-tree web suite.

**Commits:** `c99a9a7` (declare test deps, remove graceful-skip),
`58cdb50` (lockfile + OSV evidence).
