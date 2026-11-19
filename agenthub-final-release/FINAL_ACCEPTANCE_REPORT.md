# AGENTHUB — Final Acceptance Report (Phase I)

**Date:** 2026-11-19. **Phase:** I — Final regression.
**Baseline:** `5417787` (FINAL REMEDIATION, 2026-11-19 ~18:06 WIB).
**Final content commit:** `8f54900` (this report is committed on top;
the manifest is regenerated for the final commit afterwards — see §7).
**Work:** 16 commits, 86 files changed, +19,646 / −751 lines.

## 1. Decision

**CONDITIONAL GO for BNB Testnet staging. NO-GO for mainnet.**

The code is ready to deploy to testnet the moment the user supplies
the 8 deployment inputs (§5) and approves the broadcast. Every
mandatory test passes from a clean install under the CI-pinned
toolchains; no critical vulnerability is unresolved without a
documented, independently justified risk acceptance; the deployment
machinery is proven end-to-end against a chain-97 fork with a genuine
Safe. Mainnet stays NO-GO: no external audit, the Next.js 15 upgrade
is pending, the testnet smoke test has not run on the live chain, and
the mainnet gate in `FINAL_DEPLOYMENT_CHECKLIST.md` §7 is unsatisfied.

This is NOT a full GO, for two explicit reasons that no amount of
local work can resolve:

1. **CI has never run on GitHub.** The repo has no GitHub remote.
   All 12 checks reproduce locally and pass (Phase G), including two
   defects that would have failed the first GitHub run — but a GitHub
   run is unproven until a remote exists and the workflow executes
   there.
2. **Deployment inputs are missing.** All 8 items in §5 (tBNB,
   deployer key, Safe, creator, verifier, pauser, BscScan key,
   explicit broadcast approval) are still with the user.

## 2. Final regression — baseline vs final

Full suite run in a fresh clean copy (`git archive` of `8f54900` +
submodules) under Node v20.20.2 + pnpm 9.15.4 + forge 1.9.0 +
slither 0.11.6 (the CI pins). The install was a **cold install from
the registry** (the VM restarted mid-battery and wiped the pnpm
store — the first attempt was SIGTERM'd during the web build; the
battery was re-run in full from scratch and every step below is from
the complete run).

| Suite                               | Baseline (`5417787`)         | Final (`8f54900`)                                              | Verdict  |
| ----------------------------------- | ---------------------------- | -------------------------------------------------------------- | -------- |
| Clean install (`--frozen-lockfile`) | Not proven (manual symlinks) | exit 0, cold from registry                                     | IMPROVED |
| Foundry tests                       | 255/255                      | **255/255** (19 suites)                                        | SAME     |
| Fuzz (10,000 runs, seed 42)         | 255/255                      | **255/255**                                                    | SAME     |
| Vitest web                          | 136 passed + 4 skipped       | **136 passed + 4 skipped** (140)                               | SAME     |
| Vitest shared                       | 8/8                          | **8/8**                                                        | SAME     |
| TypeScript (web + shared)           | exit 0\*                     | exit 0                                                         | SAME     |
| Lint (web + shared)                 | exit 0                       | exit 0                                                         | SAME     |
| Production build (chain 97)         | exit 0                       | exit 0, 8 routes + `_not-found`, all static                    | SAME     |
| Prettier + `forge fmt`              | exit 0\*                     | exit 0                                                         | SAME     |
| E2E smoke (unconnected)             | 23/23                        | **23/23**, 0 page/console errors                               | SAME     |
| Wallet E2E (connected)              | did not exist                | **25/25**, 0 page/console errors                               | NEW      |
| Anvil integration                   | 27/27 + 4/4                  | **27/27 + 4/4**                                                | SAME     |
| Slither (`--fail-medium`)           | exit 0, 12 results           | exit 0, **12 results (4 Low + 8 Info)**                        | SAME     |
| OSV dependency audit                | 76 (8C/21H/41M/6L)           | **33 (3C/9H/18M/3L)**                                          | IMPROVED |
| Gitleaks (full history)             | 0 leaks                      | **0 leaks** (73 commits)                                       | SAME     |
| Manifest verification               | 291/291 for `9d71517`        | 291/291 for `9d71517` (regenerated for the final commit in §7) | SAME     |

