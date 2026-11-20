# AGENTHUB — Test Results (Phase 8 regression battery)

> **Source.** All numbers below are from
> `reports/PHASE8_SECURITY_REMEDIATION_REPORT.md` §5 (battery run
> 20 November 2026, 06:40–07:10 WIB, on the final Phase 8 working
> tree, solc 0.8.39) and §8 (CI). Raw logs are in the repo at
> `agenthub-phase8-remediation/logs/` — referenced here, not copied.
> The auditor can re-run every suite from the audit commit; commands
> are in `BUILD_REPRODUCTION.md`.

## 1. Summary

| Suite                               |              Baseline (5723ff3) |                                 Phase 8 final (e1b316b) | Verdict         |
| ----------------------------------- | ------------------------------: | ------------------------------------------------------: | --------------- |
| `forge build` (via-IR, solc 0.8.39) |                          exit 0 |          **exit 0** (artifacts: 0.8.39+commit.ce47f2c8) | GREEN           |
| Foundry tests                       |             287/287 (20 suites) |                                 **321/321 (22 suites)** | +34             |
| Fuzz 10,000 runs, seed 42           |                         287/287 |                                             **321/321** | +34             |
| Vitest web                          |              159 + 5 skip (164) |                                  **173 + 5 skip (178)** | +14             |
| Vitest shared                       |                             8/8 |                                                 **8/8** | same            |
| TypeScript (web + shared)           |                          exit 0 |                            **exit 0** (after PH8-1 fix) | GREEN           |
| Lint (web + shared)                 |                          exit 0 |                                              **exit 0** | GREEN           |
| Production build Next.js            | exit 0, 8 routes + `_not-found` |         **exit 0, 8 routes + `_not-found`, all static** | GREEN           |
| Prettier + `forge fmt`              |                          exit 0 |                                              **exit 0** | GREEN           |
| E2E smoke                           |                           23/23 |                             **23/23**, 0 console errors | same            |
| Wallet E2E                          |                           26/26 |                             **26/26**, 0 console errors | same            |
| Anvil integration                   |                     30/30 + 5/5 |                                         **30/30 + 5/5** | same            |
| Slither app-only                    |              exit 0, 12 results | **exit 0, 13 results: 0 High, 0 Medium, 4 Low, 9 Info** | +1 Info (PH8-2) |
| OSV audit                           |                 7 (0C/0H/6M/1L) |                      **7 (0C/0H/6M/1L)**, identical set | same            |
| Gitleaks full history               |           0 leaks (100 commits) |                               **0 leaks (100 commits)** | same            |
| `export-abis --check`               |                         — (new) |           **exit 0** — all four ABIs match regeneration | NEW             |
| ABI parity deep-equal               |      1 contract (skipped in CI) |             **4/4 contracts, running** + 5 subset tests | NEW             |

**No test was deleted; no assertion was weakened** (Phase 8 §5.7):
per-suite test counts are equal or higher than baseline; Foundry rose
287 → 321 and Vitest web 164 → 178 purely by addition. Three old tests
were updated to the new semantics WITHOUT weakening assertions (revoke
test now deactivates first; rotation test now grants first; one `setUp`
grants 1 verifier per the M01 guard).

## 2. Foundry — 321/321 (22 suites)

Total = 287 baseline + 27 new contract tests (16 PolicyEnforcement +
11 VerifierGuardrail) + 7 new deploy tests (DeployScript/PauserRole).
Fuzz with the exact CI command (`--fuzz-runs 10000 --fuzz-seed 42`):
321/321, 0 failures, 0 skips.

Key policy scenarios (all green): reward 1,001/T1 revert; 1,001/T2
succeed; 1,000/T1 succeed; 10,000/T1 revert; 10,000/T3 succeed;
high-value badge + T1 revert; high-value badge + T2 succeed; ordinary
badge + T1 succeed; CheckIn 10,000 pts T1 succeed (policy is
Attested-only — design decision, see `FINDINGS.md` PH7-L08);
threshold 0/4 still revert. Threshold 1/2/3 completion, duplicate
signer, replay, deadline, and revocation/recovery all green
(ThresholdAttestation + Attestation + VerifierGuardrail suites).

Logs: `02-forge-test.log`, `03-forge-fuzz.log`.

## 3. Vitest — web 173 + 5 skip (178), shared 8/8

