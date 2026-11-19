# AGENTHUB — Final Pre-Testnet Cleanup Report

**Date:** 2026-11-19. **Baseline:** `76572c6` (remediation, 193/193 Foundry
tests). **Code frozen at:** `5775cd3` (this report + evidence package are
docs-only commits on top). **Evidence package:**
`final-pre-testnet-package/` (README + frozen reports + raw logs).

**Numbering note:** this report follows the directive
(`FINAL_PRE_TESTNET_DIRECTIVE.md`): 1–2 manifest, 3 gate doc, 4 Vitest,
5 Safe validation, 6 validator allowlist, 7 VERIFIER_ROLE SOP, 8 transient
investigation, 9 full re-run, 10 no-deploy rule. Two commit messages cite
the coordinator brief's numbering instead (gate = "item 2", Vitest =
"item 3"); the work is the same.

## 1. Verdict

**GO for BSC testnet staging** — conditional on the user providing tBNB +
a dedicated deployer key and accepting the transient-failure caveat (§4).
**NO-GO for mainnet** (unchanged: testnet staging + external review first).

Why GO, on evidence rather than test counts alone:

- **No contract logic changed except the two user-requested features**
  (Safe validation is deployment-script only; the allowlist is a new,
  fully tested gate on QuestManager). Everything else is tests, docs,
  scripts, and formatting.
- **218/218 Foundry tests across 8 full green runs** in this cleanup (5
  seeded + unseeded + fuzz 10k + aggregate), plus the 193/193 baseline.
- **Slither finding set identical to the remediation baseline** — 10
  findings, 0 Critical/High/Medium, 4 Low, 6 Informational, 0 new.
- **The two user-found design gaps are closed and tested**, and the
  operational gaps (Safe check, verifier SOP, vitest) are closed too.
- **The transient failure could not be reproduced** after a serious,
  logged hunt (§4). It remains a caveat, not a blocker for testnet
  staging — but the mitigations in §4.4 should be adopted before
  mainnet.

## 2. What changed, per directive item

### Items 1–2 — Manifest (commit: manifest commit, last)

`PACKAGE_MANIFEST.md` regenerated for the final commit with
`scripts/generate-manifest.sh` and verified with
`scripts/verify-manifest.sh`: **209 file hashes, 0 mismatches**, both
submodules match. The old manifest described commit `18e1aa4` (168
hashes) and was stale by design (it describes the commit it was generated
from, committed separately). No script changes were needed — the design
was sound; it was simply out of date.

### Item 3 — Deployment gate doc (commit `05d6395`)

`docs/SECURITY_DEPLOYMENT_GATE.md` updated to the real state: 218 Foundry
tests, Vitest 24 tests, M4 closed, Slither 10 findings (0
Critical/High/Medium, 4 Low, 6 Informational), deployment script
available, **testnet explicitly NOT deployed**. Also: pre-testnet
checklist gains the validator-approval step; the pause-runbook item
notes partial coverage via the VERIFIER_ROLE SOP (§4 of that doc).

### Item 4 — Vitest (commit `abf7491`, closes M4)

- `vitest 3.2.4` pinned in `apps/web` and `packages/shared`; the `test`
  scripts replace the echo placeholders; aggregate `pnpm test` runs
  vitest (web + shared) plus `forge test` (contracts).
- **24 new tests, all passing:** env validation (13, incl. the M5
  chain↔Agent ID consistency rules — mainnet rejects a non-official
  Agent ID, testnet rejects the official one, local accepts any
  non-zero address), chain helpers (3), shared constants + QuestType
  (8, pinning the official Agent ID address and the chain ids).
- New files: `apps/web/vitest.config.ts`,
  `apps/web/lib/env.test.ts`, `apps/web/lib/chains.test.ts`,
  `packages/shared/vitest.config.ts`,
  `packages/shared/src/constants.test.ts`.

### Item 5 — Safe validation for ADMIN_MULTISIG (commit `657502f`)

- New `script/SafeValidation.sol` library: staticcalls `getThreshold()`
  and `getOwners()` on the address, fail-closed; requires a real Safe
  with **threshold ≥ 2** (`MIN_SAFE_THRESHOLD = 2`); errors `NotASafe` /
  `UnsafeThreshold`.
- Enforced in `DeployAgentHub.deploy()` before any deployment, and
  available standalone as `script/ValidateSafe.s.sol`.
- Tests: new `test/SafeValidation.t.sol` (6 tests) + `DeployScript.t.sol`
  now uses a 2-of-3 `MockSafe` (was an EOA) with 5 new tests — 11 new
  tests total. Documented in `DEPLOYMENT_PLAN.md` §3.

### Item 6 — Validator allowlist for OnChain quests (commit `9cda09f`)

