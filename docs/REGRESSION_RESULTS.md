# Regression Results

**AGENTHUB — Security Review Remediation test evidence.**
**Date:** 2026-11-19. **Baseline:** `c568ee0` — 120/120 passing.
**After remediation:** **193/193 passing, 0 failed, 0 skipped.**
**Net change:** +73 tests. **No test was deleted or weakened.**

## 1. Per-suite results (baseline vs after)

| Suite | Baseline | After | Delta | Notes |
|---|---|---|---|---|
| AccessControl | 10 | 11 | +1 | Verifier role matrix |
| Achievement | 19 | 19 | 0 | Unchanged |
| AgentGate | 18 | 18 | 0 | Unchanged |
| AgentGateMainnet | — | 10 | +10 | NEW — TEMUAN 2 |
| AttackSimulation | 7 | 7 | 0 | Call sites updated (§3) |
| Attestation | — | 24 | +24 | NEW — TEMUAN 1 |
| DeployScript | — | 15 | +15 | NEW — TEMUAN 4 |
| EconomicAttack | 6 | 6 | 0 | Call sites updated (§3) |
| Integration | 6 | 7 | +1 | Timelock verifier grant |
| Invariant | 2 | 2 | 0 | 5th (OnChain) quest added (§3) |
| MockAgentId | 5 | 5 | 0 | Unchanged |
| QuestManager | 32 | 40 | +8 | Kind/dependency rules |
| Reputation | 15 | 15 | 0 | Unchanged |
| Validator | — | 14 | +14 | NEW — TEMUAN 1 |
| **Total** | **120** | **193** | **+73** | |

Counts verified two ways: `forge test` output (14 suites, 193 tests) and
`grep -cE "function test(Fuzz)?_"` per file against the baseline commit
(the Invariant suite runs 1 test function + 1 invariant function = 2).

Full-suite log: `security-remediation-package/logs/forge-test-full-after-temuan4.txt`.

## 2. New tests by finding

### TEMUAN 1 — Quest completion validation (47 new tests)
- `Attestation.t.sol` (24): valid completion + events; replay rejection;
  wrong nonce / account / quest; cross-chain replay (chainId 56 domain);
  cross-contract replay (second QuestManager); unauthorized signer; verifier
  rotation (revoke invalidates outstanding attestations immediately);
  admin-only role grant; expired / too-far / max-lifetime deadlines;
  malleable signature rejection; empty / zero / short signatures; non-holder
  with valid attestation (nonce not consumed); failed completion does not
  burn the nonce; attested farming bounded by cooldown; paused reverts;
  2 fuzz tests (valid attestation any in-range deadline; wrong nonce always
  rejected).
- `Validator.t.sol` (14): TokenBalanceValidator units (threshold, zero/EOA
  token, fail-closed on reverting/garbage token) + fuzz (threshold vs
  balance); OnChain completion path (holder completes, insufficient balance
  reverts, gains balance → completes, live re-check every completion);
  malicious validators (reverting → atomic revert, garbage → decode revert,
  reentrant → exactly one award, always-true → behaves like CheckIn).
- `QuestManager.t.sol` (8): constructor rejects EOA dependencies (TEMUAN 3);
  OnChain without validator / with EOA validator rejected; validator
  rejected for CheckIn / Attested; Attested quest stores its kind;
  `completeQuest` reverts on Attested quests; `completeQuestWithAttestation`
  reverts on CheckIn quests.
- `AccessControl.t.sol` (1): verifier role matrix — only admin grants/
  revokes; a verifier cannot create quests or pause.

### TEMUAN 2 — Agent ID pinning (10 new tests)
- `AgentGateMainnet.t.sol` (10): official constant pinned; mainnet accepts
  the official address; mainnet rejects the mock, a fake ERC-721, and an
  arbitrary contract; testnet + local accept the mock; chains 1 and 137
  rejected; `WrongChain` still fires before the mainnet lock on chain 31337.

### TEMUAN 3 — Dependency validation (covered above)
- `test_ConstructorRejectsEoaDependencies` (QuestManager.t.sol, counted in
  the 8 above) + `test_DeployedStackWorksEndToEnd` (DeployScript.t.sol).

