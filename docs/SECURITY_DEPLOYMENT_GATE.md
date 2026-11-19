# AGENTHUB — Security Deployment Gate

> Go/no-go checklist for moving to the next stage (BSC testnet deploy, then
> mainnet). Evaluated 2026-11-19 at commit `62ad154` (final pre-testnet
> cleanup: validator allowlist + Safe validation + Vitest + VERIFIER_ROLE
> SOP). **No deployment of any kind has been performed. Testnet has NOT
> actually been deployed — the deployment script exists and is dry-run
> tested, but no contract is live anywhere.**

## Gate verdict

| Gate (§7 directive)                    | Status     | Evidence                                                                                                                                                                                                                                                      |
| -------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0 unresolved Critical/High             | ✅ PASS    | 0 Critical; 1 High (SEC-001) fixed + regression-tested; remediation added no new Critical/High (Slither re-run in the final verification confirms — see below)                                                                                                 |
| Medium fixed or mitigated + documented | ✅ PASS    | 1 Medium (SEC-002) fixed + regression-tested; 1 Medium (unused-return) found + fixed during remediation; M4 (vitest) is now CLOSED — see below                                                                                                                |
| All tests pass                         | ✅ PASS    | `forge test`: **218 passed, 0 failed** (16 suites; 193 remediation baseline + 14 validator allowlist + 11 Safe validation); **Vitest: 24 passed** (8 shared + 16 web); web lint/typecheck pass                                                               |
| Invariants hold                        | ✅ PASS    | 5 invariants over ~32,768 randomized handler calls, 0 violations (re-verified in the final pre-testnet runs)                                                                                                                                                  |
| Static analysis findings reviewed      | ✅ PASS    | Slither 0.11.6: **10 findings, 0 Critical/High/Medium, 4 Low, 6 Informational** — verified at 76572c6; re-run in the final pre-testnet verification (item 9) to confirm the allowlist + Safe changes add no new findings                                            |
| No secrets exposed                     | ✅ PASS    | No keys/secrets in the repo; `.gitignore` covers `.env.*`; grep-verified (see review package logs)                                                                                                                                                            |
| No unverified dependencies             | ⚠️ PARTIAL | OpenZeppelin 5.0.2 (pinned, audited upstream) + npm deps pinned in lockfile; **`pnpm audit` never ran locally** (registry 403) — CI audit job covers it on runners                                                                                            |

**Overall: GO for BSC testnet staging** (once the user provides tBNB + a
deployer key) — **pending the final pre-testnet verification** (item 9:
full re-run + Slither confirmation) and the user's own decision on the
transient-failure caveat (see `FINAL_PRE_TESTNET.md`). **NOT YET GO for
mainnet** — see the pre-mainnet list.

## Pre-testnet checklist (blocking)

- [ ] User provides tBNB + deployer key (dedicated deployer wallet, funded
      minimally). **Not yet provided — this is the current blocker.**
- [ ] Deploy to BSC testnet (chain 97) with MockAgentId; verify the full
      quest → points → badge flow on-chain via BscScan. Deployment script
      is ready (`script/DeployAgentHub.s.sol`, dry-run tested local +
      testnet fork); `ADMIN_MULTISIG` is validated as a Safe (threshold
      ≥ 2) before any deployment.
- [ ] Confirm Cancun EVM behavior on BSC testnet (`evm_version = "cancun"`
      is pinned; BSC testnet must accept it).
- [ ] TimelockController (2-day delay) + multisig admin flow rehearsed on
      testnet, including deployer renounce of admin **and** setup-only
      operational roles (SEC-002).
- [ ] Initial validators approved on testnet (TokenBalanceValidator
      instance(s) via timelock) and one OnChain completion verified
      end-to-end (see `QUEST_VALIDATION_DESIGN.md` §2.4).
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
- [ ] MockAgentId **never** deployed to mainnet; the deploy script refuses
      chain 56 with a mock address (guard in `DeployAgentHub.s.sol`) and
      requires `CONFIRM_MAINNET_DEPLOY=true` on mainnet.
- [x] M4 closed: vitest unit tests for `apps/web` + `packages/shared`
      (env validation incl. M5 chain/Agent ID consistency, chain helpers,
      shared constants) — 24 tests, all passing (final pre-testnet
      cleanup, item 3).
- [ ] `pnpm audit` green on CI (runs on GitHub runners; blocked locally).
- [ ] Independent review of the `security-review-package/` by at least
      one external reviewer, or a scoped audit if budget allows. This
      phase was self-review + automated tooling, not an external audit.
- [ ] Incident response: pause runbook written (who can pause, how
      unpause is decided, timelock delay implications during an incident).
      Partially covered: `VERIFIER_ROLE_SOP.md` §4 documents the
      pause/revoke/unpause sequence for a verifier compromise (worst case
      ~4 days paused); a general runbook for other incident types is
      still open.

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
2. Decision on the admin multisig (Safe) setup: who the signers are
   (threshold ≥ 2 is enforced by the deploy script).
3. Decision on who holds the first verifier key (see
   `VERIFIER_ROLE_SOP.md`).
4. Approval before any deploy or hackathon submit (standing rule).