\* Baseline typecheck/format passed only with the manual node_modules
symlinks in place; the final numbers come from a clean install with
declared test dependencies (Phase C).

**Zero regressions. Zero tests deleted. Zero security assertions
weakened. Zero CI checks disabled.** The 4 skipped web tests are the
pre-existing baseline skips, unchanged; the 1 skipped test file is
`lib/anvil-integration.test.ts`, which runs only under the anvil
runner by design.

## 3. What changed, per phase

| Phase                   | Gate   | Changes                                                                                                                                                                                                                                                                                                         |
| ----------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A — Source integrity    | PASSED | Manifest verified (291/291, commit `9d71517`); delta vs the remediation report is 5 files, no source changes. Report only.                                                                                                                                                                                      |
| B — Dependency security | PASSED | next 14.2.18→14.2.35, vitest 3.2.4→4.1.12, postcss→8.5.33, zod 3→4.6.7 + 7 pnpm overrides; lockfile regenerated (3 rounds); OSV 76→33; per-finding risk acceptance for the 12 remaining Next.js findings.                                                                                                       |
| C — Test infrastructure | PASSED | Test deps declared (`@testing-library/react` 16.3.3, jsdom 26.1.0, playwright 1.65.1); graceful-skip fallback removed (missing deps fail loudly); clean install proven; full suite green from a clean copy.                                                                                                     |
| D — Contract security   | PASSED | 15/15 areas audited, **0 exploitable vulnerabilities**; no contract code changed; 4 observations (non-findings) recorded.                                                                                                                                                                                       |
| E — Attestation         | PASSED | 12/12 EIP-712 lifecycle points verified; built the missing local verifier signing tool (`sign-attestation.mjs`, key from env only, refuses non-verifiers); SOP updated; NO verifier dashboard / backend signing service for testnet (decision documented).                                                      |
| F — Frontend & wallet   | PASSED | 11/11 areas verified; new wallet E2E suite (25/25, real wagmi `injected()` path on anvil); runner cleanup fixes (process-group kill, `pipefail`); no app code changed.                                                                                                                                          |
| G — CI/CD               | PASSED | Found + fixed a **nonexistent Node pin** (`20.17.6` → `20.20.2`, would have failed every JS job on GitHub); fail-closed audit allowlist script (4 test cases); stale comments fixed; all 12 checks reproduce locally.                                                                                           |
| H — Testnet readiness   | PASSED | Full deploy proven on a chain-97 fork with a genuine Safe (18 txs, all §4.3 post-deploy checks green); found + fixed the **BscScan key gap** (foundry ignores `BSCSCAN_API_KEY` — added the `[etherscan]` mapping); fixed stale `DEPLOYMENT.md` (incl. invalid `--verifier bscscan`); completed `.env.example`. |
| I — Final regression    | PASSED | This report. Full suite green from a clean install (see §2).                                                                                                                                                                                                                                                    |

## 4. Dependency audit — before / after

|                | Baseline | Final                                                                                                             |
| -------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| Packages       | 920      | 950 (test deps added)                                                                                             |
| Total findings | 76       | **33**                                                                                                            |
| CRITICAL       | 8        | **3** (all `next@14.2.35`, image-optimization RCE ×2 + Windows RCE — not applicable: no `next/image`, Linux-only) |
| HIGH           | 21       | **9** (all `next@14.2.35`)                                                                                        |
| MODERATE       | 41       | 18                                                                                                                |
| LOW            | 6        | 3                                                                                                                 |

Fixed by the upgrades: CVE-2025-29927 + 2 Next.js HIGH DoS, vitest
UI RCE, tinypool ×2 CRITICAL, postcss ×4 HIGH, zod, ws, glob,
decode-uri-component, coinbase wallet-sdk, vite HIGH. The 12
remaining Next.js findings have fixes only in Next.js 15.x/16.x; the
upgrade (React 19 migration) is a recorded **pre-mainnet
requirement**. Each of the 12 carries a documented risk acceptance
(`DEPENDENCY_REMEDIATION_REPORT.md` §6) and an allowlist entry
(`scripts/pnpm-audit-allowlist.mjs`) that fails the CI audit job on
any NEW high/critical finding or any stale entry.