- `QuestManager.approvedValidators` mapping; admin-only
  `approveValidator` / `revokeValidator`; `ValidatorNotApproved` error;
  `ValidatorApproved` / `ValidatorRevoked` events.
- **Enforced at creation AND completion** — revoking a validator takes
  effect immediately, even for quests created while it was approved.
- New suite `test/ValidatorAllowlist.t.sol` (14 tests); `IQuestManager`
  + `IQuestValidator` (TRUST comment) updated; `Validator.t.sol` and
  `Invariant.t.sol` updated to approve validators.
- Documented: `QUEST_VALIDATION_DESIGN.md` §2.4 (design, initial list =
  TokenBalanceValidator instances, add/remove process) and
  `DEPLOYMENT_PLAN.md` §4/§6 (trust assumption + post-deploy approval
  step).

### Item 7 — VERIFIER_ROLE SOP (commit `62ad154`)

New `docs/VERIFIER_ROLE_SOP.md`: trust model, who-holds-keys rules
(named verifiers, dedicated hardware-backed keys, ≤ 3 verifiers),
grant procedure, **routine rotation** (grant new first, drain in-flight
attestations ≤ 7 days, then revoke — revocation immediately invalidates
outstanding attestations), **emergency revocation** (pause first — the
only instant control — then timelock revoke, then timelock unpause;
honest worst case ~4 days paused), attestation issuance duty,
monitoring, and checklists. Consistent with the attestation design
(§2.3) and T-ATT-01.

### Item 8 — Transient-failure investigation — see §4

### Item 9 — Full re-run — see §3

### Item 10 — No broadcast / no deploy

Honored throughout: no transaction was broadcast, no contract deployed
to any network, no private key or real funds used, the user's wallet
(`baw`) was never touched. The only network calls were read-only
(testnet-fork dry-runs in the remediation phase, registry reads for
vitest).

## 3. Verification results (item 9 — all real numbers)

| Check | Result | Log |
|---|---|---|
| Foundry full suite (unseeded) | **218 passed, 0 failed** (16 suites, 51.53s) | `logs/final-forge-test.log` |
| Foundry fuzz 10,000 runs | **218 passed, 0 failed** (63.11s) | `logs/final-forge-fuzz-10k.log` |
| Foundry seeded runs (item 8) | **5 × 218 passed, 0 failed** (seeds 1, 42, 12345, 987654321, 20261119) | `logs/transient-run-seed-*.log` |
| Aggregate `pnpm test` | **exit 0** — forge 218/218 + vitest shared 8/8 + vitest web 16/16 | `logs/final-pnpm-test.log` |
| Vitest (web + shared) | **24 passed, 0 failed** | `logs/final-pnpm-test.log` |
| Slither 0.11.6 | **10 findings: 0 Critical/High/Medium, 4 Low, 6 Informational** — identical set to the 76572c6 baseline (only line-number shifts + cyclomatic complexity 13→14, Informational, from the allowlist branch) | `logs/final-slither.log`, `logs/final-slither.json` |
| `pnpm lint` | exit 0 | `logs/final-pnpm-lint.log` |
| `pnpm typecheck` | exit 0 | `logs/final-pnpm-typecheck.log` |
| `pnpm format:check` | exit 0 (was failing pre-existing at baseline — see §5) | `logs/final-pnpm-format2.log` (first failing run: `logs/final-pnpm-format.log`) |
| `forge fmt --check` | exit 0 | `logs/final-forge-fmt.log` |
| Web build (`NODE_OPTIONS=--max-old-space-size=1024`) | exit 0 | `logs/final-pnpm-build.log` |
| Manifest verification | **209 hashes, 0 mismatches** | (run at commit time; see §2 items 1–2) |

Baseline preserved: **no existing test was deleted or weakened**. The
suite grew 193 → 218 purely by addition (14 allowlist + 11 Safe).

## 4. Transient-failure investigation (item 8)

### 4.1 Background

During the remediation phase, 1 of the parent's 5 verification runs
failed 1 test (unidentified — only the tail was logged), and the
coordinator saw 2 similar failures. A hunt then (5 consecutive green
runs, fuzz × 10 seeds, invariant × 4 seeds, no replay corpus in
`cache/`) found no reproducible cause. Leading hypothesis: a random
fuzz seed (`foundry.toml` pins no seed). Documented in
`REGRESSION_RESULTS.md` §4.4.

### 4.2 What this cleanup tried

- **5 full seeded runs** (`--fuzz-seed` 1, 42, 12345, 987654321,
  20261119), sequential, **full output saved** to
  `logs/transient-run-seed-*.log` (the lesson from §4.1: never save
  only the tail). **All 5 green: 218/218 each.**
