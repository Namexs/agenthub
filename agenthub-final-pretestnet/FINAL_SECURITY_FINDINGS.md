# AGENTHUB — Final Security Findings (Phase 9)

Final security regression for the pre-testnet remediation. Baseline:
HEAD `c5bed05` (218 Foundry tests). This review covers HEAD `1f873c2`
(Phase 4 commit) — the code as it stands after Phases 1, 2, 5, 6, 7, 8,
and 4. No new exploitable vulnerability was found in this review. The
open items are the dependency advisories from Phase 4 (not exploitable
in this deployment) plus documented residual risks. Nothing in this
document is a claim of absolute security.

## 1. Regression battery (all green)

| Command                                                    | Result                                      | Log                                                                    |
| ---------------------------------------------------------- | ------------------------------------------- | ---------------------------------------------------------------------- |
| `forge clean && forge build`                               | PASS                                        | `logs/phase9-forge.log`                                                |
| `forge test -vvv`                                          | **255/255**, 0 failed                       | `logs/phase9-forge.log` (tail; full output in `phase9-forge-full.log`) |
| `forge test` (full output saved)                           | **255/255**, 0 failed, 19 suites            | `logs/phase9-forge-full.log`                                           |
| `forge test --fuzz-runs 10000` (random seed)               | **255/255**, 0 failed                       | `logs/phase9-fuzz.log`                                                 |
| `forge test --fuzz-runs 10000 --fuzz-seed 42` (Phase 4)    | **255/255**, 0 failed                       | `logs/phase4-ci-fuzz.log`                                              |
| `forge fmt --check`                                        | PASS                                        | `logs/phase9-web.log` (via format job)                                 |
| `slither . --exclude-dependencies --fail-medium` (Phase 4) | exit 0 — 0 High/Medium                      | `logs/phase4-ci-slither.log`                                           |
| `slither . --exclude-dependencies --json`                  | 12 results, 4 Low + 8 Info, `success: true` | `logs/phase9-slither.json`, `logs/phase9-slither.log`                  |
| web: lint, typecheck, vitest, build                        | PASS — 136 vitest + 4 skipped, build 11/11  | `logs/phase9-web.log`                                                  |
| shared: lint, typecheck, vitest                            | PASS — 8/8                                  | `logs/phase9-web.log`                                                  |
| `pnpm format:check`                                        | PASS after 1 fix (see §1.1)                 | `logs/phase9-web.log`                                                  |

**Failing tests: none.** Every suite in the battery passed. No test
was changed, weakened, or deleted to make anything pass in this phase.

### 1.1 The one failure during the battery (fixed, not hidden)

The first `pnpm format:check` run failed on one file:
`agenthub-final-pretestnet/logs/phase4-osv-audit.json` (the OSV audit
evidence JSON is machine-written and not prettier-formatted). Fix:
added `agenthub-final-pretestnet/logs/` to `.prettierignore`, per the
repo's standing principle that evidence logs stay byte-identical to
tool output (the same reason `security-review-package/logs/` and the
frozen evidence packages are ignored). Re-run: all matched files pass.
The log preserves the failure and the fix
(`logs/phase9-web.log`).

### 1.2 Slither `--json` exit 255 (teardown quirk, not an analysis failure)

The `slither --json` run exited 255 — but the analysis itself
completed: the JSON is valid (`success: true`, 12 detectors) and the
text log shows the full "12 result(s) found" summary. The non-zero
exit comes from crytic-compile's teardown, which runs `forge clean`

- a `forge build --build-info` rebuild after the analysis; that
  teardown step fails on this VM. The same analysis without `--json`
  (Phase 4, `--fail-medium`) exited 0. A `forge build` run immediately
  after confirmed the build tree is healthy. The exit code is recorded
  honestly here; it does not change the finding count.

### 1.3 Transient test failure — still unreproduced