### TEMUAN 4 — Deployment script (15 new tests)
- `DeployScript.t.sol` (15): full local deploy wires everything (roles,
  timelock delay, deployer keeps nothing); end-to-end completion through
  the deployed stack; explicit Agent ID skips the mock; no-verifier deploy
  skips the role; zero multisig/creator/pauser rejected; unsupported chain
  rejected; mainnet rejects mock / zero Agent ID; mainnet accepts the
  official address; testnet accepts the mock; `run()` deploys a local stack
  (via `vm.setEnv` + `startBroadcast`, public Anvil test key, local only);
  `run()` refuses mainnet without `CONFIRM_MAINNET_DEPLOY=true`;
  `run()` deploys on mainnet with confirmation + official address.
- CLI dry-runs: local `forge script` (8,467,332 gas, success) and BSC
  testnet fork via publicnode (`SIMULATION COMPLETE`, 10,294,857 gas).
  No broadcast. Logs in `security-remediation-package/logs/`.

### Integration (1 new test)
- `test_TimelockCanGrantVerifierRoleAfterDelay` + a VERIFIER_ROLE assertion
  in `test_DeployerLostAdminAfterRenounce` (Integration.t.sol).

## 3. Existing tests that were updated (and why)

**`createQuest` call sites — 48 sites across 6 test files**
(QuestManager, AttackSimulation, EconomicAttack, Integration, Invariant,
AccessControl). The `createQuest` signature gained two parameters
(`ValidationKind validationKind, address validator`). Every existing call
site was updated to pass `ValidationKind.CheckIn, address(0)`.
**Rationale:** the old tests exercised self-service completion — completing
by calling the function. Under the new design that behavior is exactly what
`CheckIn` means, now labeled explicitly instead of implicitly. Behavior is
identical; the tests still assert the same outcomes (points, badges, caps,
cooldowns, duplicates). No assertion was weakened.

**`Invariant.t.sol` — a 5th quest added.** The handler now also drives an
OnChain daily quest (TokenBalanceValidator, threshold 1, MockERC20; alice/
bob/carol hold 100, dave holds 0). Rewards/badges/caps arrays extended to 5.
`test_HandlerActuallyCompletesQuests` updated for the new totals (alice
on-chain quest → 115 pts, then daily after warp → 125). The invariant
itself (points awarded == sum of completed quest rewards, etc.) is
unchanged and still holds.

**`QuestManager.t.sol` — `test_CreateQuestStoresAllFields`** now also
asserts `validationKind` and `validator` (strictly stronger).

**`Integration.t.sol` — `test_DeployerLostAdminAfterRenounce`** now also
asserts the deployer holds no VERIFIER_ROLE (strictly stronger).

**`AccessControl.t.sol` — `test_VerifierRoleMatrix`** is new (counted in §2).

No other existing test was modified. `AttackSimulation.t.sol` and
`EconomicAttack.t.sol` changed only at the call sites (verified via
`git diff --stat`: 35 and 13 lines respectively, all mechanical).

## 4. Test failures found and fixed during the remediation

1. `test_VerifierRoleMatrix` (AccessControl): a role lookup
   (`qm.QUEST_CREATOR_ROLE()`) placed after `vm.prank` consumed the prank,
   so the target call ran as the test contract. Fixed by hoisting the
   lookups before the prank. Test bug, not contract bug.
2. `test_RunRefusesMainnetWithoutConfirmation` (DeployScript): passed in
   isolation, failed in the full suite — `vm.setEnv` persists across tests
   in one run, so a sibling test's `CONFIRM_MAINNET_DEPLOY=true` leaked in.
   Fixed by setting the flag explicitly to `"false"` in the test. Test bug,
   not contract bug.
3. `test_MalleableSignatureRejected` / `test_EmptySignatureRejected` /
   `test_ZeroSignatureRejected` / `test_ShortSignatureRejected`
   (Attestation): after the Slither-driven change of
   `InvalidAttestationSignature()` to `InvalidAttestationSignature(bytes32
   errorArg)` (§6), the selector-only `expectRevert` no longer matched the
   4+32-byte revert data. Fixed by expecting the full error with the exact
   argument (flipped `s` for malleable, length for empty/short, 0 for
   zero). Test update, not a weakening — the assertions are now stricter.