## 5. Open findings, residual risks, deployment blockers

**Open findings (none blocking for testnet staging):**

- O1. Next.js 15 upgrade pending (pre-mainnet requirement; §4).
- O2. No external security audit of the contracts (pre-mainnet
  requirement; internal audit found 0 exploitable issues).
- O3. E2E suites are not CI jobs yet (playwright is now declared, so
  the Phase 4 blocker is gone — recommended follow-up).
- O4. Real wallet-app check outstanding (the wallet E2E uses an
  injected stub — it proves the wagmi path, not a real Binance
  Wallet / MetaMask build, extension popups, or mobile deep-links).
- O5. Cancun-opcode support on BSC must be smoke-tested on testnet
  before any mainnet deploy (contracts use no Cancun-only opcodes,
  but the pin is unproven on BSC).

**Residual risks (carried from Phases D/E/F):**

- R1. Safe identity is out-of-band: validation proves an address IS
  a genuine Safe, not that it is THE TEAM'S Safe (§5.1 of the plan
  is mandatory before broadcast).
- R2. Verifier honesty (T-ATT-01): attestations are only as honest
  as their verifiers; revocation takes up to ~4 days across the
  timelock (pause is the fast path).
- R3. Testnet identity is mock-based: testnet cannot prove mainnet
  Agent ID gating.
- R4. Timelock key loss: executors = multisig only; a lost multisig
  cannot be administered (testnet: redeploy; mainnet: catastrophic).
- R5. Global attestation nonce: one pending attestation per account
  at a time; a second must be re-signed.
- R6. No on-chain undo for dishonest attestations / no badge
  revocation / no points correction (immutable ledger by design).

**Deployment blockers (all with the user):**

1. No GitHub remote → CI unproven on GitHub (see §1).
2. tBNB (≥ 0.05 tBNB recommended; deploy costs ~0.0012 tBNB).
3. Dedicated deployer key (single-use, secure channel — never chat).
4. Admin multisig (Safe) address on BSC testnet, threshold ≥ 2.
5. Quest creator address.
6. First verifier address (optional).
7. Pauser address (optional — defaults to the multisig).
8. BscScan API key.
9. Explicit approval to broadcast this specific testnet deployment.

## 6. What still needs the user

1. **Create the GitHub remote** (or confirm the repo stays local) —
   without it, CI can never run on GitHub and the decision can never
   become a full GO.
2. **Provide the 8 deployment inputs** in §5 (items 2–9) when ready
   to deploy to testnet — then the deployment-day sequence in
   `FINAL_DEPLOYMENT_CHECKLIST.md` §4 runs as written.
3. **Decide the Next.js 15 upgrade timing** (pre-mainnet requirement;
   needs a normal machine — lockfile regeneration is impossible on
   this VM — plus a React 19 migration plan).
4. **Commission the external security review** before any mainnet
   talk (checklist §7 item 2).

## 7. Manifest regeneration

`PACKAGE_MANIFEST.md` is regenerated for the final commit after this
report is committed (the manifest excludes itself and is committed
separately from the commit it describes — the established pattern;
`verify-manifest.sh` confirms the recorded commit matches). The
regenerated manifest + its verification are committed as the final
step of this remediation.

## 8. Evidence index

All reports in `agenthub-final-release/`; all raw logs in
`agenthub-final-release/logs/` (phases A–I, 77 files):

- `SOURCE_INTEGRITY_REPORT.md` (A)
- `DEPENDENCY_REMEDIATION_REPORT.md` (B)
- `TEST_INFRASTRUCTURE_REPORT.md` (C)
- `CONTRACT_FINAL_AUDIT.md` (D)
- `ATTESTATION_FINAL_REPORT.md` (E)
- `FRONTEND_FINAL_ACCEPTANCE.md` (F)
- `CI_FINAL_REPORT.md` (G)
- `TESTNET_DEPLOYMENT_READINESS.md` (H)
- `FINAL_ACCEPTANCE_REPORT.md` (I — this report)

**Final verdict: CONDITIONAL GO for BNB Testnet staging, NO-GO for
mainnet.** No deployment is authorized by this report — only the
user's explicit approval for a specific broadcast authorizes one.
