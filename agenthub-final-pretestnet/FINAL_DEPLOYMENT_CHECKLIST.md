# AGENTHUB — Final Deployment Checklist (Phase 10)

**Status: NOT DEPLOYED. Nothing is deployed to any network.**
**Decision: CONDITIONAL GO for BNB Testnet staging** — the code is
ready; the deployment authority is not yet verified (see §1).
**Mainnet: NO-GO** until the testnet validation + the mainnet gate in
§7 are satisfied.

This checklist is the operational companion to
`docs/DEPLOYMENT_PLAN.md` (script + trust assumptions),
`docs/ROLE_MATRIX.md` (roles), `docs/SECURITY_DEPLOYMENT_GATE.md`
(mainnet gate), and `docs/VERIFIER_ROLE_SOP.md` (verifier ops). Where
this checklist and those docs disagree, the checklist's §1 status
wins — it is the newest document.

## 1. What the user must provide (BLOCKING — none received yet)

Nothing in §2–§5 can run until these are supplied. Do not substitute
placeholders.

| #   | Item                                  | Status         | Notes                                                                                                                                                                                                                     |
| --- | ------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **tBNB** for gas                      | ☐ NOT RECEIVED | Testnet deploy dry-run measured 10,294,857 gas (~0.00103 tBNB at the fork's gas price). Fund the deployer with **≥ 0.05 tBNB** (margin for verification + smoke tests). Faucet: https://testnet.bnbchain.org/faucet-smart |
| 2   | **Dedicated deployer key**            | ☐ NOT RECEIVED | Fresh key, single-use, funded only for this deployment. Never a key that holds real funds or the user's Agent ID wallet. Supply via a secure channel — never in chat.                                                     |
| 3   | **Admin multisig (Safe) address**     | ☐ NOT RECEIVED | A genuine Safe on BSC testnet (chain 97), threshold ≥ 2 (2-of-3 recommended). Must pass §3's verification BEFORE the deploy.                                                                                              |
| 4   | **Quest creator address**             | ☐ NOT RECEIVED | Address receiving QUEST_CREATOR_ROLE.                                                                                                                                                                                     |
| 5   | **First verifier address** (optional) | ☐ NOT RECEIVED | Address receiving VERIFIER_ROLE at deploy time. Can be granted later via timelock instead.                                                                                                                                |
| 6   | **Pauser address** (optional)         | ☐ NOT RECEIVED | Defaults to the admin multisig if unset (production default). Only supply if a different pauser is intended.                                                                                                              |
| 7   | **BscScan API key**                   | ☐ NOT RECEIVED | For contract verification (`--verify`). Supply via a secret manager / env, never in chat or in the repo. Testnet BscScan uses the same key as mainnet BscScan.                                                            |
| 8   | **Explicit approval to broadcast**    | ☐ NOT RECEIVED | The user inspects the source ZIP + final report first, then approves this specific testnet deployment. No approval = no broadcast.                                                                                        |

## 2. Pre-flight validation (do now, before deployment day)

These checks need no user input and no funds. All are green as of
this remediation.

| #   | Check                                       | Result                                                                                                                                                                                               | Evidence                                                 |
| --- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| 1   | Agent ID address, chain 56 (mainnet)        | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` (official, locked on-chain by `AgentGate`)                                                                                                              | `AgentGate.sol` L23; `AgentGateMainnet.t.sol` (10 tests) |
| 2   | Agent ID address, chain 97 (testnet)        | **MockAgentId**, deployed by the script when `AGENT_ID_ADDRESS` is unset. The official Agent ID does NOT exist on testnet — the frontend REJECTS the official address on chain 97 (`lib/env.ts` L62) | `DeployAgentHub.s.sol`; `lib/env.ts`                     |
| 3   | Agent ID address, chain 31337 (local)       | MockAgentId (same mechanism)                                                                                                                                                                         | `DeployLocalTestStack.s.sol`                             |
| 4   | Safe canonical singletons (v1.4.1 / v1.3.0) | `0x41675C099F32341bf84BFc5382aF534df5C7461a` / `0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552` — verified live on BSC 56 + 97                                                                           | `SAFE_VALIDATION_REVIEW.md`                              |
| 5   | Safe canonical factories                    | v1.4.1 `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67`, v1.3.0 `0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2` — verified live on BSC 56 + 97                                                              | `SAFE_VALIDATION_REVIEW.md`                              |
| 6   | Deploy script dry-run (local)               | PASS — 8,467,332 gas, 6 CREATEs + 11 wiring CALLs                                                                                                                                                    | `security-remediation-package/logs/`                     |
| 7   | Deploy script dry-run (BSC testnet fork)    | PASS — `SIMULATION COMPLETE`, 10,294,857 gas (~0.00103 BNB)                                                                                                                                          | `security-remediation-package/logs/`                     |
| 8   | Full test battery                           | 255/255 Foundry, 136 + 8 vitest, E2E 23/23, anvil 27/27 + 4/4, Slither 0 High/Medium                                                                                                                 | `FINAL_SECURITY_FINDINGS.md` §1                          |
| 9   | Secret scan                                 | 0 leaks (gitleaks, full history, with allowlist for public anvil dev keys)                                                                                                                           | `CI_EVIDENCE.md` §5                                      |
| 10  | Frontend env validation                     | Chain ↔ Agent ID consistency enforced (56 = official only, 97 = mock only); all addresses validated as EVM addresses; `NEXT_PUBLIC_DEPLOY_BLOCK` non-negative int                                   | `lib/env.ts`, `lib/env.test.ts` (17 tests)               |
| 11  | Timelock delay                              | 2 days (`TIMELOCK_DELAY = 2 days`), self-administered (no optional admin)                                                                                                                            | `DeployAgentHub.s.sol`                                   |
| 12  | Role matrix                                 | Documented + enforced by `_verifyWiring` (reverts on any mismatch)                                                                                                                                   | `docs/ROLE_MATRIX.md`, `DeployScript.t.sol`              |

## 3. Independent Safe verification (REQUIRED, before broadcast)

The deploy script proves the multisig is a GENUINE Safe; it cannot
prove it is the TEAM's Safe. Do all five steps from
DEPLOYMENT_PLAN.md §5.1 and record the evidence in the deployment
record:

- [ ] 1. Open the address in the Safe web app (app.safe.global,
     BSC testnet): it loads as a Safe with the expected owners and
     threshold. If the app does not recognize it, STOP.
- [ ] 2. Confirm every owner out-of-band (second channel, not just
     the chat message that supplied the address). Threshold ≥ 2.
- [ ] 3. BscScan creation trace: created by a canonical factory
     (§2 rows 4–5) with a canonical singleton.
- [ ] 4. Standalone check: `ADMIN_MULTISIG=<0x..> forge script
script/ValidateSafe.s.sol --fork-url <testnet-rpc>` prints
     the OK line with the expected threshold and owner count.
     Keep the output.
- [ ] 5. Test-sign with the Safe: the owners execute a no-op (or a
     test timelock proposal) to prove they can still reach quorum.

## 4. Deployment-day sequence (testnet, chain 97)

**Do not start this section without §1 item 8 (explicit approval).**
Each step has a checkbox; check it only when the step's output is
read and matches the expected result.

### 4.1 Dry run (no broadcast)

- [ ] 1. Set env (deployer key, `ADMIN_MULTISIG`, `QUEST_CREATOR`,
     optional `PAUSER`/`VERIFIER`) — from a secure source, never
     typed into a shared log.
- [ ] 2. `forge script script/DeployAgentHub.s.sol --fork-url
<testnet-rpc>` (no `--broadcast`).
- [ ] 3. Read the full dry-run output: 6 CREATEs (MockAgentId,
     AgentGate, Timelock, Reputation, Achievement, QuestManager),
     11 wiring CALLs, no `WiringCheckFailed`, no
     `NotASafe`/`UnknownSingleton`/`UnknownProxyCodehash`.
- [ ] 4. Confirm the gas estimate is within the deployer balance
     (expect ~0.001–0.002 tBNB at current testnet gas prices;
     re-check live gas price before broadcast).

### 4.2 Broadcast

- [ ] 5. Same command + `--broadcast --verify` (BscScan API key via
     env, never on the command line in a shared terminal).
- [ ] 6. Record every deployed address + tx hash in the deployment
     record (`docs/DEPLOYMENT_RECORD.md` — create it; it does not
     exist yet). Copy the addresses into `apps/web/.env.local`
     (testnet values) — see §5.2.
- [ ] 7. Verify all 6 contracts on BscScan (testnet). If `--verify`
     fails for any contract, verify manually with
     `forge verify-contract` before continuing.

### 4.3 Post-deploy on-chain verification

Read (do not write) against the live addresses and confirm each:

- [ ] 8. `AgentGate.agentIdContract()` == deployed MockAgentId.
- [ ] 9. `AgentGate.isAgentHolder(<a test Agent ID holder>)` == true;
     `isAgentHolder(<a non-holder>)` == false.
- [ ] 10. `QuestManager` dependencies: gate / reputation / achievement
      addresses match the deployed addresses.
- [ ] 11. Role matrix (every row of `docs/ROLE_MATRIX.md` via
      `hasRole`): DEFAULT_ADMIN_ROLE == timelock on all 3 contracts;
      SCORE_SOURCE_ROLE == QuestManager; ISSUER_ROLE == QuestManager;
      BADGE_MANAGER_ROLE == multisig; QUEST_CREATOR_ROLE == creator;
      PAUSER_ROLE == multisig (or the explicit pauser);
      VERIFIER_ROLE == first verifier (if set).
- [ ] 12. Deployer holds NO role on any contract.
- [ ] 13. Timelock: `getMinDelay()` == 2 days; PROPOSER_ROLE /
      CANCELLER_ROLE / EXECUTOR_ROLE == multisig; DEFAULT_ADMIN_ROLE
      == timelock itself.
- [ ] 14. `Reputation` / `Achievement` / `QuestManager` are
      unpaused (`paused() == false`).

## 5. Testnet smoke test (must pass before any mainnet talk)

### 5.1 On-chain smoke (via cast / forge script, test wallets only)

- [ ] 1. Mint test Agent IDs to 2 test wallets (MockAgentId is
     mintable by its owner — the deployer; use it only for testing).
- [ ] 2. Create one quest of EACH kind (CheckIn, OnChain, Attested)
     via QUEST_CREATOR_ROLE. For the OnChain quest: deploy a
     `TokenBalanceValidator` instance first, then approve it via a
     timelock proposal (2-day delay — start this early; it is the
     longest pole in the smoke test).
- [ ] 3. Complete the CheckIn quest from a holder wallet; verify
     points + `QuestCompleted` event.
- [ ] 4. Complete the OnChain quest from a holder with a sufficient
     token balance; verify. Also verify a holder WITHOUT the
     balance cannot complete it.
- [ ] 5. Complete the Attested quest with a real EIP-712 attestation
     from the first verifier; verify. Verify an expired attestation
     and a wrong-account attestation both revert.
- [ ] 6. Verify badge issuance: `Achievement.hasBadge` true for the
     completed quest's badge; verify a transfer attempt reverts.
- [ ] 7. Verify pause: multisig pauses QuestManager; a completion
     reverts; unpause via timelock (2-day delay — schedule it).
- [ ] 8. Verify the frontend's event queries against the live chain
     (leaderboard + tx history populate from real logs).

### 5.2 Frontend smoke (testnet env)

Set in `apps/web/.env.local` (never committed):

```text
NEXT_PUBLIC_CHAIN_ID=97
NEXT_PUBLIC_AGENT_ID_ADDRESS=<deployed MockAgentId>
NEXT_PUBLIC_AGENT_GATE_ADDRESS=<deployed AgentGate>
NEXT_PUBLIC_QUEST_MANAGER_ADDRESS=<deployed QuestManager>
NEXT_PUBLIC_REPUTATION_ADDRESS=<deployed Reputation>
NEXT_PUBLIC_ACHIEVEMENT_ADDRESS=<deployed Achievement>
NEXT_PUBLIC_DEPLOY_BLOCK=<block number of the first deployment tx>
```

- [ ] 1. `pnpm --filter web build` with the testnet env (chain 97)
     compiles; `pnpm --filter web start` serves.
- [ ] 2. Connect a test wallet (Binance Wallet / MetaMask, testnet
     network): holder status shows correctly for a holder and a
     non-holder.
- [ ] 3. Wrong-network banner appears on mainnet (chain 56) and the
     one-click switch works.
- [ ] 4. `/quests` shows the 3 live quests with correct eligibility;
     a CheckIn completion succeeds end-to-end (wallet prompt →
     tx → confirmation → points update).
- [ ] 5. Attestation flow: paste a real attestation → signer
     verified → submit → completion confirmed.
- [ ] 6. `/leaderboard`, `/dashboard`, `/profile`, `/history` show
     live data from testnet events (not the static preview).
- [ ] 7. Confirm the static preview is gone wherever a contract is
     configured (no page claims live data it does not have).

## 6. Rollback / incident notes (testnet)

- The contracts are **immutable** — there is no upgrade path. A
  wiring mistake is fixed by REDEPLOYING (new addresses) and
  updating the frontend env. Budget for at least one redeploy.
- The only fast incident control is **pause** (multisig, no
  delay). Unpause costs 2 days (timelock). Do not pause on testnet
  unless the smoke test requires it — the 2-day unpause blocks the
  rest of the smoke test.
- A compromised verifier key: revoke VERIFIER_ROLE via timelock
  (2 days) — or pause immediately while the revocation is queued.
  See `VERIFIER_SECURITY_SOP.md` §5.
- A compromised quest-creator key: revoke QUEST_CREATOR_ROLE via
  timelock; deactivate the malicious quests (admin, timelock);
  pause if completions are being farmed.
- A lost multisig: the deployment cannot be administered. On
  testnet, redeploy with a new multisig. On mainnet this would be
  catastrophic — multisig custody is a pre-mainnet requirement.

## 7. Mainnet gate (NOT part of this deployment)

Testnet success does NOT authorize mainnet. Before any mainnet
broadcast, ALL of the following must hold (see
`docs/SECURITY_DEPLOYMENT_GATE.md` for the full gate):

1. Testnet smoke test (§5) fully green, including the 2-day
   timelock flows (validator approval + unpause).
2. External security review of the contracts (R-012) — no review
   has been commissioned yet.
3. Dependency upgrades (DEP-001/002/003) landed + `pnpm audit`
   clean at `--audit-level=high` + `scripts/osv-audit.mjs` re-run.
4. Threshold (M-of-N) attestation implemented before any attested
   quest with rewardPoints > 1,000 or a real-world-value badge
   goes live (R-010).
5. Mainnet multisig created + independently verified (§3, on
   chain 56) + owners confirmed out-of-band.
6. Monitoring + incident response plan in place (completion
   spikes, verifier activity, pause events — see
   `VERIFIER_SECURITY_SOP.md` §6).
7. BSC mainnet gas + deployer funding arranged (mainnet deploy is
   ~10.3M gas at mainnet prices — budget accordingly).
8. Explicit user approval for the MAINNET broadcast (a separate
   approval from the testnet one).
9. `CONFIRM_MAINNET_DEPLOY=true` set deliberately at broadcast
   time (the script enforces it).

## 8. What this checklist does NOT authorize

- It does not authorize a broadcast. Only the user's explicit
  approval for this specific deployment does (§1 item 8).
- It does not authorize mainnet. See §7.
- It does not authorize spending real funds. Testnet only (tBNB
  has no monetary value).
- It does not authorize using the user's personal wallet (namexs.ai)
  as the deployer. The deployer is a dedicated, single-use key.