+14 new web tests: +3 ABI deep-equals (M08), +6 event parity (M09),
+5 minimal-read-ABI subset tests (PH8-1). The 5 skips are
anvil-integration tests requiring `ANVIL_DEPLOYMENT`, same as baseline.

Logs: `04-vitest-web.log`, `04b-abi-parity-verbose.log` (deep-equal
4/4), `05-vitest-shared.log`, `20-vitest-rerun.log` (173 + 5 skip).

## 4. E2E + Anvil

E2E smoke 23/23, wallet E2E 26/26 (threshold-2 end-to-end, Bob's
points 150), Anvil 30/30 node checks + 5/5 vitest — all with 0 console
errors.

Logs: `09-e2e-smoke.log`, `10-wallet-e2e.log`,
`11-anvil-integration.log` (+ `-runner.log` companions).

## 5. Static analysis + audits

- **Slither (app-only):** exit 0, 13 results — 0 High, 0 Medium,
  4 Low (`timestamp` — `block.timestamp` comparisons for day/minute-scale
  windows, already triaged in Phase 7), 9 Info (`assembly` ×3,
  `low-level-calls` ×3, `cyclomatic-complexity` ×2, `pragma` ×1). One
  NEW Info vs Phase 7: `cyclomatic-complexity` on `createQuest` (PH8-2,
  benign — linear guard clauses, each tested). Two old findings only
  moved line numbers. Logs: `12-slither.log`, `12b-slither-json.log`,
  `test-results/slither-phase8.json`.
- **OSV:** 7 findings (6 Moderate, 1 Low), 0 High/Critical; set
  identical to Phase 6/7 (960 packages). Logs: `13-osv.log`,
  `test-results/osv-audit-phase8.json`.
- **Gitleaks:** 0 leaks, 100 commits scanned. Log: `14-gitleaks.log`.
- **`export-abis --check`:** exit 0. Log: `15-export-abis-check.log`.

## 6. Gas benchmark

Method: `gasleft()` measurements in `test/ThresholdAttestation.t.sol`,
`forge test --match-test testGas -vv`. Full analysis:
`test-results/gas-benchmark-phase8.md`; raw log: `16-gas-benchmark.log`.

| Measurement                        | Phase 6 (0.8.24, old code) | Phase 8 code @ 0.8.24 | **Phase 8 final (0.8.39)** |    Δ vs Phase 6 |
| ---------------------------------- | -------------------------: | --------------------: | -------------------------: | --------------: |
| Threshold-1 completion             |                    242,735 |               244,966 |                **244,840** | +2,105 (+0.87%) |
| Threshold-2 completion             |                    253,867 |               256,098 |                **255,766** | +1,899 (+0.75%) |
| Threshold-3 completion             |                    265,221 |               267,452 |                **266,911** | +1,690 (+0.64%) |
| Marginal / extra signature (T2−T1) |                     11,132 |                11,132 |                 **10,926** |            −206 |
| Marginal / extra signature (T3−T2) |                     11,354 |                11,354 |                 **11,145** |            −209 |

Decomposition: code effect +2,231 gas (constant across thresholds —
one cold SLOAD for the L07 `supersedes` guard in `_completeQuest`,
a deliberate security cost); solc 0.8.39 effect −126/−332/−541
(MCOPY codegen for `bytes[]` copies + shorter IR dispatcher). All
completions remain far below the 300,000-gas bound asserted by tests.

## 7. CI — run #44644411279, SUCCESS 10/10

