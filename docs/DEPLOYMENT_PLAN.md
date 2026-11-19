# Deployment Plan

**AGENTHUB — deployment script, role wiring, and trust assumptions.**
**Date:** 2026-11-19. **Script:** `packages/contracts/script/DeployAgentHub.s.sol`.
**Status:** script written and dry-run tested (local + BSC testnet fork).
**No deployment has been performed. Nothing is deployed.**

## 1. Deployment order

The script deploys in dependency order (single run, single deployer key):

1. **MockAgentId** — only on testnet (97) / local (31337), and only when
   `AGENT_ID_ADDRESS` is unset. Never on mainnet.
2. **AgentGate** — trusts the Agent ID address (official on mainnet).
3. **TimelockController** — 2-day delay; multisig proposes + executes;
   NO optional admin (the timelock self-administers via proposals, per OZ
   guidance — the optional admin "should be subsequently renounced", so it
   is never granted).
4. **Reputation** — deployer as temporary admin.
5. **Achievement** — deployer as temporary admin.
6. **QuestManager** — deployer as temporary admin.

Then role wiring (§2), admin handover to the timelock, deployer renounce,
and post-deploy verification (`_verifyWiring` — reverts on any mismatch).

## 2. Role wiring (final state)

| Contract | Role | Holder |
|---|---|---|
| Reputation | DEFAULT_ADMIN_ROLE | Timelock |
| Reputation | SCORE_SOURCE_ROLE | QuestManager |
| Achievement | DEFAULT_ADMIN_ROLE | Timelock |
| Achievement | ISSUER_ROLE | QuestManager |
| Achievement | BADGE_MANAGER_ROLE | Admin multisig |
| QuestManager | DEFAULT_ADMIN_ROLE | Timelock |
| QuestManager | QUEST_CREATOR_ROLE | Quest creator address |
| QuestManager | PAUSER_ROLE | Pauser address (fast pause, no timelock) |
| QuestManager | VERIFIER_ROLE | First verifier (optional; more via timelock) |
| Timelock | DEFAULT_ADMIN_ROLE | Timelock itself |
| Timelock | PROPOSER_ROLE / CANCELLER_ROLE | Admin multisig |
| Timelock | EXECUTOR_ROLE | Admin multisig |
| **All** | **any role** | **Deployer: NONE** |

The deployer holds zero privileges after deployment (SEC-002). Admin actions
(role grants, quest-type changes, unpausing after a timelock delay) go
through 2-day timelocked proposals from the multisig. Pausing is the only
fast admin action (PAUSER_ROLE, no delay) — it exists to stop an incident.

## 3. How to run the script

```bash
cd packages/contracts

# 1. DRY-RUN first (simulation only — no broadcast, no funds spent):
DEPLOYER_PRIVATE_KEY=<key> \
ADMIN_MULTISIG=<0x..> QUEST_CREATOR=<0x..> PAUSER=<0x..> \
[VERIFIER=<0x..>] [AGENT_ID_ADDRESS=<0x..>] \
forge script script/DeployAgentHub.s.sol \
  --fork-url <rpc-url>   # omit for a local in-memory simulation

# 2. Only after reviewing the dry-run output AND getting explicit approval:
#    add --broadcast --verify (see §5 checklist). Never broadcast a dry-run
#    you have not read.
```

Environment variables:

| Variable | Required | Notes |
|---|---|---|
| `DEPLOYER_PRIVATE_KEY` | yes | Dedicated deployer key, funded only for this deployment. |
| `ADMIN_MULTISIG` | yes | Multisig address (timelock proposer/executor + badge manager). **Validated before any deployment:** the script statically calls `getThreshold()` and `getOwners()` and requires a real Safe with threshold ≥ 2 (see `script/SafeValidation.sol`, `MIN_SAFE_THRESHOLD = 2`); a non-Safe or 1-of-n address reverts the deploy. A standalone pre-check exists: `forge script script/ValidateSafe.s.sol --sig "run(address)" <addr>`. |
| `QUEST_CREATOR` | yes | Address that creates quests. |
| `PAUSER` | yes | Address that can pause QuestManager instantly. |
| `VERIFIER` | no | First attestation verifier (VERIFIER_ROLE). |
| `AGENT_ID_ADDRESS` | no | Agent ID contract. Unset on 97/31337 = deploy MockAgentId. On 56 MUST be `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`. |
| `CONFIRM_MAINNET_DEPLOY` | on 56 | Must be `true` on chain 56, otherwise the script reverts. |

