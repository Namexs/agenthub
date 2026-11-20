# AGENTHUB — Security Findings

> Security engineering phase, 2026-11-19. Scope: `packages/contracts/src/`
> (AgentGate, QuestManager, Reputation, Achievement), `apps/web/lib/env.ts`,
> CI configuration. All findings below are real: each was reproduced by a
> failing test or a Slither detector run in this phase. **No finding was
> invented.** Line numbers refer to the code at commit `ee7592e` unless a
> finding says otherwise (fixed code shows the fixed lines; the
> before/after code is in `SECURITY_REMEDIATION.md`).

## Summary

| Severity      | Total | Fixed | Open (accepted)       | Closed as false positive |
| ------------- | ----- | ----- | --------------------- | ------------------------ |
| Critical      | 0     | 0     | 0                     | 0                        |
| High          | 1     | 1     | 0                     | 0                        |
| Medium        | 1     | 1     | 0                     | 0                        |
| Low           | 2     | 1     | 1 (accepted risk)     | 0                        |
| Informational | 2     | 0     | 1 (accepted group)    | 1                        |
| **Total**     | **6** | **3** | **2 (0 exploitable)** | **1**                    |

---

## SEC-001 — AgentGate reverted instead of failing closed on malformed returndata

- **Severity:** High
- **Status:** FIXED (commit `a597a2d`)
- **Contract / function:** `packages/contracts/src/AgentGate.sol` —
  `isAgentHolder(address)`, lines 44–55 (fixed code)
- **Root cause:** The original implementation used Solidity `try/catch`
  around a high-level `IERC721Balance(...).balanceOf(account)` call.
  `try/catch` catches reverts from the external call, but it does **not**
  catch ABI-decoding errors of malformed returndata: if the target returns
  fewer than 32 bytes (or garbage), the decoding itself reverts in the
  _caller_, outside the `try` region — so `isAgentHolder` reverted instead
  of returning `false`.
- **PoC (reproducible):** `test/AgentGate.t.sol` —
  `test_GarbageReturnFailsClosed`: a mock Agent ID contract whose fallback
  returns 1 byte of garbage. Against the original code the test failed
  with a revert; against the fixed code it passes (`isAgentHolder`
  returns `false`).
- **Exploit scenario / impact:** No attacker is required. Any deployment
  where the configured Agent ID address returns malformed data — a
  misconfigured address pointing at a non-ERC-721 contract, or an
  upstream change to the trusted contract — would make **every**
  `isAgentHolder` call revert. `QuestManager.completeQuest` calls
  `requireAgentHolder` first, so **all quest completions platform-wide
  would brick** (total DoS of the core function) until redeployment.
- **Exploit prerequisites:** A deployment pointing at an address whose
  `balanceOf` returndata is malformed, or a change in the trusted
  contract's return behavior. The official mainnet Agent ID contract is
  not expected to misbehave; the realistic trigger is misconfiguration.
- **Remediation:** Replaced the high-level call with a low-level
  `staticcall`, an explicit `data.length < 32` check, and an assembly
  `mload` of the first return word. `staticcall` additionally guarantees
  the trusted contract cannot change state through this call.
  See `SECURITY_REMEDIATION.md` §SEC-001 for before/after code.
- **Regression test:** `test_GarbageReturnFailsClosed` (+
  `test_RevertingAgentIdFailsClosed`, `test_MaliciousAgentIdFailsClosed`
  in `test/AttackSimulation.t.sol`).
- **Verification:** test passes; full suite green (120/120).

## SEC-002 — Constructors granted operational roles that survived admin renounce

- **Severity:** Medium
- **Status:** FIXED (commit `aadf24f`)
- **Contract / function:**
  `packages/contracts/src/QuestManager.sol` — constructor (was lines 53–54,
  now 45–57); `packages/contracts/src/Achievement.sol` — constructor (was
  lines 38–39, now 36–41)
- **Root cause:** Both constructors granted an operational role to the
  deployer in addition to `DEFAULT_ADMIN_ROLE` (`PAUSER_ROLE` in
  QuestManager, `BADGE_MANAGER_ROLE` in Achievement). The production
  setup flow renounces `DEFAULT_ADMIN_ROLE` to hand admin to a
  TimelockController — but renouncing admin does **not** renounce the
  operational roles, so the deployer EOA silently kept them forever.