The unidentified transient failure (1 failing test in 1 of 5 runs
during the user-review remediation; cause never found) has **not
recurred in 10 additional full-suite runs** across Phases 1–9
(including 3 fuzz-10k runs and the `-vvv` run). Total since the
incident: ~18 consecutive green full runs. It remains documented as
residual risk R-011 with the mitigations already in place (pinned
fuzz seed in the CI fuzz job, full logs saved per run).

## 2. The 12-category review

Each category was re-checked against the CURRENT code (all four
contracts + deploy script + SafeValidation), not just against older
reports. Verdicts:

### 2.1 Reentrancy — PASS

- Both completion entry points are `nonReentrant`
  (`QuestManager.completeQuest` L180, `completeQuestWithAttestation`
  L195); `Achievement.issue` is `nonReentrant` (L62).
- Checks-effects-interactions throughout `_completeQuest` (L241):
  all state changes precede the `reputation.addPoints` /
  `achievement.issue` calls (L283–288).
- Untrusted calls are STATICCALLs (validator L344, Agent ID
  `AgentGate.isAgentHolder` L72, staticcall L75–76) — a state-changing callee is
  reverted at the EVM level.
- `Achievement` uses `_mint`, not `_safeMint` — no
  `onERC721Received` callback at mint time.
- Regression tests: `AttackSimulation.test_ReentrancyViaBadgeCallbackImpossible`,
  `test_MintCallbackCompletionBoundedToOne`,
  `MaliciousValidators` (reentrant validator), `ValidatorRegistryTest`
  (state-changing validator blocked, counter stays 0).

### 2.2 Access control — PASS

- Every sensitive function is role-gated (see `docs/ROLE_MATRIX.md`):
  createQuest (QUEST_CREATOR_ROLE), approve/revokeValidator
  (DEFAULT_ADMIN_ROLE = timelock), emergencyRevokeValidator
  (PAUSER_ROLE), pause (PAUSER_ROLE), unpause (DEFAULT_ADMIN_ROLE),
  addPoints (SCORE_SOURCE_ROLE = QuestManager), issue (ISSUER_ROLE =
  QuestManager), defineBadge (BADGE_MANAGER_ROLE = multisig).
- Constructors grant ONLY DEFAULT_ADMIN_ROLE; the deploy script
  grants operational roles explicitly, moves admin to the 2-day
  timelock, and makes the deployer renounce everything
  (`DeployAgentHub.s.sol` L218–233, verified by `_verifyWiring`).
- Regression tests: `AccessControl.t.sol` (11 role-matrix tests),
  `PauserRole.t.sol` (9 tests incl. deployer-has-no-role,
  timelock-delay-enforced, revocation).

### 2.3 Signature replay — PASS

- EIP-712 domain binds chainId + verifying contract (OZ EIP712,
  fork-aware); struct binds account + questId + nonce + deadline
  (`QuestManager._verifyAttestation` L212).
- Per-account nonce consumed on success; a failed completion reverts
  the whole tx, so the nonce is not burned (`Attestation.t.sol`:
  nonce-not-burned-on-failure).
- `ECDSA.tryRecover` rejects malleable signatures; deadline bounded
  (expired rejected, > 7 days rejected); VERIFIER_ROLE checked at
  completion time, so revocation invalidates outstanding attestations.
- Phase 6 audited 15 checks, 0 vulnerabilities. Regression tests:
  `Attestation.t.sol` (24) + `VerifierSecurity.t.sol` (5, incl.
  front-running and cross-account submission).

### 2.4 Unauthorized quest completion — PASS

- `_completeQuest` requires Agent ID holder status via
  `gate.requireAgentHolder` (L242); Attested quests reject bare
  `completeQuest` (L185); OnChain quests require an approved
  validator returning true (L270–276); duplicate/cooldown/cap/window
  checks all precede effects.
- Regression tests: `QuestManager.t.sol` (40),
  `Invariant.invariant_NonHolderEarnsNothing`,
  `AttackSimulation.test_DelegatedCompletionImpossible`,
  `EconomicAttack.test_SybilWithoutAgentIdsEarnsNothing`.