Dry-run evidence (2026-11-19): local simulation 8,467,332 gas; BSC testnet
fork (publicnode) `SIMULATION COMPLETE`, 10,294,857 gas (~0.00103 BNB),
6 CREATEs + 11 role-wiring CALLs. Logs in
`security-remediation-package/logs/`. The BNB Chain dataseed RPC returned
403 from the build VM — use publicnode or another endpoint for forks.

## 4. Trust assumptions (documented honestly)

1. **Code-length checks are not trust proofs.** `QuestManager`'s constructor
   checks that its three dependencies have code (`NoCodeAtDependency`), and
   `createQuest` checks that an OnChain validator has code. These checks
   reject EOAs and empty addresses — they do NOT prove the code is the right
   contract or that it behaves honestly. A malicious contract with matching
   function signatures would pass. The real protection is deployment-time
   discipline: the script deploys all four contracts itself and asserts the
   wiring; dependencies are never supplied from an untrusted source.
2. **Validators are allowlist-gated.** An OnChain quest's validator is
   picked by the quest creator, but it must be on the QuestManager
   allowlist (`approvedValidators`): `createQuest` and quest completion
   both revert with `ValidatorNotApproved` for an unapproved validator,
   and revoking a validator takes effect immediately at completion (see
   `QUEST_VALIDATION_DESIGN.md` §2.4). The allowlist stops a creator
   from wiring an arbitrary always-true validator — but an approved
   validator is still trusted code: never approve a validator whose
   source you have not read, and never approve a validator you do not
   control (a third party could upgrade or replace its logic only if it
   is a proxy — prefer non-proxy validators).
3. **Verifiers are trusted.** See `QUEST_VALIDATION_DESIGN.md` §2.3 and
   `NEW_THREAT_MODEL.md` T-ATT-01. Attested quests are only as honest as
   their verifiers.
4. **The Agent ID contract is trusted.** AgentGate trusts the official
   Binance Agent ID contract on mainnet. A compromise of that contract is
   out of AGENTHUB's scope.
5. **The multisig is trusted and must not lose its keys.** If the multisig
   loses PROPOSER_ROLE (or its keys), the timelock cannot be administered.
   Multisig custody is an operational requirement, not a contract feature.
6. **The deployer key is single-use.** Use a dedicated key, fund it only for
   the deployment, and discard it afterwards (it holds no roles after the
   script runs, but a leaked key could still be used to deploy lookalike
   contracts or confuse verification).

## 5. Pre-broadcast checklist (mainnet AND testnet)

- [ ] Dry-run output reviewed: 6 contracts, correct addresses, 11 wiring
      calls, no `WiringCheckFailed`.
- [ ] All env addresses double-checked out-of-band (the script cannot verify
      an address belongs to the intended person).
- [ ] `AGENT_ID_ADDRESS` on mainnet is exactly
      `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`.
- [ ] `CONFIRM_MAINNET_DEPLOY=true` set deliberately (mainnet only).
- [ ] Deployer key is dedicated and funded only for this deployment.
- [ ] Explicit owner approval for this specific broadcast.
- [ ] After broadcast: verify all contracts on BscScan (`--verify` or manual
      `forge verify-contract`), then re-run the wiring checks against the
      live addresses (read `hasRole` for every role in §2).
- [ ] Record the deployed addresses in `apps/web/.env.local` (never commit
      real keys) and in the deployment record.

## 6. Post-deployment steps (not in the script)

- Approve the initial validators through the timelock (2-day delay):
  deploy the `TokenBalanceValidator` instance(s) for the launch quests
  and `approveValidator` each one — see `QUEST_VALIDATION_DESIGN.md`
  §2.4 for the list and the approval process. No OnChain quest can be
  created until at least one validator is approved.
- Define the first badges (`Achievement.defineBadge`, via the multisig as
  BADGE_MANAGER_ROLE).
- Grant additional verifiers through the timelock (2-day delay).
- Create the first quests (QUEST_CREATOR_ROLE): at least one of each
  ValidationKind, and verify one completion of each kind on testnet before
  mainnet.
- Set up monitoring: completion spikes, verifier activity, pause events.
- Testnet is staging: a testnet deployment does NOT authorize mainnet. The
  mainnet deployment repeats this whole checklist.