- **PoC (reproducible):** `test/AccessControl.t.sol` —
  `test_PauseUnpauseRoleMatrix` failed with "next call did not revert as
  expected": the test asserted the admin could _not_ pause, but the admin
  held `PAUSER_ROLE` from construction. `test/Integration.t.sol` —
  `test_DeployerLostAdminAfterRenounce` (strengthened as the regression
  test) asserts the deployer holds **no** operational role after renounce.
- **Exploit scenario / impact:** A compromised or rogue deployer key (the
  very key the renounce flow is meant to remove from the trust model)
  could pause QuestManager indefinitely: every timelock unpause (2-day
  delay) could be followed by an immediate re-pause, griefing the
  platform into permanent downtime. It could also define arbitrary badge
  metadata. No funds are at risk (contracts hold no funds); impact is
  availability + integrity of badge definitions.
- **Exploit prerequisites:** Access to the deployer key after deployment.
  (Without the fix, this is a standing privilege, not a one-time window.)
- **Remediation:** Constructors grant **only** `DEFAULT_ADMIN_ROLE`.
  Operational roles must be granted explicitly during setup, and the
  deploy script / setup flow must renounce any setup-only role the
  deployer held (the integration test models this: deployer renounces
  `BADGE_MANAGER_ROLE` after defining the first badge).
  See `SECURITY_REMEDIATION.md` §SEC-002 for before/after code.
- **Regression test:** `test_DeployerLostAdminAfterRenounce` (asserts all
  four operational roles are absent for the deployer) +
  `test_PauseUnpauseRoleMatrix` (admin cannot pause without the role).
- **Verification:** tests pass; full suite green (120/120).

## SEC-003 — QuestManager ignored the minted badge token id (Slither unused-return)

- **Severity:** Low (Slither rated this detector Medium; assessed Low —
  see impact)
- **Status:** FIXED (commit `ee7592e`)
- **Contract / function:** `packages/contracts/src/QuestManager.sol` —
  `completeQuest(uint256)`, line 135–138 (fixed code);
  `packages/contracts/src/interfaces/IQuestManager.sol` — `QuestCompleted`
  event, lines 46–49
- **Root cause:** `completeQuest` called `achievement.issue(...)` and
  discarded its `uint256 tokenId` return value, so the minted badge token
  was not linked to the completion event.
- **PoC (reproducible):** Slither 0.11.6, detector `unused-return`,
  first run: `QuestManager.completeQuest ignores return value by
achievement.issue(...) (src/QuestManager.sol#133)`.
- **Exploit scenario / impact:** None exploitable. This is an
  observability gap only: indexers and the frontend could not learn the
  badge token id from the completion event and needed a second lookup
  (`hasBadge` / `BadgeIssued` event). No state, funds, or access control
  depended on the discarded value — hence Low, not Medium.
- **Exploit prerequisites:** N/A (not exploitable).
- **Remediation:** Capture the return value and emit it in
  `QuestCompleted` as `badgeTokenId` (0 when no badge is issued).
  See `SECURITY_REMEDIATION.md` §SEC-003 for before/after code.
- **Regression test:** `test_QuestCompletedEventCarriesBadgeTokenId` and
  `test_QuestCompletedEventHasZeroTokenIdWithoutBadge` in
  `test/QuestManager.t.sol`.
- **Verification:** tests pass; Slither re-run: `unused-return` gone.

## SEC-004 — Quest windows and cooldowns depend on `block.timestamp` (Slither timestamp ×3)

- **Severity:** Low
- **Status:** OPEN — accepted risk (documented, no code change)
- **Contract / function:** `packages/contracts/src/QuestManager.sol` —
  `createQuest` line 76; `completeQuest` lines 107–108, 118;
  `nextCompletionAt` line 183
- **Root cause:** Quest start/end windows and daily/weekly cooldowns are
  enforced with `block.timestamp`. Block producers can shift timestamps
  by small amounts (seconds on BSC).
- **PoC (reproducible):** Slither 0.11.6, detector `timestamp`, 3
  findings (one per function). No test PoC is needed: the dependence is
  by design and visible in the code.
