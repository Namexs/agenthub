# AGENTHUB — Security Deployment Gate

> Go/no-go checklist for moving to the next stage (BSC testnet deploy, then
> mainnet). Evaluated 2026-11-19 at commit `ee7592e` (before the review
> package commit). **No deployment of any kind was performed in this phase.**

## Gate verdict

| Gate (§7 directive)                    | Status     | Evidence                                                                                                                                                           |
| -------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0 unresolved Critical/High             | ✅ PASS    | 0 Critical; 1 High (SEC-001) fixed + regression-tested                                                                                                             |
| Medium fixed or mitigated + documented | ✅ PASS    | 1 Medium (SEC-002) fixed + regression-tested; M4 (vitest) is the only open Medium and is a test-coverage gap, not a contract vulnerability — see below             |
| All tests pass                         | ✅ PASS    | `forge test`: 120 passed, 0 failed; web lint/typecheck/build pass; format checks pass                                                                              |
| Invariants hold                        | ✅ PASS    | 5 invariants over ~32,768 randomized handler calls, 0 violations                                                                                                   |
| Static analysis findings reviewed      | ✅ PASS    | Slither 0.11.6 final run (verified twice): 7 findings, all reviewed — 3 Low accepted (SEC-004), 4 Informational accepted (SEC-006); 1 Medium fixed during the phase (SEC-003); 1 false positive from intermediate runs (SEC-005) is absent from the final run |
| No secrets exposed                     | ✅ PASS    | No keys/secrets in the repo; `.gitignore` covers `.env.*`; grep-verified (see review package logs)                                                                 |
| No unverified dependencies             | ⚠️ PARTIAL | OpenZeppelin 5.0.2 (pinned, audited upstream) + npm deps pinned in lockfile; **`pnpm audit` never ran locally** (registry 403) — CI audit job covers it on runners |

**Overall: GO for BSC testnet staging** (once the user provides tBNB + a
deployer key). **NOT YET GO for mainnet** — see the pre-mainnet list.

## Pre-testnet checklist (blocking)

- [ ] User provides tBNB + deployer key (dedicated deployer wallet, funded
      minimally). **Not yet provided — this is the current blocker.**
- [ ] Deploy to BSC testnet (chain 97) with MockAgentId; verify the full
      quest → points → badge flow on-chain via BscScan.
- [ ] Confirm Cancun EVM behavior on BSC testnet (`evm_version = "cancun"`
      is pinned; BSC testnet must accept it).
- [ ] TimelockController (2-day delay) + multisig admin flow rehearsed on
      testnet, including deployer renounce of admin **and** setup-only
      operational roles (SEC-002).
- [ ] Enable GitHub secret scanning + push protection in repo settings
      (cannot be configured from the workflow file).

## Pre-mainnet checklist (blocking — do not skip)

- [ ] All pre-testnet items complete, with testnet contracts verified on
      BscScan and the staging flow exercised end-to-end.
- [ ] Production privilege model in place: `DEFAULT_ADMIN_ROLE` →
      TimelockController (minDelay 2 days); proposers/executors = admin
      Safe (threshold ≥ 2); `QUEST_CREATOR_ROLE` = campaign multisig;
      `PAUSER_ROLE` = admin multisig; `SCORE_SOURCE_ROLE` / `ISSUER_ROLE`
      = QuestManager only; deployer renounces everything.
- [ ] Mainnet AgentGate pointed at the official Agent ID contract
      `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` (chain 56) — the
      frontend M5 check enforces this at build time.
- [ ] MockAgentId **never** deployed to mainnet; mainnet deploy script
      must refuse chain 56 with a mock address (add a guard in the
      deploy script when it is written).
- [ ] M4 closed: vitest unit tests for `apps/web` + `packages/shared`
      (env validation, chain helpers). Currently zero — the env logic
      was verified by harness + builds instead, which is acceptable for
      testnet staging but not for mainnet.
- [ ] `pnpm audit` green on CI (runs on GitHub runners; blocked locally).
- [ ] Independent review of the `security-review-package/` by at least
      one external reviewer, or a scoped audit if budget allows. This
      phase was self-review + automated tooling, not an external audit.
- [ ] Incident response: pause runbook written (who can pause, how
      unpause is decided, timelock delay implications during an incident).

## Known accepted risks (carried forward)

- SEC-004: `block.timestamp` dependence (seconds-level manipulation,
  days-level windows/cooldowns) — accepted.
- Agent ID issuance is Binance's: Sybil resistance rests on one Agent ID
  per agent identity. If Agent ID issuance is ever gamed, quest farming
  scales with it. Out of this project's control; monitored via the
  leaderboard / completion-rate anomalies.
- Timelock delay (2 days) slows emergency admin action; pause is the
  fast path (multisig, no delay) and unpause needs the timelock — by
  design, so a compromised pauser cannot resume alone.
- No funds are held by the contracts (non-custodial, points + badges
  only), so the blast radius of a contract bug is reputation/badge
  integrity, not user funds.

## What still needs the user

1. **tBNB + deployer key** for the BSC testnet deploy (blocking).
2. Decision on the admin multisig (Safe) setup: who the signers are.
3. Approval before any deploy or hackathon submit (standing rule).