### 2.5 Fake Agent ID — PASS (mainnet locked; testnet by design)

- `AgentGate` constructor enforces `OFFICIAL_AGENT_ID`
  (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) on chain 56
  (`AgentGate.sol` L23) and rejects other chains (allowlist
  {56, 97, 31337}); `expectedChainId` must equal `block.chainid`.
- `isAgentHolder` fails closed (false on wrong chain, zero account,
  call failure, short returndata).
- Testnet/local accept any contract (MockAgentId) BY DESIGN — the
  deployer must deploy the right mock; that trust is procedural
  (DEPLOYMENT_PLAN.md), not on-chain. Recorded as residual R-004.
- Regression tests: `AgentGate.t.sol` (18),
  `AgentGateMainnet.t.sol` (10),
  `AttackSimulation.test_MaliciousAgentIdFailsClosed`.

### 2.6 Fake Safe — PASS (Phase 1)

- `SafeValidation.validate` checks: chain ∈ {56, 97}; code exists;
  threshold ≥ 2 and ≤ owners; `masterCopy()` is a canonical
  singleton (v1.4.1 `0x41675C…`, v1.3.0 `0xd9Db27…`); proxy
  codehash is a canonical proxy codehash (closes masterCopy
  spoofing); `VERSION()` ∈ {"1.3.0", "1.4.1"}.
- Local path (chain 31337 only) validates against
  operator-supplied values. Manual pre-deploy verification procedure
  in DEPLOYMENT_PLAN.md §5.1 (required — the check proves
  genuineness, not identity; residual R-003).
- Regression tests: `SafeValidation.t.sol` (17, incl. fake
  interface, spoof singleton, threshold 1, threshold > owners,
  EOA, zero address, wrong chain).

### 2.7 Malicious validator — PASS (Phase 5)

- Registry with mandatory metadata; zero/code-less rejected;
  revocation checked at creation AND completion (immediate effect);
  emergency revocation via PAUSER_ROLE (no timelock); re-approval
  requires admin.
- `_validateOnChain` uses STATICCALL + strict returndata check
  (exactly 32 bytes, word 0 or 1) — a state-changing or reentering
  validator is reverted at the EVM level; a reverting validator
  fails closed (`ValidatorCallFailed`); malformed returndata reverts
  (`InvalidValidatorReturndata`).
- Residual R-002: a validator returning the WRONG ANSWER
  (always-true) cannot be detected on-chain — approval is the trust
  decision, gated by the admin (timelock).
- Regression tests: `ValidatorRegistry.t.sol` (11),
  `Validator.t.sol` (14), `ValidatorAllowlist.t.sol` (14).

### 2.8 Reward manipulation — PASS (with residual R-001)

- `MAX_REWARD_POINTS` = 10,000 enforced at creation
  (`QuestManager` L139); no function changes rewards after creation;
  completions are counted and capped (`maxCompletions`).
- A compromised QUEST_CREATOR_ROLE could create many max-reward
  quests (points inflation until detected). Mitigations: the role is
  granted via timelock; creations are public on-chain events; the
  admin can deactivate quests and the multisig can pause. Points
  have no monetary value (not redeemable), which bounds the impact.
- Regression tests: `EconomicAttack.test_CreatorCannotExceedRewardCap`,
  `test_MaxRewardQuestEmissionBounded`,
  `test_CappedQuestTotalEmissionBounded`,
  `Invariant.invariant_CompletionsMatchAndRespectCap`.

### 2.9 Reputation manipulation — PASS

- There is deliberately NO admin score function. Points increase
  ONLY via `Reputation.addPoints`, restricted to SCORE_SOURCE_ROLE
  (the QuestManager contract), capped at 10,000/event, pausable,
  and every change emits `PointsAdded` with the causing quest id.
- The only manipulation path is via quest creation (§2.8), not via
  direct score writes.
- Regression tests: `Reputation.t.sol` (15),
  `Invariant.invariant_PointsMatchGhost`,
  `Invariant.invariant_EventsMatchGhost`,
  `AccessControl.test_AddPointsRoleMatrix`.