- **Exploit scenario / impact:** A block producer (or a user lucky
  enough to land in a manipulated block) could complete a daily quest a
  few seconds before the cooldown truly expires, or enter a quest a few
  seconds early. Windows and cooldowns are measured in **days**; the
  maximum gain is seconds of early access to a capped reward
  (≤ 10,000 points per completion, itself capped per quest). No fund
  loss, no double award (one-time quests are still one-time).
- **Exploit prerequisites:** Control of block production, or luck, for a
  gain measured in seconds.
- **Remediation:** None applied. Any on-chain time source has this
  property; block numbers are worse on BSC (variable block times).
  Accepted as a documented risk; the threat model records it.
- **Regression test:** N/A (accepted by design). Cooldown behavior is
  covered by `test_DailyCooldownEnforced`,
  `test_WeeklyCooldownEnforced`, and the economic farming bounds.
- **Verification:** Reviewed; Slither findings acknowledged.

## SEC-005 — Slither `uninitialized-local` on `badgeTokenId` (false positive, no longer reported)

- **Severity:** Informational
- **Status:** CLOSED — false positive. Reported in intermediate Slither runs
  (after the SEC-003 fix, before the modifier reorder), reviewed as a false
  positive at the time, and **absent from the final run** (two consecutive
  runs, 7 detectors, 0 Medium — see
  `security-review-package/logs/slither-final.json`). The detector's
  dataflow analysis changed when `nonReentrant` was moved to the first
  modifier position; no code change was made to silence it.
- **Contract / function:** `packages/contracts/src/QuestManager.sol` —
  `completeQuest(uint256)`, line 135
- **Root cause (of the report):** Slither 0.11.6's `uninitialized-local`
  detector flagged `badgeTokenId` as "never initialized" even though it is
  initialized in its declaration. Two forms were tried — `uint256
badgeTokenId = 0;` followed by conditional assignment, and a ternary
  initializer covering both branches — and the detector flagged both in
  the intermediate runs.
- **Proof it is a false positive:** (1) The variable has an explicit
  initializer expression that always evaluates (ternary, both branches
  produce a value). (2) Solidity value types are zero-initialized by
  default, so no read of this variable can ever observe undefined data.
  (3) Both branches are covered by tests asserting the emitted value:
  `test_QuestCompletedEventCarriesBadgeTokenId` (badge path, token id 1)
  and `test_QuestCompletedEventHasZeroTokenIdWithoutBadge` (no-badge
  path, token id 0).
- **Exploit scenario / impact:** None — no uninitialized read exists.
- **Remediation:** None. The code was deliberately **not** contorted to
  silence the detector; the ternary single-assignment form is kept.
- **Verification:** Reviewed against the intermediate Slither 0.11.6
  reports; confirmed absent from the final report
  (`security-review-package/logs/slither-final.json`, re-run twice).

## SEC-006 — Slither Informational findings (reviewed, intentional)

- **Severity:** Informational
- **Status:** OPEN — accepted (4 detectors, all reviewed)
- **Findings:**
  1. `assembly` — `AgentGate.isAgentHolder`, lines 51–53. Intentional:
     the single `mload` is the SEC-001 fix (fail-closed returndata
     parsing). Minimal, tested, no memory-safety issue (reads one word
     past the bytes-array length slot after a `data.length >= 32` check).
  2. `low-level-calls` — `AgentGate.isAgentHolder`, lines 47–48.
     Intentional: the `staticcall` is the SEC-001 fix; the return value
     (`success`, length, decoded word) is fully checked, and `staticcall`
     cannot change state.
  3. `pragma` — two version constraints across the codebase
     (`^0.8.20` in OpenZeppelin, `^0.8.24` in our files). Not an issue:
     `foundry.toml` pins `solc_version = "0.8.39"` and the CI toolchain
     is pinned to 1.9.0, so the actual compiler is fixed and reproducible.
  4. `cyclomatic-complexity` — `QuestManager.completeQuest`, complexity 12. The function is a linear sequence of guard clauses, each
     independently tested (32 QuestManager tests). Splitting it would
     hurt readability without improving safety.
- **Verification:** Reviewed against the Slither 0.11.6 report.

---

## Appendix — Compiler and Foundry linter warnings (all reviewed)

