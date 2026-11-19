# AGENTHUB — Phase 6: Threshold Attestation (M-of-N) Implementation Report

**Date:** 2026-11-19. **Scope:** close R-010 (threshold attestation) by
implementing M-of-N attestation per
`THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md`, with full regression.
**Baseline:** `129439a` (NEXT PHASE VALIDATION, CONDITIONAL GO testnet).
**Final content commit:** `53849d9` (this report is committed on top;
the manifest is regenerated for the final commit afterwards — see §8).
**Work:** 9 commits, 43 files changed, +2,532 / −385 lines.

## 1. Decision

**CONDITIONAL GO for live BNB Testnet validation. NO-GO for mainnet.**

The threshold implementation is complete and fully regression-tested:
all 15 requirements from the Phase 6 task are met with evidence (§2,
§3). The code is ready to be proven on the live testnet smoke test.

**R-010 is NOT fully CLOSED.** The plan's acceptance criteria (§7)
split into two groups: implementation + regression criteria are met;
closure criteria that need the live chain or an external party are
still open — testnet smoke (blocked on the 8 deployment inputs from
the user), inclusion in the commissioned external review (R-012, not
commissioned yet), and ≥ 3 granted verifiers before the first
threshold-2 quest on mainnet (operational, at deploy time). Claiming
R-010 CLOSED now would be false: the implementation is done, the
proof on the live chain is not. Status: **IMPLEMENTED, pending live
testnet smoke test.**

## 2. What changed

### 2.1 Contracts (`packages/contracts/src/`)

| File                                                             | Change                                                                                                                                                                                                                                                                                                                                                              |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `interfaces/IQuestManager.sol`                                   | `Quest` gains `uint8 attestationThreshold`; `createQuest` gains an 11th parameter (`uint8 attestationThreshold`); `completeQuestWithAttestation` becomes `(uint256 questId, uint256 deadline, bytes[] calldata signatures)`; new errors `DuplicateAttestationSigner`, `InsufficientAttestations`, `TooManyAttestationSignatures`, `AttestationThresholdOutOfRange`. |
| `src/QuestManager.sol`                                           | `createQuest` validates 1 ≤ threshold ≤ 3 (uniform for all quest kinds) and stores it; no setter exists, so the threshold is immutable after creation. `_verifyAttestation` becomes `_verifyAttestations` (see below). Constants `MIN_ATTESTATION_THRESHOLD = 1`, `MAX_ATTESTATION_THRESHOLD = 3`, `MAX_ATTESTATION_SIGNATURES = 5`.                                |
| `src/AgentGate.sol`, `src/Reputation.sol`, `src/Achievement.sol` | No changes.                                                                                                                                                                                                                                                                                                                                                         |
| `script/DeployAgentHub.s.sol`                                    | No changes (no new constructor args, no new roles).                                                                                                                                                                                                                                                                                                                 |
| `foundry.toml`                                                   | **`via_ir = true` — REQUIRED, not optional** (see §5.1).                                                                                                                                                                                                                                                                                                            |

`_verifyAttestations` (replacing the single-signature verifier):

1. Rejects an empty array (`InsufficientAttestations`) and arrays
   over 5 signatures (`TooManyAttestationSignatures`).
2. Deadline checks exactly as before (expired / more than 7 days out).
3. Recovers every signature with `ECDSA.tryRecover` over the
   UNCHANGED EIP-712 digest (`Attestation(account, questId, nonce,
deadline)`, same domain) — all M signers sign the same digest.
   Every signature must recover to a DISTINCT `VERIFIER_ROLE`
   holder: a duplicate reverts (`DuplicateAttestationSigner`), a
   malformed/malleable signature reverts
   (`InvalidAttestationSignature`), a non-verifier reverts
   (`UnauthorizedVerifier`). Junk anywhere in the array fails the
   whole call.
4. Requires distinct valid signers ≥ the quest's threshold, else
   `InsufficientAttestations(provided, required)`. Extra signatures
   beyond M are allowed but must still be valid.
5. Consumes the account nonce EXACTLY ONCE per completion,
   regardless of M. A reverted completion burns no nonce (the whole
   transaction reverts).