### 2.10 Duplicate badge — PASS

- `Achievement.issue` reverts when `_hasBadge[account][badgeId]`
  (L71); `_completeQuest` pre-checks `hasBadge` before issuing
  (L287). One badge per (account, badgeId), enforced on-chain.
- Soulbound by construction: `_update` reverts transfers (L103),
  `approve`/`setApprovalForAll` revert (L110/L114).
- Regression tests: `Achievement.t.sol` (19),
  `Invariant.invariant_BadgesMatchGhost`.

### 2.11 Denial of service — PASS (with notes)

- No unbounded loops: `Reputation.level` iterates at most 5
  thresholds; no function iterates over quests, users, or badges.
- Bounded strings at creation (title ≤ 128 bytes, description ≤
  1024 bytes); no function has unbounded gas.
- Creation is role-gated (no public spam vector); each creation
  costs the creator gas.
- `AgentGate.isAgentHolder` fails closed instead of reverting, so a
  misbehaving Agent ID contract cannot DoS integrators.
- Notes (not vulnerabilities): (a) the FRONTEND reads all quests
  via multicall — a very large quest count would slow page loads
  (off-chain; residual R-005, pagination is future work); (b)
  `deactivateQuest` has no reactivation — an admin error is
  permanent for that quest (re-create instead; residual R-008);
  (c) unpause requires the 2-day timelock (slow recovery by design;
  residual R-009).
- Regression tests: `AttackSimulation.test_GasExhaustionIsAtomic`,
  `test_DownstreamRevertIsAtomic`.

### 2.12 Dependency misconfiguration — PASS (with documented residuals)

- Constructors check dependencies are non-zero AND have code
  (`QuestManager` L103–110, `AgentGate` L36–37).
- AgentGate mainnet lock (§2.5); frontend M5 chain↔Agent ID
  consistency checks (`lib/env.ts`, 17 env tests); SafeValidation
  (§2.6); deploy script `_verifyWiring` checks every role + the
  timelock configuration on-chain.
- Residual R-004: a code-length check proves an address IS a
  contract, not that it is the RIGHT contract — deploying the wrong
  (but valid) Reputation/Achievement instance cannot be detected
  on-chain. Control: the deployment verification steps in
  DEPLOYMENT_PLAN.md + the deploy script's wiring assertions.
- JS dependencies: see §4 (OSV audit — 76 findings, none
  exploitable in this deployment; CI audit job will fail until
  upgrades land).

## 3. Slither inventory (12 results, 0 High/Medium)

Slither 0.11.6, `slither . --exclude-dependencies`, 37 contracts,
102 detectors. Full JSON: `logs/phase9-slither.json`.

| #    | Detector                | Impact | Sites                                                                                                                  | Disposition                                                                                                                                   |
| ---- | ----------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1–4  | `timestamp`             | Low    | `QuestManager` createQuest L140, `_verifyAttestation` L213–214, `_completeQuest` L244–245/255, `nextCompletionAt` L399 | **Accepted (SEC-004).** All windows are hours/days; BSC timestamp manipulation is seconds. Immaterial.                                        |
| 5–7  | `assembly`              | Info   | `AgentGate.isAgentHolder` L79–81, `QuestManager._validateOnChain` L350–352, `TokenBalanceValidator.validate` L51–53    | **Intentional.** Minimal returndata reads (first 32-byte word) after length checks. Reviewed; correct.                                        |
| 8–10 | `low-level-calls`       | Info   | Same 3 staticcall sites as above                                                                                       | **Intentional.** All three are STATICCALLs with success + returndata checks, fail-closed. The Phase 5 hardening IS low-level calls by design. |
| 11   | `pragma`                | Info   | 2 Solidity versions in the tree (project `^0.8.24`, OZ `^0.8.20`)                                                      | **Expected.** Compiler is pinned (`solc_version = "0.8.24"`, `evm_version = "cancun"` in foundry.toml — M2 fixed).                            |
| 12   | `cyclomatic-complexity` | Info   | `QuestManager._completeQuest` (complexity 14)                                                                          | **Accepted.** One function with many sequential checks; splitting it would hurt auditability. No action.                                      |

