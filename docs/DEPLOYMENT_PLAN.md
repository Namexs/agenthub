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

| Contract     | Role                           | Holder                                                              |
| ------------ | ------------------------------ | ------------------------------------------------------------------- |
| Reputation   | DEFAULT_ADMIN_ROLE             | Timelock                                                            |
| Reputation   | SCORE_SOURCE_ROLE              | QuestManager                                                        |
| Achievement  | DEFAULT_ADMIN_ROLE             | Timelock                                                            |
| Achievement  | ISSUER_ROLE                    | QuestManager                                                        |
| Achievement  | BADGE_MANAGER_ROLE             | Admin multisig                                                      |
| QuestManager | DEFAULT_ADMIN_ROLE             | Timelock                                                            |
| QuestManager | QUEST_CREATOR_ROLE             | Quest creator address                                               |
| QuestManager | PAUSER_ROLE                    | **Admin multisig (default)** — `PAUSER` env overrides (non-default) |
| QuestManager | VERIFIER_ROLE                  | First verifier (optional; more via timelock)                        |
| Timelock     | DEFAULT_ADMIN_ROLE             | Timelock itself                                                     |
| Timelock     | PROPOSER_ROLE / CANCELLER_ROLE | Admin multisig                                                      |
| Timelock     | EXECUTOR_ROLE                  | Admin multisig                                                      |
| **All**      | **any role**                   | **Deployer: NONE**                                                  |

The deployer holds zero privileges after deployment (SEC-002). Admin actions
(role grants, quest-type changes, unpausing after a timelock delay) go
through 2-day timelocked proposals from the multisig. Pausing is the only
fast admin action (PAUSER_ROLE, no delay) — it exists to stop an incident.

## 3. How to run the script

```bash
cd packages/contracts

# 1. DRY-RUN first (simulation only — no broadcast, no funds spent):
DEPLOYER_PRIVATE_KEY=<key> \
ADMIN_MULTISIG=<0x..> QUEST_CREATOR=<0x..> \
[PAUSER=<0x..>] [VERIFIER=<0x..>] [AGENT_ID_ADDRESS=<0x..>] \
[SAFE_SINGLETON=<0x..> SAFE_PROXY_CODEHASH=<0x..>]   # local (31337) only
forge script script/DeployAgentHub.s.sol \
  --fork-url <rpc-url>   # omit for a local in-memory simulation

# 2. Only after reviewing the dry-run output AND getting explicit approval:
#    add --broadcast --verify (see §5 checklist). Never broadcast a dry-run
#    you have not read.
```

Environment variables:

| Variable                 | Required   | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------ | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DEPLOYER_PRIVATE_KEY`   | yes        | Dedicated deployer key, funded only for this deployment.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `ADMIN_MULTISIG`         | yes        | Multisig address (timelock proposer/executor + badge manager). **Validated before any deployment:** the script verifies it is a GENUINE Safe — canonical singleton (v1.3.0/v1.4.1) + canonical proxy codehash + `VERSION()` + threshold ≥ 2 (see `script/SafeValidation.sol`, `MIN_SAFE_THRESHOLD = 2`); a non-Safe, fake, or 1-of-n address reverts the deploy. A standalone pre-check exists: `forge script script/ValidateSafe.s.sol --sig "run()"` (production chains need `--fork-url`). The on-chain check proves genuineness, NOT that this is the team's Safe — the manual verification in §5.1 is still REQUIRED. |
| `SAFE_SINGLETON`         | local only | LOCAL CHAIN (31337) ONLY: expected Safe singleton for the explicit validation path. Must be UNSET on 56/97 (canonical enforcement; an explicit value reverts the deploy).                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `SAFE_PROXY_CODEHASH`    | local only | LOCAL CHAIN (31337) ONLY: expected Safe proxy codehash for the explicit validation path. Must be UNSET on 56/97.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `QUEST_CREATOR`          | yes        | Address that creates quests.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `PAUSER`                 | no         | Address that can pause QuestManager instantly. **Default (unset): the verified admin multisig** (production default, Phase 2). An explicit address overrides the default — a documented non-default configuration (see `ROLE_MATRIX.md`).                                                                                                                                                                                                                                                                                                                                                                                  |
| `VERIFIER`               | no         | First attestation verifier (VERIFIER_ROLE).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `AGENT_ID_ADDRESS`       | no         | Agent ID contract. Unset on 97/31337 = deploy MockAgentId. On 56 MUST be `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `CONFIRM_MAINNET_DEPLOY` | on 56      | Must be `true` on chain 56, otherwise the script reverts.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |

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
2. **Validators are registry-gated.** An OnChain quest's validator is
   picked by the quest creator, but it must be in the QuestManager
   validator registry (`validatorInfo`, with name/version/documentation):
   `createQuest` and quest completion both revert with
   `ValidatorNotApproved` for an unapproved validator, and revoking a
   validator takes effect immediately at completion (see
   `QUEST_VALIDATION_DESIGN.md` §2.4). The registry stops a creator
   from wiring an arbitrary always-true validator — but an approved
   validator is still trusted code: never approve a validator whose
   source you have not read, and never approve a validator you do not
   control (a third party could upgrade or replace its logic only if it
   is a proxy — prefer non-proxy validators). The validator call is a
   STATICCALL, so a validator cannot write state or reenter — but it
   can still return a wrong answer, which is why approval is a
   human review decision.
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

### 5.1 Manual Safe verification (REQUIRED — the on-chain check is not enough)

The deploy script proves `ADMIN_MULTISIG` is a GENUINE Safe proxy with a
sane threshold. It cannot prove the Safe belongs to the AGENTHUB team or
that its owners are the intended people. Do all of the following BEFORE
broadcasting, and record the evidence (screenshots / tx hashes) in the
deployment record:

1. **Open the Safe in the Safe web app** (app.safe.global, correct
   network): the address must load as a Safe with the expected owners
   and threshold. If the app does not recognize it, STOP.
2. **Confirm the owners out-of-band:** every owner address must match a
   named team member, confirmed in a second channel (not just the chat
   message that supplied the address). Threshold must be ≥ 2 (2-of-3
   recommended for testnet).
3. **Check the creation trace on BscScan:** the Safe's creation
   transaction must come from a canonical factory — SafeProxyFactory
   v1.4.1 `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67` or
   GnosisSafeProxyFactory v1.3.0
   `0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2` — with the singleton
   `0x41675C099F32341bf84BFc5382aF534df5C7461a` (v1.4.1) or
   `0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552` (v1.3.0).
4. **Run the standalone check** and keep the output:
   `ADMIN_MULTISIG=<0x..> forge script script/ValidateSafe.s.sol
--fork-url <rpc-url>` — it must print the OK line with the expected
   threshold and owner count.
5. **Test-sign with the Safe:** before the real deploy, have the owners
   execute a no-op (or the actual timelock proposal flow on testnet) to
   prove the signers can still reach quorum. A Safe nobody can sign
   with is a deployment that can never be administered.

## 6. Post-deployment steps (not in the script)

- Approve the initial validators through the timelock (2-day delay):
  deploy the `TokenBalanceValidator` instance(s) for the launch quests
  and `approveValidator` each one with name, version, and documentation
  — see `QUEST_VALIDATION_DESIGN.md` §2.4 for the list and the approval
  process. No OnChain quest can be created until at least one validator
  is approved.
- Define the first badges (`Achievement.defineBadge`, via the multisig as
  BADGE_MANAGER_ROLE).
- Grant additional verifiers through the timelock (2-day delay).
- Create the first quests (QUEST_CREATOR_ROLE): at least one of each
  ValidationKind, and verify one completion of each kind on testnet before
  mainnet.
- Set up monitoring: completion spikes, verifier activity, pause events.
- Testnet is staging: a testnet deployment does NOT authorize mainnet. The
  mainnet deployment repeats this whole checklist.