`forge build` (solc 0.8.24, Foundry 1.9.0) initially emitted 24 warnings.
4 were fixed in code; the remaining 20 were each reviewed and are
documented below. Final state: **0 solc warnings** ("Compiler run
successful!"), 20 linter warnings, all dispositioned.

### Fixed (4)

| Warning                                      | Location                                          | Fix                                                 |
| -------------------------------------------- | ------------------------------------------------- | --------------------------------------------------- |
| `Warning (2018)` mutability can be `pure` ×2 | `Achievement.sol` `approve` / `setApprovalForAll` | Added `pure` (both functions only revert)           |
| `non-reentrant-not-first` ×2                 | `QuestManager.completeQuest`, `Achievement.issue` | Moved `nonReentrant` to the first modifier position |

### Reviewed, no change (20)

| Warning                            | Count                                                | Disposition                                                                                                                                                                                                                                              |
| ---------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `reentrancy-no-eth`                | 2 (`QuestManager.completeQuest` external calls)      | False positive: `nonReentrant` is now the first modifier, so the guard is set before the function body runs; the calls go to trusted contracts (own Reputation/Achievement) that make no callbacks. Attack-sim tests prove no reentrancy surface exists. |
| `reentrancy-events`                | 2 (`AgentGate.verify`, `QuestManager.completeQuest`) | Benign: the AgentGate "external call" is a `staticcall` (cannot change state or reenter); the QuestManager event follows calls to trusted contracts under `nonReentrant`, with all state already committed (checks-effects-interactions).                |
| `block-timestamp`                  | 5 (`QuestManager`)                                   | Same as SEC-004 — accepted risk.                                                                                                                                                                                                                         |
| `unsafe-oz-erc721-mint`            | 1 (`Achievement._mint`)                              | Intentional by design: `_mint` (not `_safeMint`) removes the `onERC721Received` callback and with it the reentrancy surface; soulbound badges need no receiver check. Documented in the contract NatSpec.                                                |
| `environment-read-across-mutation` | 10 (test files only)                                 | Benign test patterns: `vm.warp(block.timestamp + X)` reads the timestamp fresh to compute the warp target; helper functions read `block.timestamp` twice in one expression with no warp between the reads. All affected tests pass.                      |

---

## Phase 1 audit items addressed in this phase

| ID                                | Severity | Disposition                                                                                                                                   |
| --------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| M2 (evm_version unpinned)         | Medium   | Fixed — `foundry.toml` pins `cancun` (`4a690c4`)                                                                                              |
| M5 (chain↔Agent ID consistency)  | Medium   | Fixed — `env.ts` allowlist + cross-checks, 8-case harness + negative build (`1a24e91`)                                                        |
| M3 (CI foundry `stable`)          | Medium   | Fixed — pinned to 1.9.0 (`1a24e91`)                                                                                                           |
| L2 (redundant solc keys)          | Low      | Fixed (`4a690c4`)                                                                                                                             |
| L4 (DeployMock denylist)          | Low      | Fixed — allowlist {97, 31337} (`4a690c4`)                                                                                                     |
| L1 (`.gitignore` misses `.env.*`) | Low      | Fixed — `.env.*` ignored except `.env.example` (`1a24e91`)                                                                                    |
| L3 (web tsconfig duplicates base) | Low      | Fixed — extends `@agenthub/config/typescript/base`, typecheck passes (`1a24e91`)                                                              |
| L5 (CI gaps)                      | Low      | Partially fixed — format job, audit job, `permissions:` block added; secret scanning is a repo setting, listed as a pre-deploy checklist item |
| L6 (build memory cap)             | Low      | Fixed — `NODE_OPTIONS=--max-old-space-size=1024` in web build script (`1a24e91`)                                                              |
| L7 (lowercase Agent ID address)   | Low      | Fixed — checksummed `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` everywhere (verified with viem `getAddress`)                                 |
| M1 (`pnpm install` EPERM)         | Medium   | Not a repo defect — VM environment quirk, noted in Phase 1 audit                                                                              |
| M4 (zero web/shared unit tests)   | Medium   | **Still open** — vitest not added in this phase; see deployment gate                                                                          |
| L8 (peer-dep warnings)            | Low      | Not addressed — cosmetic, environment-level                                                                                                   |
| L9 (`pnpm audit` blocked in VM)   | Low      | Mitigated — CI audit job runs on GitHub runners; no local result exists                                                                       |