Count change 10 → 12 vs the post-remediation baseline: the Phase 5
staticcall hardening added the 2 new sites
(`_validateOnChain`, `TokenBalanceValidator.validate`), each flagged
once by `assembly` and once by `low-level-calls`. The new findings
are the hardening itself, not regressions.

## 4. Dependency findings (carried from Phase 4 — OSV audit)

920 packages queried; **76 findings: 8 CRITICAL, 21 HIGH,
41 MODERATE, 6 LOW** (`logs/phase4-osv-audit.json`,
`scripts/osv-audit.mjs`). Full per-finding table in
`CI_EVIDENCE.md` §6. Summary by item:

| ID      | Severity                               | Finding                                                                                                                                                                                                                             | Exploitability here                                                                         | Remediation                                                                                                                                   |
| ------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| DEP-001 | High (finding) / None (exploitability) | Next.js 14.2.18: 13 HIGH/CRITICAL incl. 3 CRITICAL RCEs (Image Optimization SVG/AVIF, Windows) + CVE-2025-29927 middleware bypass                                                                                                   | None: static export, no image optimization, no middleware, no Server Actions, Linux hosting | Patch to 14.2.35 now (fixes CVE-2025-29927 + 2 DoS); major upgrade to 15.5.28+/16.4.1+ before any serverful feature. Pre-mainnet requirement. |
| DEP-002 | High / None                            | vitest 2.1.9 + 3.2.4 CRITICAL UI RCE; tinypool 1.1.1 CRITICAL prototype-pollution→RCE (×2)                                                                                                                                          | None: Vitest UI never runs (`vitest run` only); worker options are repo-controlled          | `vitest@3.2.6` (pulls fixed tinypool).                                                                                                        |
| DEP-003 | High / None                            | postcss 8.4.31/47 (file read, traversal), zod 3.23.8 (memory exhaustion), glob 10.3.10 (CLI injection), ws 8.18.0 (DoS), vite 5.4.21 (Windows bypass), decode-uri-component 0.2.2 (ReDoS), @coinbase/wallet-sdk 4.2.1 (undisclosed) | None: build/dev-time only, or inputs are repo-controlled                                    | Patch upgrades (`postcss@8.5.18`, `ws@8.21.0`, etc.); zod 4.x is a major.                                                                     |

**Consequence:** the CI `audit` job (`pnpm audit
--audit-level=high`) will FAIL on its first real run. The job is
correctly strict; the tree is not clean. No upgrade was performed
in this remediation: every upgrade needs a lockfile regeneration,
which is impossible on this VM, and a Next.js major upgrade is out
of scope. Upgrades + a re-run of `scripts/osv-audit.mjs` are a
pre-mainnet requirement (testnet demo is unaffected — see
exploitability column).

## 5. Findings fixed during this remediation (summary)

Full detail lives in the per-phase documents; this table is the
index, not a re-derivation.