Trigger: push to `main`, HEAD `d2ab86d` (Phase 8 content commit),
20 November 2026, 07:15:39–07:19:09 WIB (3 min 30 s). Fifth green run
in a row (runs #1–#4 from Phase 6 also green).
URL: https://github.com/Namexs/agenthub/actions/runs/44644411279

| Job                                                | Result     |
| -------------------------------------------------- | ---------- |
| Contracts (forge build + test)                     | ✅ success |
| Contracts fuzz + invariant (10k runs, pinned seed) | ✅ success |
| Slither static analysis (fail on Medium+)          | ✅ success |
| Secret scanning (gitleaks)                         | ✅ success |
| Dependency audit                                   | ✅ success |
| Web (lint, typecheck, vitest, build)               | ✅ success |
| Shared (lint, typecheck, vitest)                   | ✅ success |
| Format check (prettier + forge fmt)                | ✅ success |
| E2E (smoke + wallet, real build + anvil)           | ✅ success |
| Package manifest check                             | ✅ success |

The Web job now runs `forge build` before vitest (M07) — the four-contract
deep-equal parity (M08) and `export-abis --check` (I09) ran in CI for the
first time and are green. Non-blocking annotations: Node.js 20 deprecation
warnings on some actions (pre-existing). A second CI run
(#44645056350) on the final HEAD is also reported green 10/10 (see
`reports/PHASE8_SECURITY_REMEDIATION_REPORT.md` §8 note and the Phase 8
verification record).

**Caveat — local JS tree is stale.** Local verification ran on
Next 14.2.35 + React 18.3.1 installed vs Next 15.5.29 + React 19.3.1
pinned (`pnpm install` is impossible on the preparation VM). The
authority for the pinned tree is CI (§7 above), not the local battery.
The TS2589 fix (PH8-1) was verified on local TS 5.6.3, the same version
as pinned.

## 8. Raw-log index (`agenthub-phase8-remediation/logs/`)

`01-forge-build.log` · `02-forge-test.log` · `03-forge-fuzz.log` ·
`04-vitest-web.log` + `04b-abi-parity-verbose.log` ·
`05-vitest-shared.log` · `06-typecheck-lint.log` (first run — typecheck
failed TS2589, see PH8-1; green rerun in log 19) ·
`07-next-build.log` (first run — build failed TS2589; green rerun in
log 21) · `08-format.log` (first run — version artifact, see Phase 8
§9; final green in log 08b) · `08b-format-final.log` ·
`09-e2e-smoke.log` + `09-e2e-smoke-runner.log` ·
`10-wallet-e2e.log` + `10-wallet-e2e-runner.log` ·
`11-anvil-integration.log` + `11-anvil-integration-runner.log` ·
`12-slither.log` + `12b-slither-json.log` · `13-osv.log` ·
`14-gitleaks.log` · `15-export-abis-check.log` ·
`16-gas-benchmark.log` · `17-baseline-build.log` (baseline 5723ff3
rebuild) · `18-bytecode-audit.log` (comparison + opcode scan) ·
`19-typecheck-rerun.log` · `20-vitest-rerun.log` ·
`21-next-build-rerun.log` · `phase8-bytecode-audit.py` (metadata-aware
scanner).

Phase 7 battery logs (287-test baseline, 39 PoCs, gas re-measurement):
`agenthub-phase7-review/logs/` (16 logs + per-workstream reports in
`agenthub-phase7-review/findings/`).

## 9. Phase 9 re-run (audit commit `7dff852`)

The full battery was re-run on the audit commit after the Phase 9
deploy-script changes (20 November 2026, ~08:00–08:15 WIB; raw logs in
`agenthub-phase9-readiness/logs/`). All 13 suites green; the only
deltas vs Phase 8 are the 2 new deploy-guard tests.

| Suite                               | Phase 9 result (`7dff852`)                             |
| ----------------------------------- | ------------------------------------------------------ |
| `forge build` (via-IR, solc 0.8.39) | exit 0 (82 dtk)                                        |
| Foundry tests                       | **323/323** (22 suites)                                |
| Fuzz 10,000 runs, seed 42           | **323/323**                                            |
| Vitest web / shared                 | **173 + 5 skip (178)** / **8/8**                       |
| TypeScript + lint                   | exit 0                                                 |
| Production build Next.js            | exit 0, 11 halaman statis                              |
| E2E smoke / wallet E2E              | **23/23** / **26/26**, 0 console error                 |
| Anvil integration                   | **30/30 + 5/5**                                        |
| Slither app-only                    | exit 0, 13 hasil: 0 High, 0 Medium (set identik)       |
| OSV audit                           | 7 (0C/0H), set identik                                 |
| Gitleaks full history               | 0 leak (108 commit)                                    |
| ABI parity + `export-abis --check`  | vitest abi-parity 13/13, deep-equal 4/4, exit 0        |
| Gas benchmark (threshold)           | T1 244.840 / T2 255.766 / T3 266.911 — identik Phase 8 |

No test was deleted; no assertion was weakened. The fork dry-run of the
live test plan (90/90 checks) is documented separately in
`agenthub-phase9-readiness/workstreams/04-live-testnet-test-plan-fork-dryrun.md`
— it is fork evidence, not live-testnet evidence.