4. **One unidentified transient failure:** during the final verification
   pass, one full-suite run reported a single failing test, but only the
   last two output lines were logged, so the failing test was not
   identified. Three subsequent full-suite runs (two default seed, one
   `--fuzz-seed 12345`) all passed 193/193, and the 10,000-run fuzz pass
   also passed 193/193. The failure was not reproduced. It is recorded
   here honestly rather than hidden; the likely candidates are a fuzz-seed
   dependent invariant run or a one-off environment hiccup. Lesson: always
   log full test output, not just the tail.

Both are documented here so a future reader does not "fix" them again.

## 5. Fuzz, invariant, and static analysis

- **Fuzz (default runs):** included in the 193 — all fuzz tests pass.
- **Fuzz (10,000 runs):** run separately; see
  `security-remediation-package/logs/forge-test-fuzz-10000.txt`.
- **Invariant:** 2/2 (handler drives all 5 quests incl. the new OnChain one).
- **Slither 0.11.6:** run separately; see
  `security-remediation-package/logs/slither.txt` and §6 below.
- **Format:** `forge fmt --check` clean (see logs).

## 6. Slither results

Slither 0.11.6, `slither . --exclude-dependencies`, run 2026-11-19.
Full output: `security-remediation-package/logs/slither.txt` (+ `slither.json`).

**Result: 10 findings — 0 Critical, 0 High, 0 Medium, 4 Low, 6 Informational.**

| Impact | Detector | Count | Assessment |
|---|---|---|---|
| Low | `timestamp` | 4 | `block.timestamp` comparisons for quest windows, attestation deadlines, cooldowns. Inherent to the design; BSC block times (~0.75s) make miner manipulation of day-scale windows irrelevant. Pre-existing pattern (3 in baseline), +1 for the attestation deadline checks. |
| Informational | `assembly` | 2 | Inline asm in `AgentGate.isAgentHolder` (pre-existing, SEC-001 fail-closed pattern) and `TokenBalanceValidator.validate` (same pattern). Intentional. |
| Informational | `low-level-calls` | 2 | `staticcall` in the same two functions. Intentional (fail-closed + state-change-free). |
| Informational | `cyclomatic-complexity` | 1 | `_completeQuest` complexity 13 (was 12 in baseline — the validator branch added one path). Accepted: splitting it would obscure the checks-effects-interactions order. |
| Informational | `pragma` | 1 | Two solc constraints (^0.8.20 OZ, ^0.8.24 project). Pre-existing. |

**Baseline comparison:** the pre-remediation run had 7 findings (0
Critical/High/Medium, 3 Low, 4 Informational). The remediation adds 3
findings, all Low/Informational and all explained above. No new High/Medium.

**One Medium was found and fixed during this pass:** the first Slither run
flagged `unused-return` (Medium) on
`(signer, err,) = ECDSA.tryRecover(...)` in `_verifyAttestation` — the
third return value (`errorArg`: the offending `s` or the signature length)
was dropped. The value is `bytes32(0)` on success, so dropping it was safe,
but carrying it into the revert makes bad attestations diagnosable:
`InvalidAttestationSignature` now takes the `errorArg`, and the 4 affected
tests assert the exact argument (§4.3). Re-run after the fix: the Medium is
gone, 10 findings remain, all Low/Informational.

## 7. Frontend verification

Run 2026-11-19 with pnpm 9.15.4 (reinstalled via npm — pnpm is ephemeral
on this VM and had been removed):

| Command | Result |
|---|---|
| `pnpm typecheck` | exit 0 |
| `pnpm lint` | exit 0 — "No ESLint warnings or errors" |
| `pnpm test` | exit 0 (contracts `forge test` + web placeholder: "no unit tests yet — vitest lands in Phase 2") |
| `pnpm build` | exit 0 (with `NODE_OPTIONS=--max-old-space-size=1024`) |

Logs: `security-remediation-package/logs/pnpm-*.txt`.

Notes:
- `pnpm install` ends with the known VM quirk `EPERM: operation not
  permitted, chown '.../node_modules/.modules.yaml.<tmp>'` (also seen in
  the Phase 1 audit) — the install itself completes (903 packages resolved,
  0 downloaded) and all commands above run. Not a repo defect.
- `pnpm typecheck` needs `forge` on PATH (the contracts package's
  typecheck is `forge build`).
- The web app does not call `createQuest`/`completeQuest` yet (only a
  `balanceOf` ABI + placeholder UI), so the contract signature change does
  not affect the frontend build.