| Finding                                                                                        | Severity           | Phase | Fix                                                                                                                  | Regression test                          |
| ---------------------------------------------------------------------------------------------- | ------------------ | ----- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| SafeValidation trusted any threshold/owners interface (fake Safe)                              | High               | 1     | Canonical singleton + proxy codehash + VERSION checks; local path restricted to 31337; manual verification procedure | `SafeValidation.t.sol` (17)              |
| PAUSER_ROLE default was an arbitrary deployer-chosen address; docs disagreed                   | Medium             | 2     | Default = verified admin multisig; role matrix; docs aligned                                                         | `PauserRole.t.sol` (9)                   |
| Validator allowlist was a bool map; validator calls were normal calls (state changes possible) | Medium             | 5     | Registry with metadata; STATICCALL + returndata enforcement; emergency revocation                                    | `ValidatorRegistry.t.sol` (11)           |
| AttestationUsed event did not attribute the signer (monitoring blind spot)                     | Low                | 6     | Signer added as indexed topic                                                                                        | `VerifierSecurity.t.sol` (5)             |
| Frontend showed static sample data as if live                                                  | Medium (integrity) | 7     | Real on-chain integration (wagmi/viem), honest empty/error states                                                    | Anvil 27/27 + 4/4; vitest 136; E2E 23/23 |
| CI never ran vitest / fuzz / Slither / secret scanning; Node unpinned                          | Low                | 4     | 8-job workflow, pinned toolchains, gitleaks + `.gitleaks.toml`                                                       | `CI_EVIDENCE.md`                         |
| `computeLevel` was 0-based (contract levels are 1-based)                                       | Low                | 7     | Fixed to 1-based; anvil test asserts against contract `level()`                                                      | `lib/events.test.ts`, anvil integration  |
| Gitleaks config silently disabled all rules (first version)                                    | Medium (process)   | 4     | `[extend] useDefault = true`; negative control test                                                                  | `logs/phase4-ci-secrets-control.log`     |

Findings fixed in EARLIER phases (before this remediation) are in
`docs/SECURITY_FINDINGS.md` (SEC-001 High, SEC-002 Medium, SEC-003
Low) and `docs/REGRESSION_RESULTS.md` (user-review findings 1–4);
they were re-verified by the passing regression battery, not
re-audited here.

## 6. Open findings + residual risks

| ID      | Severity | Title                                                   | Exploit scenario                                                                                                           | Impact                                                                  | Remediation                                                                                                    | Status                |
| ------- | -------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------- |
| DEP-001 | High     | Next.js 14.2.18 advisories (13)                         | N/A in this deployment (static site) — activates only if image optimization / middleware / Server Actions are ever enabled | RCE / auth bypass IF those features are enabled                         | Upgrade path (§4); re-audit after                                                                              | OPEN — pre-mainnet    |
| DEP-002 | High     | vitest/tinypool CRITICALs                               | N/A — Vitest UI never runs                                                                                                 | RCE on a dev machine IF the UI server is started                        | `vitest@3.2.6`                                                                                                 | OPEN — pre-mainnet    |
| DEP-003 | High     | postcss/zod/glob/ws/vite/coinbase HIGHs                 | N/A — build/dev-time, repo-controlled inputs                                                                               | Varies (see §4)                                                         | Patch upgrades                                                                                                 | OPEN — pre-mainnet    |
| R-001   | Low      | QUEST_CREATOR_ROLE compromise → points inflation        | Compromised creator key creates many 10k-point quests; holders farm                                                        | Reputation inflation (points have no monetary value)                    | Creator role on multisig; monitor `QuestCreated`; deactivate + pause on abuse                                  | ACCEPTED (monitored)  |
| R-002   | Low      | Always-true validator returns the wrong answer          | Malicious/buggy validator approved by a compromised admin approves everything                                              | Unearned completions for its quests                                     | Review-before-approval (registry metadata); monitor completions per validator; emergency revocation            | ACCEPTED (process)    |
| R-003   | Info     | Safe check proves genuineness, not identity             | Deployer validates a genuine Safe that is NOT the intended multisig (wrong owners)                                         | Admin powers go to the wrong Safe                                       | Manual verification procedure (DEPLOYMENT_PLAN §5.1) — REQUIRED before deploy                                  | OPEN — procedural     |
| R-004   | Info     | Constructor checks prove code exists, not identity      | Deployer wires the wrong (but valid) contract instance                                                                     | Wrong trust root                                                        | Deployment verification steps + `_verifyWiring`                                                                | OPEN — procedural     |
| R-005   | Info     | Frontend reads ALL quests via multicall                 | Quest count grows very large (thousands)                                                                                   | Slow page loads (off-chain UX)                                          | Pagination (future frontend work)                                                                              | OPEN — future         |
| R-006   | Low      | Timestamp dependence (Slither ×4)                       | BSC validator shifts block.timestamp by seconds                                                                            | Windows shift by seconds (immaterial vs hours/days)                     | None — accepted (SEC-004)                                                                                      | ACCEPTED              |
| R-007   | Info     | `hasCompleted` stays true forever for repeatable quests | — (semantic quirk, documented in code)                                                                                     | A reader could misread "completed" as "cannot complete again"           | None — frontend checks questType first                                                                         | ACCEPTED (documented) |
| R-008   | Info     | Deactivation is permanent (no reactivation)             | Admin deactivates the wrong quest                                                                                          | That quest is dead; must re-create                                      | Careful admin process                                                                                          | ACCEPTED              |
| R-009   | Info     | Unpause requires the 2-day timelock                     | Emergency pause, then slow recovery                                                                                        | Up to ~2 days paused (worst case ~4 days incl. verifier rotation)       | Documented in SECURITY.md emergency procedures                                                                 | ACCEPTED (by design)  |
| R-010   | Low      | Single-verifier attestation (no threshold)              | One compromised verifier key attests falsely                                                                               | Unearned Attested completions until revocation (≤ 7-day deadline bound) | M-of-N threshold attestation before any high-value attested quest goes live on mainnet (Phase 6 design sketch) | OPEN — pre-mainnet    |
| R-011   | Info     | Transient test failure, unreproduced                    | Unknown (1 in ~13 runs during remediation; 0 in ~18 runs since)                                                            | A CI run could flake once                                               | Pinned fuzz seed in CI; full logs per run                                                                      | ACCEPTED (monitored)  |
| R-012   | Info     | No external security review yet                         | —                                                                                                                          | Unknown unknowns in the contracts                                       | External review before mainnet (required by SECURITY_DEPLOYMENT_GATE.md)                                       | OPEN — pre-mainnet    |

