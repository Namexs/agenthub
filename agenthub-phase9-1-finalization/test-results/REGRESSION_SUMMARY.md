# AGENTHUB Phase 9.1 — Regression Battery (item 7)

- **Repo:** `~/workspace/agenthub/`, branch `main`, HEAD `0313922`
  (`fix(test): correct ANVIL_KEY typo in DeployScriptTest`)
- **Run:** 2026-11-20 ~09:07–09:20 WIB (02:07–02:20 UTC)
- **Solidity:** 0.8.39 · **Target:** BNB Testnet chain 97 (no deployment, no
  broadcast, no private key used in this battery)
- **Raw logs:** `agenthub-phase9-1-finalization/logs/` (this file's sibling dir)

## Verdict

**13 of 14 steps PASS. 1 step FAILS: step 7 (Lint) — `forge fmt --check`
exits 1 on 4 Phase 9.1 files.** No code or test was modified to make anything
pass; the formatting failure was retried once and reproduced. The failure is
formatting-only (no test, build, or security impact), but it is a real
regression vs the Phase 9 baseline (exit 0) and would fail the CI format job
(`forge fmt --check`). Fix is `forge fmt` on the 4 files — left to the code
worker / parent decision, not done here (tracked files untouched).

## Results table

| #   | Step                               | Command / mechanism                                                                                    | Result                                                                                                                                                                                                                                                                           | Baseline (Phase 9)         | Log                                                             |
| --- | ---------------------------------- | ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- | --------------------------------------------------------------- |
| 1   | `forge build`                      | `forge build` in `packages/contracts/`                                                                 | **PASS** — exit 0 (warnings only; compilation cached, "No files changed")                                                                                                                                                                                                        | exit 0                     | `regression-forge-build.log`                                    |
| 2   | `forge test`                       | `forge test`                                                                                           | **PASS** — **343 passed, 0 failed, 0 skipped** (24 suites, 46.68s)                                                                                                                                                                                                               | 323/323                    | `regression-forge-test.log`                                     |
| 3   | Fuzz 10k                           | `forge test --fuzz-runs 10000 --fuzz-seed 42` (CI's pinned seed)                                       | **PASS** — **343 passed, 0 failed, 0 skipped** (24 suites, 95.02s)                                                                                                                                                                                                               | 323/323 @ 10k              | `regression-forge-fuzz-10k.log`                                 |
| 4   | Invariant tests                    | Suite `InvariantTest` in `packages/contracts/test/Invariant.t.sol`, run inside `forge test`            | **PASS** — 5 invariants PASS (`invariant_BadgesMatchGhost`, `invariant_CompletionsMatchAndRespectCap`, `invariant_EventsMatchGhost`, `invariant_NonHolderEarnsNothing`, `invariant_PointsMatchGhost`), runs 256, calls 32768, reverts 0; + `test_HandlerActuallyCompletesQuests` | covered in `forge test`    | `regression-forge-test.log`, `regression-forge-fuzz-10k.log`    |
| 5   | Vitest web + shared                | `vitest run` via each package's local `node_modules/.bin` (pnpm absent on VM — see notes)              | **PASS** — web **173 passed + 5 skipped** (10 files, 9 passed / 1 skipped); shared **8/8**                                                                                                                                                                                       | web 173+5 skip, shared 8/8 | `regression-vitest-web.log`, `regression-vitest-shared.log`     |
| 6   | TypeScript typecheck               | `tsc --project tsconfig.json --noEmit` (web + shared)                                                  | **PASS** — web exit 0, shared exit 0                                                                                                                                                                                                                                             | exit 0                     | `regression-typecheck.log`                                      |
| 7   | Lint                               | web `next lint`, shared `eslint src --ext .ts`, contracts `forge fmt --check`                          | **FAIL** — web exit 0 ("No ESLint warnings or errors"), shared exit 0, **contracts `forge fmt --check` exit 1** (4 files, see below)                                                                                                                                             | exit 0                     | `regression-lint.log`, `regression-forge-fmt-retry.log`         |
| 8   | Production build (Next.js)         | `NODE_OPTIONS=--max-old-space-size=1024 next build` in `apps/web`                                      | **PASS** — exit 0, 9 routes, First Load JS 87.3 kB shared                                                                                                                                                                                                                        | exit 0                     | `regression-next-build.log`                                     |
| 9   | E2E smoke + wallet                 | `apps/web/scripts/run-e2e-smoke.sh`, `run-wallet-e2e.sh` (Playwright, Chromium installed)              | **PASS** — smoke **23/23**, wallet **26/26** (threshold-2 attestation checks pass)                                                                                                                                                                                               | 23/23 + 26/26              | `regression-e2e-smoke.log`, `regression-e2e-wallet.log`         |
| 10  | Anvil integration                  | `apps/web/scripts/run-anvil-integration.sh` (local anvil, throwaway test key only)                     | **PASS** — node checks **30/30**, vitest anvil test **5/5**                                                                                                                                                                                                                      | 30/30 + 5/5                | `regression-anvil-integration.log`                              |
| 11  | Slither 0.11.6                     | `slither . --exclude-dependencies --fail-medium` (CI version, venv install)                            | **PASS** — exit 0, **0 High / 0 Medium**, 4 Low + 9 Informational (13 total; see note)                                                                                                                                                                                           | 0H/0M (4 Low + 8 Info)     | `regression-slither.log`, `regression-slither.json`             |
| 12  | OSV scan                           | Repo mechanism `scripts/osv-audit.mjs` (OSV API over `pnpm-lock.yaml`, 960 packages)                   | **PASS** — **7 findings: 6 MODERATE + 1 LOW, 0 CRITICAL / 0 HIGH**                                                                                                                                                                                                               | 7, 0C/0H                   | `regression-osv-audit.log`, `regression-osv-audit.json`         |
| 13  | Gitleaks 8.27.2                    | `gitleaks detect` (full history, repo `.gitleaks.toml`)                                                | **PASS** — **0 leaks**, 116 commits scanned, 7.65 MB                                                                                                                                                                                                                             | 0 leaks                    | `regression-gitleaks.log`, `regression-gitleaks.json`           |
| 14  | ABI parity + `export-abis --check` | `node packages/contracts/script/export-abis.mjs --check` + `lib/abis/abi-parity.test.ts` in vitest web | **PASS** — `export-abis --check` exit 0 ("all 4 committed ABIs match regeneration"); ABI parity **13/13** in vitest                                                                                                                                                              | 13/13 + exit 0             | `regression-export-abis-check.log`, `regression-vitest-web.log` |

## Failure detail — step 7 (`forge fmt --check`, exit 1)

Retried once: same exit 1, same 4 files. All 4 are Phase 9.1 files; the diffs
are line-wrapping only (no semantic change):

1. `packages/contracts/test/DeploymentArtifact.t.sol` — long string constants
   (`HASH_*`) and one `assertEq` call
2. `packages/contracts/test/ProposeGrantVerifier.t.sol` — `buildProposal(...)`
   call wrapping (4 sites) + `vm.expectRevert(...)` wrapping (3 sites)
3. `packages/contracts/script/RecordDeployment.s.sol` — array literal +
   `string.concat(...)` wrapping
4. `packages/contracts/script/ProposeGrantVerifier.s.sol` — chained
   `.schedule(...)` call wrapping

Fix (not applied here): run `forge fmt` on these 4 files and re-check. This
would also fail the CI `format` job (`forge fmt --check`) on HEAD `0313922`.

## Notes / observations

- **Forge test count verified:** the code worker's claim of 343 is correct —
  343/343 in both the standard run and the 10k fuzz run (was 323 in Phase 9;
  +20 from Phase 9.1 tests: DeploymentArtifact 5, ProposeGrantVerifier 12,
  plus DeployScript growth 33).
- **Invariant runs are not scaled by `--fuzz-runs`:** both runs show the
  invariant suite at runs 256 / calls 32768. That is Foundry's separate
  invariant depth config, not a battery gap.
- **Slither +1 Informational vs Phase 9:** 13 findings now (was 12). The new
  one is `cyclomatic-complexity` on `QuestManager.createQuest` (complexity
  15); Phase 9 documented only `_completeQuest` (14). `createQuest` crossed
  the threshold (Phase 8 H01 threshold validation + Phase 9.1 changes).
  Informational only — 0 High/Medium bar still holds; the documented
  inventory in `agenthub-final-pretestnet/FINAL_SECURITY_FINDINGS.md` §3
  (12 results) is now stale by one entry.
- **`forge build` warnings:** 30 lint warnings (reentrancy-events,
  block-timestamp, environment-read-across-mutation, etc.) — pre-existing,
  warnings only, exit 0. Full list in `regression-forge-build.log`.
- **pnpm is NOT installed on this VM** (`which pnpm` empty, no corepack).
  Per the task's environment note, no `pnpm install` was attempted. Vitest /
  tsc / eslint / next were run via each package's existing
  `node_modules/.bin` binaries (same commands the package.json scripts run).
  pnpm 9.15.4 was installed globally via `npm install -g` (tool-only, into
  `/usr/bin`, no repo write) but was not needed: the OSV step used the repo's
  `scripts/osv-audit.mjs`, which needs no pnpm (the repo's own comment
  records that `pnpm audit` is blocked on this VM — registry 403).
- **OSV run isolation:** `osv-audit.mjs` hard-codes its JSON output to
  `agenthub-final-pretestnet/logs/phase4-osv-audit.json`, which would have
  overwritten Phase 4 evidence. It was run from a scratch copy in
  `~/workspace/.tmp/osv-run/` against a copy of `pnpm-lock.yaml`; the JSON
  was copied to this battery's logs dir. No repo file was touched.
- **E2E/anvil runner logs:** the repo runners hard-code log paths under
  `agenthub-final-pretestnet/logs/` and `agenthub-final-release/logs/`
  (tracked files). Their fresh logs were copied into this battery's logs dir
  and the tracked originals restored with `git checkout --`. Same for
  `apps/web/next-env.d.ts`, which `next build` regenerates (diff: dropped
  the `./.next/types/routes.d.ts` reference line + doc-URL change).
  **Final `git status`: clean except the two untracked phase dirs** —
  no tracked file was left modified, no commit, no push.
- **Stale anvil killed:** the first wallet-E2E attempt failed its pre-flight
  ("port 8545 already in use"). The holder was an orphaned `anvil --port
8545` (PID 2492, PPID 1, started 02:04 UTC, block number 0x0 — never used).
  Killed; re-run passed 26/26. No stray anvil/next processes remain.
- **Tool installs (outside repo, no repo writes):** Slither 0.11.6 in
  `~/workspace/.tmp/slither-venv/` (CI version), gitleaks 8.27.2 binary in
  `~/workspace/.tmp/`, pnpm 9.15.4 global via npm. Playwright
  Chromium 1255 was already installed (`~/.cache/ms-playwright`).
- **No deployment / broadcast / private key:** all on-chain activity was
  local anvil only (throwaway anvil test key #0, as the repo scripts do).

## Files produced (all under `agenthub-phase9-1-finalization/`)

- `test-results/REGRESSION_SUMMARY.md` — this file
- `logs/regression-forge-build.log`
- `logs/regression-forge-test.log`
- `logs/regression-forge-fuzz-10k.log`
- `logs/regression-vitest-web.log`
- `logs/regression-vitest-shared.log`
- `logs/regression-typecheck.log`
- `logs/regression-lint.log`
- `logs/regression-forge-fmt-retry.log`
- `logs/regression-next-build.log`
- `logs/regression-e2e-smoke.log`
- `logs/regression-e2e-wallet.log`
- `logs/regression-anvil-integration.log`
- `logs/regression-slither.log`
- `logs/regression-slither.json`
- `logs/regression-slither-json-run.log`
- `logs/regression-osv-audit.log`
- `logs/regression-osv-audit.json`
- `logs/regression-gitleaks.log`
- `logs/regression-gitleaks.json`
- `logs/regression-export-abis-check.log`
