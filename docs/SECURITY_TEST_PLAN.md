# AGENTHUB — Security Test Plan

> Scope: security engineering phase (post–Phase 1), 2026-11-19.
> Contracts: `packages/contracts/src/` — AgentGate, QuestManager, Reputation,
> Achievement (+ interfaces, MockAgentId). Frontend env validation:
> `apps/web/lib/env.ts`. All tests run locally with Foundry; **no testnet or
> mainnet deployment was performed in this phase** (needs tBNB + deployer key
> from the user — not provided).

## 1. Test inventory (final run: 120 passed, 0 failed)

| Suite            | File                          | Tests   | What it proves                                                                       |
| ---------------- | ----------------------------- | ------- | ------------------------------------------------------------------------------------ |
| MockAgentId      | `test/MockAgentId.t.sol`      | 5       | Soulbound mock behaves like the real Agent ID (incl. 1 fuzz)                         |
| AgentGate        | `test/AgentGate.t.sol`        | 18      | Fail-closed gate: reverts, garbage, reentrancy, chain binding (incl. 1 fuzz)         |
| QuestManager     | `test/QuestManager.t.sol`     | 32      | Validation, roles, cooldowns, caps, pause, badge skip, event token id (incl. 1 fuzz) |
| Reputation       | `test/Reputation.t.sol`       | 15      | Role-only points, caps, level thresholds, pause (incl. 1 fuzz)                       |
| Achievement      | `test/Achievement.t.sol`      | 19      | Soulbound enforcement, one-badge rule, roles, pause (incl. 1 fuzz)                   |
| Integration      | `test/Integration.t.sol`      | 6       | Real wiring end-to-end + TimelockController admin flow                               |
| Invariant        | `test/Invariant.t.sol`        | 2       | 5 stateful invariants over ~32,768 randomized handler calls + 1 sanity test          |
| AttackSimulation | `test/AttackSimulation.t.sol` | 7       | Reentrancy, malicious Agent ID, downstream revert, OOG, delegation, ID transfer      |
| AccessControl    | `test/AccessControl.t.sol`    | 10      | Full role matrix incl. admin-has-no-implicit-power                                   |
| EconomicAttack   | `test/EconomicAttack.t.sol`   | 6       | Cooldown farming bounds, emission caps, Sybil-without-ID                             |
| **Total**        |                               | **120** |                                                                                      |

Category totals: unit 89 · integration 6 · invariant 2 (5 invariant
functions) · attack simulation 7 · access control 10 · economic 6.
Fuzz tests: 5 (`testFuzz_*` in AgentGate, MockAgentId, QuestManager,
Reputation, Achievement).

## 2. How to run

```bash
cd packages/contracts
forge build            # solc 0.8.39, evm_version cancun (foundry.toml)
forge test             # full suite, ~45 s (invariant suite dominates)
forge test --match-contract QuestManagerTest   # one suite
forge fmt --check      # formatting gate (CI)
```

Frontend (from repo root):

```bash
pnpm --filter @agenthub/web lint
pnpm --filter @agenthub/web typecheck
NEXT_PUBLIC_CHAIN_ID=97 pnpm --filter @agenthub/web build
pnpm format:check
```

Static analysis (venv `~/workspace/slither-venv`, Slither 0.11.6, solc 0.8.39):

```bash
cd packages/contracts
slither . --exclude-dependencies
# Exit code 255 is Slither's "findings present" signal, not a crash.
# Final run (verified twice): 7 detectors — 0 Critical/High/Medium,
# 3 Low (accepted), 4 Informational (reviewed). See SECURITY_FINDINGS.md.
# (An intermediate run reported 1 Medium uninitialized-local, reviewed as
# a false positive; it is absent from the final run — see SEC-005.)
```

## 3. Coverage by threat (threat model `docs/SECURITY_THREAT_MODEL.md`)

| Threat                                     | Covered by                                                                                                                    |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| T1 non-holder completes quests             | Unit (gate checks) + invariant `NonHolderEarnsNothing` + economic Sybil test                                                  |
| T2 double claim / replay                   | Unit (duplicate, cooldown) + invariant (points/completions match ghost) + attack sim (delegation, mint-callback, ID transfer) |
| T3 reentrancy                              | Attack sim (badge callback, mint callback, fallback) + `nonReentrant` + `_mint` (no callback)                                 |
| T4 privilege escalation                    | Access-control matrix (10 tests) + integration (timelock flow, deployer renounce)                                             |
| T5 malformed/untrusted input               | AgentGate garbage/revert tests + attack sim (malicious Agent ID fails closed)                                                 |
| T6 economic farming                        | Economic suite (daily/weekly bounds, emission caps) + invariant (cap respected)                                               |
| T7 downstream failure / OOG                | Attack sim (downstream revert atomicity, gas-exhaustion atomicity)                                                            |
| T8 misconfiguration (wrong chain/contract) | Frontend M5 env checks (8-case harness + negative build) + gate chain binding                                                 |

## 4. What was NOT tested (honest gaps)

- **Real Agent ID contract on BSC mainnet.** Only MockAgentId (local) was
  used. The gate's staticcall logic is contract-agnostic, but mainnet
  behavior must be verified on testnet staging first (with the mock) and
  then against the real contract on mainnet before launch.
- **BSC testnet Cancun behavior.** `evm_version = "cancun"` is pinned for
  reproducibility; BSC testnet must confirm Cancun opcodes behave before
  any mainnet deploy.
- **Safe multisig + TimelockController interaction.** Only the
  TimelockController side was tested (Foundry). The production Safe
  (threshold ≥ 2) proposing through the timelock is untested.
- **Web/shared unit tests (M4).** Still zero vitest tests. The env
  validation was verified instead via a compiled-Node harness (8 cases)
  and positive/negative `next build` runs — see `SECURITY_FINDINGS.md`
  (M5) and `security-review-package/logs/`.
- **`pnpm audit`.** Blocked by registry 403 in this VM (Phase 1 audit L9).
  A CI audit job now runs it on GitHub runners; no local audit result
  exists — **do not claim otherwise**.
- **Gas costs on live BSC.** Only Foundry gas reports exist; live costs
  need a testnet deploy.
- **Browser/wallet flows.** No browser testing was done in this phase.

## 5. Rules followed

- No assertion was weakened to make a test pass. Every failure during the
  phase was fixed in code or in the test's own (provably wrong) assumption,
  and the two real bugs found by tests (SEC-001, SEC-002) were fixed in the
  contracts, not papered over.
- Every test in the inventory above was actually run; the final full run
  is logged in `security-review-package/logs/forge-test-final.log`.
- No test touches mainnet, testnet, real funds, or the user's wallet.