## 7. What this review did NOT cover

- **No external audit.** This is an internal regression review by
  the remediation coordinator, not an independent audit. An external
  review remains a pre-mainnet requirement (R-012).
- **No testnet validation.** The contracts have not run on BSC
  testnet yet. Testnet-specific behavior (Cancun-opcode support on
  BSC, RPC rate limits on `getLogs`, real Safe deployment) is
  unproven until the testnet deploy + smoke test (Phase 10).
- **No wallet-connection E2E.** The injected-wallet flow (Binance
  Wallet prompt, chain switch) is covered at the hook level (mocked
  wagmi) and by code review, not by a real wallet click.
- **No re-audit of OpenZeppelin.** OZ 5.0.2 is trusted as a
  dependency (pinned via git submodule); its code was not re-audited
  here.
- **No review of the test-only mocks as production code.** Mocks
  (`MockAgentId`, `MockSafeProxy`, `CanonicalSafe`) are test-only;
  `DeployLocalTestStack.s.sol` deploys them to local anvil only.
  They must never be deployed to testnet/mainnet as if they were the
  real contracts (the deploy script refuses mocks on 56/97 by
  construction — `MockAgentId` is only deployed on 97/31337, and on
  97 it is the intended test identity).

## 8. Verdict for Phase 9

- **Regression battery: all green.** 255/255 Foundry (incl. `-vvv`
  and 2× fuzz-10k), 136 + 8 vitest, build 11/11, Slither 0
  High/Medium, format clean. Zero failing tests; zero tests changed
  to hide anything.
- **New exploitable vulnerabilities found: 0.**
- **Open items:** 3 dependency groups (DEP-001/002/003 — not
  exploitable in this deployment; CI audit job will fail until
  fixed) and 12 residual risks (all Low/Info, all with a named
  remediation or an explicit acceptance).
- The contract code is ready for **testnet staging** subject to the
  Phase 10 checklist. It is **not** ready for mainnet (external
  review, dependency upgrades, threshold attestation, and testnet
  validation are all still outstanding — see
  `FINAL_DEPLOYMENT_CHECKLIST.md`).