- **1 unseeded full run** (default random seed): 218/218.
- **1 fuzz 10,000-run run**: 218/218 (fuzz tests exercised 40× deeper
  than the default 256 runs).
- **1 aggregate `pnpm test`** (forge + vitest): 218/218 + 24/24.
- **Total in this cleanup: 8 full green runs at 218 tests**, on top of
  the 5 green runs from the remediation hunt (at 193 tests).

Note: forge 1.9.0 has no separate `--invariant-seed` flag; invariant
runs derive their randomness from the same fuzz seed, so the seed sweep
covers invariant randomness as far as the tooling allows.

### 4.3 Result: NOT reproduced

No failure was observed in any run. The failing test from the original
incidents remains unidentified, and the root cause remains unknown.

### 4.4 Remaining hypotheses

1. **Random fuzz seed hitting a rare input** (still the leading
   hypothesis — unproven, and 8 green runs + a 10k fuzz run make a
   seed-dependent bug less likely but do not rule out a very rare one).
2. **Environment flake** (VM CPU/RAM pressure during parallel runs —
   the original failures happened while other heavy work ran
   concurrently; this cleanup ran everything sequentially).
3. **A genuinely rare invariant/fuzz edge** that needs a specific
   multi-call sequence.

### 4.5 Recommended mitigations

- **Pin a seed in CI** (`--fuzz-seed <fixed>`) for reproducibility,
  **and** run a nightly/weekly unseeded run so a pinned seed does not
  hide a rare bug.
- **Always save full logs** from CI and local runs (never tail-only).
- If a failure ever recurs: save the full log, the seed (forge prints
  it on failure), and the failing test name before re-running —
  `forge test --fuzz-seed <seed>` reproduces a seed-dependent failure.

## 5. Environment quirks found (and fixed) in this cleanup

- **pnpm cannot write its lockfile on this VM** (EPERM chown): the
  shell runs as root in a user namespace and the workspace btrfs mount
  forbids any chown that changes uid/gid; pnpm's lockfile writer
  chowns the temp file to match the original file's 0:65534 ownership
  and fails. `/tmp` (tmpfs) allows chown but is only 512 MB — a full
  `pnpm add` there fills it (ENOSPC). **Workaround used:** copy the
  repo to `/tmp` via `git archive`, hand-edit `package.json`, run
  `pnpm install --lockfile-only` (no `node_modules`, no tarball
  downloads), copy back `package.json` + `pnpm-lock.yaml`, then
  `pnpm install` in the repo. Note: `pnpm add --lockfile-only` still
  installed `node_modules` (501 MB) — use `pnpm install
  --lockfile-only` instead. `pnpm install` in the repo exits 255
  (EPERM on `.modules.yaml` at the very end) but installs
  functionally — vitest 3.2.4 verified working.
- **`pnpm format:check` was already failing at the 76572c6 baseline**
  (20 files, mostly remediation/retest docs and frozen JSON logs) and
  CI runs it, so the repo was red. Fixed in commit `5775cd3`:
  `.prettierignore` now covers the frozen evidence packages
  (`security-retest-report/`, `security-remediation-package/`,
  `final-pre-testnet-package/` — evidence stays byte-identical, same
  rationale as the existing `security-review-package/logs/` entry)
  and the live docs were prettier-formatted (formatting only).
- **`forge` is not on this shell's PATH** (`~/.foundry/bin/forge` is
  the persistent install); the aggregate `pnpm test` needs it
  exported. CI installs foundry via the toolchain action, so this is
  local-only.
- `pnpm audit` remains blocked locally (registry 403) — CI audit job
  covers it on runners (unchanged, pre-existing).

## 6. What still needs the user

1. **tBNB + dedicated deployer key** (blocking for testnet deploy).
2. **Admin Safe signer decision** (threshold ≥ 2 enforced by the
   deploy script).
3. **First verifier key-holder decision** (see `VERIFIER_ROLE_SOP.md`).
4. **GO/NO-GO decision for the testnet deploy** — this report
   recommends GO for testnet staging (§1); the final call is the
   user's, including acceptance of the §4 caveat.
5. **External review before mainnet** (unchanged from the gate doc).

## 7. Evidence

- `final-pre-testnet-package/README.md` — package summary.
- `final-pre-testnet-package/logs/` — raw command output for every
  check in §3 and every run in §4.2.
- `final-pre-testnet-package/reports/FINAL_PRE_TESTNET.md` — frozen
  copy of this report.
- `PACKAGE_MANIFEST.md` — regenerated for the final commit (210
  hashes, verified).
- Commits (cleanup, on top of `76572c6`): `9cda09f` (allowlist),
  `657502f` (Safe validation), `abf7491` (Vitest), `62ad154` (SOP),
  `05d6395` (gate + design docs), `5775cd3` (format fix), plus this
  report + package + manifest commits.