6. Emits `AttestationUsed(account, questId, nonce, signer)` once per
   distinct signer (per-signer accounting and SOP weekly review work
   unchanged).

**ABI break (deliberate, per the plan):** the single-`bytes` entry
point is replaced, not kept alongside — two completion paths for the
same quest would let a threshold-2 quest be completed through the
legacy single-sig path. One entry point, one rule. No mainnet
deployment exists yet, so no live client breaks.

### 2.2 Frontend (`apps/web/`)

| File                                                                            | Change                                                                                                                                                                                                                                                                        |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/abis/QuestManager.ts`                                                      | Regenerated from the new forge build (`export-abis.mjs`): 11-param `createQuest`, `bytes[]` completion, 4 new errors. The other 3 ABIs are zero-diff.                                                                                                                         |
| `lib/attestation.ts`                                                            | New `checkAttestations()` (array verification: shape, deadline, recovery, duplicate rejection, distinct-count vs threshold, >5 cap) + `MAX_ATTESTATION_SIGNATURES` and threshold-range constants. Existing single-signature functions are unchanged in behavior.              |
| `hooks/useAttestation.ts`                                                       | `check(signatures[], deadline, threshold)`; per-signer `hasRole` reads via `useReadContracts`; verification exposes `signers` / `perSigner` / `threshold` while keeping the old fields.                                                                                       |
| `hooks/useCompleteQuest.ts`                                                     | `completeWithAttestation` submits a `bytes[]`.                                                                                                                                                                                                                                |
| `components/AttestationForm.tsx`                                                | Takes the quest's `threshold` as a prop; N dynamic signature inputs (add up to 5); shows "requires N verifier signature(s)"; per-signer status; submit enables only when all signatures verify. Existing visual style kept.                                                   |
| `lib/quests.ts`, `packages/shared/src/types.ts`, `components/QuestCardLive.tsx` | `Quest` type + `mapQuest` + `LAUNCH_QUESTS` carry `attestationThreshold`; the live quest card shows "Requires N verifier signature(s)" on Attested quests and passes the real threshold to the form.                                                                          |
| `scripts/anvil-integration.mjs`, `scripts/wallet-e2e.mjs`                       | Updated to the new call shapes (11-param `createQuest`, `bytes[]` completion). `e2e-smoke.mjs` needed no change (render-only smoke, no contract calls).                                                                                                                       |
| `scripts/sign-attestation.mjs`                                                  | No change needed — each verifier signs the same digest independently with the existing tool.                                                                                                                                                                                  |
| `lib/abis/abi-parity.test.ts`                                                   | New: ABI parity test (4 structural checks always run + 1 deep-equal check vs the Foundry build artifact, skipped when `out/` is absent — the CI web job does not run forge, so the skip is deliberate). No zero-diff check existed in the repo; this test is its replacement. |
| `vitest.config.ts`                                                              | `components/**` added to `include` + `esbuild: { jsx: 'automatic' }` (matches the Next.js runtime; without it component tests fail with "React is not defined").                                                                                                              |

### 2.3 Test stack + E2E

- `packages/contracts/script/DeployLocalTestStack.s.sol` (the only
  contracts-side file touched by the frontend worker): a second
  verifier (test key `0xA11CE6`) is granted `VERIFIER_ROLE`, quest
  q3 ("Post on X") is created with threshold 2, alice completes q3
  with 2 signatures, and `verifier2` is written to the deployment
  JSON.
- Wallet E2E attestation flow is now threshold-2 end-to-end in the
  browser: both verifiers sign the same digest, the form shows
  "requires 2 verifier signatures", both "(verified verifier ✓)"
  markers appear, q3 completes on-chain, bob's points reach 150.
- Anvil integration submits a threshold-2 pair through the real
  `checkAttestations()` and observes 2 `AttestationUsed` events
  (one per signer).

### 2.4 Documentation + SOP

- `docs/VERIFIER_ROLE_SOP.md`: new §6.1 (multi-verifier
  coordination flow, threshold policy — 2 for rewardPoints > 1,000
  or real-world-value badges, 1 otherwise; the revoke footgun: never
  revoke until fewer than a live quest's threshold remain; grant ≥
  threshold verifiers BEFORE creating a threshold quest;
  per-signer monitoring). §8 notes the new revert errors.
- `docs/QUEST_VALIDATION_DESIGN.md` (§2.3 + §3): attestation
  section rewritten for M-of-N.
- `agenthub-final-pretestnet/VERIFIER_SECURITY_SOP.md`: §6 sketch →
  implemented spec.
- `agenthub-final-pretestnet/FINAL_DEPLOYMENT_CHECKLIST.md` §7
  item 4: status → **IMPLEMENTED, explicitly NOT closed** (regression
  - testnet smoke still required to close).
- `docs/USER_GUIDE.md` (§4) and `README.md`: attestation copy
  updated to multi-signature.
- `THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md` was deliberately left
  untouched (historical plan document).

## 3. Regression battery — full results

Run in a fresh clean copy (`git archive` of `53849d9` + submodules,
verified identical to HEAD via `diff -r`) under Node v20.20.2 +
pnpm 9.15.4 + forge 1.9.0 + slither 0.11.6 (the CI pins). The install
was a cold `--frozen-lockfile` install (store-cached, exit 0).

| Suite                                            | Baseline (`129439a`)                       | Phase 6 (`53849d9`)                                 | Verdict  |
| ------------------------------------------------ | ------------------------------------------ | --------------------------------------------------- | -------- |
| Clean install (`--frozen-lockfile`)              | exit 0                                     | exit 0                                              | SAME     |
| Foundry tests                                    | 255/255 (19 suites)                        | **287/287 (20 suites)**                             | +32      |
| Fuzz (10,000 runs, seed 42)                      | 255/255                                    | **287/287**                                         | +32      |
| Vitest web                                       | 136 passed + 4 skipped                     | **159 passed + 5 skipped** (164)                    | +23      |
| Vitest shared                                    | 8/8                                        | **8/8**                                             | SAME     |
| TypeScript (web + shared)                        | exit 0                                     | exit 0                                              | SAME     |
| Lint (web + shared)                              | exit 0                                     | exit 0                                              | SAME     |
| Production build                                 | exit 0                                     | exit 0, 8 routes + `_not-found`, all static         | SAME     |
| Prettier + `forge fmt`                           | exit 0                                     | exit 0                                              | SAME     |
| E2E smoke                                        | 23/23                                      | **23/23**, 0 console errors                         | SAME     |
| Wallet E2E                                       | 25/25                                      | **26/26**, 0 console errors                         | +1 check |
| Anvil integration                                | 27/27 + 4/4                                | **30/30 + 5/5**                                     | +3 +1    |
| Slither (`--exclude-dependencies --fail-medium`) | exit 0, 12 results                         | exit 0, app-only set **identical** (4 Low + 7 Info) | SAME     |
| OSV dependency audit                             | 7 (0C/0H/6M/1L)                            | **7 (0C/0H/6M/1L)**, set identical                  | SAME     |
| Gitleaks (full history)                          | 0 leaks                                    | **0 leaks** (97 commits)                            | SAME     |
| Opcode scan (Cancun-only)                        | 1× MCOPY in Reputation + 1× in Achievement | **0 in all 4 contracts** (via-IR)                   | IMPROVED |

**Zero regressions. Zero tests deleted. Zero security assertions
weakened.** The 5 skipped web tests are the 4 pre-existing baseline
skips plus the anvil test file, which runs only under the anvil
runner by design.

### New tests (55 total — above the required 18–22 Foundry + 8–10 frontend)

**Foundry — 32 new tests in `test/ThresholdAttestation.t.sol`:**
happy path (threshold 1/2/3 complete; extra signatures beyond M;
threshold stored); rejects (1 sig for T2; 2 sigs for T3; empty array;

> 5 signatures; 5-signature boundary accepted; duplicate signer; 2
> valid + 1 unauthorized; malformed signature in array; signatures for
> a different nonce / quest / deadline); bounds (threshold 0 and 4
> revert, including for CheckIn quests); nonce (consumed exactly once +
> replay reverts; failed completion on a full quest does not burn the
> nonce); events (one `AttestationUsed` per signer, via `recordLogs`);
> revocation (revoked 2nd verifier invalidates the pair, re-grant
> restores it); deadline (expired / >7 days with M signatures);
> immutability (no setter; `deactivateQuest` does not change the
> threshold); fuzz ×2 (signature arrays from {v1, v2, attacker} never
> complete T3; random bytes never complete T2); gas ×4 (§4).

**Frontend — 23 new tests:** 8 unit tests for `checkAttestations`
(valid pair, duplicate pair, malformed, insufficient count, >5,
threshold-3 triple, and more); 4 hook multi-sig tests + 1 multi-sig
write test; 4 `AttestationForm` component tests; 5 ABI parity tests;
1 `mapQuest` threshold-mapping test.

**Existing tests updated mechanically only:** all pre-existing
`createQuest` / `completeQuestWithAttestation` call sites (Foundry
suites, anvil scripts, E2E) were updated to the new call shapes with
assertions unchanged. `test/EconomicAttack.t.sol` was restructured
for via-IR (helper extraction + `vm.getBlockTimestamp()` in a warp
loop — via-IR hoists `block.timestamp` across `vm.warp`); all 6 tests
pass with identical assertions.

## 4. Gas benchmark — additional cost per signature

Method: `gasleft()` around the completion call
(`test/ThresholdAttestation.t.sol`, `testGas_*`), identical quests
(OneTime, Attested, 100 points, no badge, 30-day window, unlimited)
differing ONLY in threshold, fresh account per threshold (cold
storage throughout). Solc 0.8.24, via-IR, optimizer 200. Full
methodology + cross-check in
`test-results/gas-benchmark-threshold.md`.

| Threshold | Signatures | Completion gas | Marginal / extra sig |
| --------- | ---------- | -------------- | -------------------- |
| 1         | 1          | **242,735**    | —                    |
| 2         | 2          | **253,867**    | **11,132**           |
| 3         | 3          | **265,221**    | **11,354**           |

Average marginal cost: **~11,243 gas per extra signature**.
3-of-3 overhead vs 1-of-1: **+22,486 gas (+9.3%)**. Cross-check
inside `testGas_MarginalCostPerExtraSignature` agrees within 8 gas.

This is higher than the plan's ~3k/signature estimate (which counted
only ecrecover + calldata). The measured breakdown per extra
signature is roughly: ecrecover 3,000 + cold role `SLOAD` 2,100 +
`AttestationUsed` event ~2,000 + calldata/decode ~2,000 + loop
overhead ~2,000. It is NOT a blocker: the absolute cost is small
(a 3-of-3 completion is ~0.000265 BNB at 1 gwei), and the absolute
completion gas (~243–265k) is dominated by cold storage writes that
exist with or without threshold. No gas bound in the codebase is
breached; the gas tests assert each completion stays under 300,000.

## 5. Deviations from the plan + findings

### 5.1 via-IR is REQUIRED (biggest deviation)

The 11-parameter `createQuest` CANNOT compile under solc 0.8.24's
legacy code generator ("stack too deep, dataEnd 1 slot"), even with
an empty function body — the failure is in the ABI decoder, so no
body restructure can fix it. Proven by bisection (removing the 11th
parameter restores legacy compilation; a delegate-to-internal
workaround fails because the optimizer inlines it back).
`foundry.toml` now sets `via_ir = true`, with the reason documented
in the file.

Consequences, all verified in this phase:

- **Bytecode of ALL contracts changed.** No deployment exists yet
  (testnet or mainnet), so there is no migration concern.
- **Full build takes ~5 minutes** (303s measured in the clean
  copy; ~8s under legacy codegen per the implementer's
  measurement). CI timeouts (15–30 min per job) still cover it;
  the local battery absorbed it.
- **The Phase 5 opcode scan is superseded — re-run in this phase
  (§3):** under via-IR the optimizer emits **zero Cancun-only
  opcodes** in all four contracts (previously 1× MCOPY in Reputation
  - 1× in Achievement under legacy codegen). Disassembly verified
    non-empty (7,748 lines for QuestManager). The Phase 5 finding F3
    (the `foundry.toml` comment claiming "no Cancun-only opcodes" was
    outdated) is now MOOT — the comment is true again. Cancun
    compatibility is now trivially satisfied.
- The `createQuest` body uses field-by-field assignment (not a
  struct literal) and `_verifyAttestations` is split into three
  internal functions (`_attestationDigest`,
  `_recoverAttestationSigner`) for stack depth; behavior is
  identical to the plan's sketch.

### 5.2 Fuzz tests: `vm.assume` rejection budget (found + fixed in regression)

The two new fuzz tests used `vm.assume` to filter array lengths
(1–5). They pass at the default 256 runs but FAIL at 10,000 runs,
seed 42: "`vm.assume` rejected too many inputs (65536 allowed)".
This is a test-design flaw, not a contract bug — the fuzzer
generates arbitrary array lengths, and most inputs are rejected.
Fixed in `53849d9` by capping the array length deterministically
(truncate to 5, default to 1 when empty) with no `vm.assume` — the
tested property holds for any length, so the fix preserves the
tests' meaning. Re-verified: full fuzz battery 287/287 at 10k runs,
seed 42. Lesson recorded in the test file: never length-filter
fuzzed arrays with `vm.assume`.

### 5.3 Smaller deviations

- `MAX_ATTESTATION_SIGNATURES` lives in `QuestManager.sol`, not the
  interface (the task specification overruled the plan's §3 table).
- New error `TooManyAttestationSignatures(uint256)` for >5 (the
  plan did not name an error for this case;
  `InsufficientAttestations` does not fit).
- New constants `MIN_ATTESTATION_THRESHOLD` / `MAX_ATTESTATION_THRESHOLD`
  (1/3) document the policy.
- No zero-diff ABI check existed in the repo (the plan assumed one);
  replaced by the new ABI parity test (§2.2).
- The `foundry.toml` comment about Cancun opcodes is now accurate
  again (see §5.1) — no comment change was needed.

### 5.4 Observations (not blockers)

- **Slither without `--exclude-dependencies` reports 44 findings
  including 1 High + 8 Medium — ALL in OpenZeppelin `lib/`
  (`Math.sol`, `ECDSA.sol`, etc.), pre-existing dependency code.**
  The project's CI gate is `--exclude-dependencies --fail-medium`
  by design, and it passes (exit 0, app-only set identical to
  baseline). The dependency findings are OpenZeppelin's, not
  AGENTHUB's, and are out of scope for this phase — but they are
  recorded here honestly so no one mistakes the raw 44 for a
  regression.
- **Historical E2E logs overwritten:** the frontend worker refreshed
  `agenthub-final-pretestnet/logs/phase7-anvil-integration.log` and
  `agenthub-final-release/logs/phase-f-wallet-e2e.log` with the new
  Phase 6 runs (the runner scripts write to hardcoded paths). The
  old logs survive in git history; the new logs are the current
  green runs. Future phases should copy runner output into their
  own folder instead of letting the hardcoded paths overwrite
  phase evidence (this phase's own logs live in
  `agenthub-phase6-threshold/logs/`).
- `forge build` emits pre-existing lint warnings (`block-timestamp`,
  `reentrancy-no-eth`, one `environment-read-across-mutation` help
  from the restructured `EconomicAttack` test). Warnings, not
  errors; the build exits 0 and CI does not fail on them.

## 6. Residual risks

1. **Threshold does not make attestations true.** It stops ONE
   compromised verifier; M colluding verifiers still succeed, and
   no threshold makes any verifier honest. Pause + SOP monitoring
   remain the real backstop (unchanged from the plan).
2. **Threshold footgun (plan §2.2):** AccessControl cannot enumerate
   role holders, so the contract cannot check threshold ≤ live
   verifier count. Revoking verifiers below a live quest's threshold
   bricks that quest. Mitigation is SOP-only (grant ≥ threshold
   before creating; never revoke below the highest live threshold
   without deactivating affected quests first; the admin can always
   deactivate a bricked quest and recreate it at threshold 1).
3. **Coordination UX:** collecting M signatures out-of-band is
   slower and can fail (one verifier offline). The nonce moves on
   ANY attested completion by the account, so a half-collected set
   goes stale if the user completes another attested quest first —
   the form re-verifies immediately before submit and shows a stale
   state.
4. **ABI break:** any external integrator calling the old
   single-`bytes` function breaks at the next deploy. No mainnet
   deployment exists yet, so the blast radius is testnet-only.
5. **via-IR build time (~5 min)** slows local iteration and CI
   marginally; no timeout is breached.
6. **Verifier set size (plan §8, decision 3):** threshold is
   meaningless with a 1-person verifier set. The set must grow to ≥
   3 before any threshold-2 quest is created on mainnet — an
   operational decision for the team, not a code change.
7. **Real wallet-app compatibility (O4) and WalletConnect (F6)**
   remain open from the previous validation — untouched by this
   phase, closing during live testnet validation.

## 7. R-010 acceptance criteria — status

From `THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md` §9:

| Criterion                                                                                                                                     | Status                                                                                                                                                      |
| --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Threshold implementation merged with all new tests green and the full regression battery green (Foundry + Vitest + E2E + Slither)             | **MET** — §3, all suites green from a clean install                                                                                                         |
| Testnet smoke: threshold-1 and threshold-2 quests created and completed on the live testnet; duplicate/insufficient reverts observed on-chain | **OPEN — blocked on the 8 deployment inputs from the user** (tBNB, deployer key, Safe, creator, verifier, pauser, BscScan key, explicit broadcast approval) |
| SOP §6 updated from sketch to implemented spec; checklist §7 item 4 re-verified and closed                                                    | **PARTLY MET** — SOP updated (§2.4); checklist item 4 is IMPLEMENTED but explicitly NOT closed (it closes only after the testnet smoke)                     |
| Diff included in the commissioned external review (R-012)                                                                                     | **OPEN** — no review commissioned yet                                                                                                                       |
| At least 3 verifiers granted before the first threshold-2 quest is created on mainnet                                                         | **OPEN** — operational, at deploy time                                                                                                                      |

## 8. Evidence index + commits

**Reports in `agenthub-phase6-threshold/`:** this report;
`test-results/gas-benchmark-threshold.md` (gas methodology +
numbers); `test-results/osv-audit-phase6.json`;
`test-results/slither-phase6.json` (full 44-finding JSON — see §5.4
for why the gate uses the app-only subset).

**Logs in `agenthub-phase6-threshold/logs/` (14 files):**
`regression-clean-install.log`, `regression-forge-build.log`,
`regression-forge-test.log`, `regression-forge-fuzz.log`,
`regression-js.log` (shared + web: typecheck, lint, vitest, build,
prettier, forge fmt), `regression-e2e.log` (combined),
`regression-e2e-smoke.log`, `regression-wallet-e2e.log`,
`regression-anvil-integration.log`, `regression-slither.log`,
`regression-slither-json.log`, `regression-gitleaks.log`,
`regression-osv.log`, `regression-opcode-scan.log`.

**Commits (`129439a` → `53849d9`, 9 commits):**

- `48e80a5` feat(phase-6): threshold attestation M-of-N in
  QuestManager (R-010)
- `aea064f` test(phase-6): threshold attestation suite — 32 tests
  incl. fuzz + gas
- `c441749` feat(phase-6): regenerate QuestManager ABI for
  threshold attestation (R-010)
- `66eb62b` feat(phase-6): multi-signature attestation frontend
  (R-010)
- `0c90e66` test(phase-6): threshold attestation frontend tests
  (R-010)
- `baeb483` test(phase-6): threshold-2 E2E — second verifier in the
  test stack (R-010)
- `575c508` docs(phase-6): threshold attestation SOP + design +
  checklist (R-010)
- `2d16509` test(phase-6): refresh anvil + wallet E2E run logs
  (threshold-2 green)
- `53849d9` fix(phase-6): replace vm.assume length filter in
  threshold fuzz tests (10k-run rejection budget)

**Final verdict: CONDITIONAL GO for live BNB Testnet validation,
NO-GO for mainnet. R-010: IMPLEMENTED, closure pending the live
testnet smoke test.** No deployment is authorized by this report —
only the user's explicit approval for a specific broadcast
authorizes one.
