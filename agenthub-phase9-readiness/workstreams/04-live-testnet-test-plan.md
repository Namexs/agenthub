# AGENTHUB — Phase 9, Workstream 4: Live Testnet Test Plan

**Status: NOT RUN.** This is the procedure to execute on BNB Testnet
(chain 97) after the user gives explicit approval to broadcast. Every
**HASIL AKTUAL** and **TX HASH** column in this document is intentionally
left **EMPTY** — no live result has been fabricated. Fill them in during
the run; the completed document is the evidence that closes R-010.

**Code under test:** repo `~/workspace/agenthub/`, HEAD `e1b316b`
(Phase 8 final), Solidity **0.8.39**, `via_ir = true`,
`evm_version = "cancun"`. Deploy script
`packages/contracts/script/DeployAgentHub.s.sol`.
Companion documents: `agenthub-final-pretestnet/FINAL_DEPLOYMENT_CHECKLIST.md`
(§1 user inputs, §3 Safe verification, §4 deployment-day sequence,
§5.1 smoke steps 9–11), `agenthub-phase8-remediation/PHASE8_SECURITY_REMEDIATION_REPORT.md`
(§2 H01/M01/L07), `docs/ROLE_MATRIX.md`, `docs/VERIFIER_ROLE_SOP.md`.

**Fork dry-run:** this exact procedure was validated end-to-end against
a local anvil fork of BSC testnet (chain 97) on 2026-11-20 — **90/90
checks PASS**. See the separate report
[`04-live-testnet-test-plan-fork-dryrun.md`](./04-live-testnet-test-plan-fork-dryrun.md).
The dry-run proves the commands, the expected values, and the revert
selectors; it does NOT prove anything about the live chain. The live
run must still be executed in full.

## 0. How to use this plan

**Conventions.** All shell commands run from
`packages/contracts/` unless stated otherwise, with
`forge`/`cast`/`anvil` from `~/.foundry/bin` on `PATH`
(`export PATH="$HOME/.foundry/bin:$PATH"`). `<PLACEHOLDER>` values are
filled from §1 / S1 as the run proceeds. `cast call` outputs are
compared exactly as printed; large `uint256` values print with a
scientific-notation suffix, e.g. `172800 [1.728e5]` — compare the
first token only.

**Placeholders (fill at S1, reuse everywhere):**

| Placeholder       | Meaning                                            | Value (fill at S1)                                                                                     |
| ----------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `$RPC`            | BSC testnet RPC                                    | `https://bsc-testnet-rpc.publicnode.com` (fallback: `https://data-seed-prebsc-1-s1.bnbchain.org:8545`) |
| `$ADMIN_SAFE`     | Admin multisig (Safe, ≥ 2-of-3)                    |                                                                                                        |
| `$CREATOR_SAFE`   | Quest-creator Safe (≥ 2-of-3, distinct from admin) |                                                                                                        |
| `$DEPLOYER`       | Dedicated single-use deployer address              |                                                                                                        |
| `$V1` / `$V2`     | Verifier 1 / verifier 2 addresses                  |                                                                                                        |
| `$ALICE` / `$BOB` | Test holder wallets (funded with tBNB)             |                                                                                                        |
| `$MOCK`           | Deployed MockAgentId                               |                                                                                                        |
| `$GATE`           | Deployed AgentGate                                 |                                                                                                        |
| `$TIMELOCK`       | Deployed TimelockController                        |                                                                                                        |
| `$REP`            | Deployed Reputation                                |                                                                                                        |
| `$ACH`            | Deployed Achievement                               |                                                                                                        |
| `$QM`             | Deployed QuestManager                              |                                                                                                        |
| `$DEPLOY_BLOCK`   | Block of the first deployment tx                   |                                                                                                        |

**Rules of the run.**

1. **No step runs before §1 item 8 (explicit broadcast approval).**
   The deploy script itself enforces `CONFIRM_TESTNET_DEPLOY=true`
   (PH7-M05) — the guard cannot be skipped, even for the dry-run.
2. **Stop on any unexpected result.** Do not "fix forward" by
   re-running a failed step with different parameters. Record the
   actual result, stop, and escalate. The contracts are immutable —
   a wiring mistake is fixed by REDEPLOYING (new addresses), never by
   patching.
3. **One scenario at a time, in order.** Later scenarios depend on
   earlier state (quest IDs, verifier count, timelock operations).
   The order below is load-bearing; §2 explains the timelock
   critical path.
4. **Every state-changing step is recorded** with its tx hash in the
   scenario's table the moment it lands. A step without a recorded
   tx hash is not done.
5. **Attestations are signed fresh, on the day of the completion.**
   An attestation binds account + questId + nonce + deadline; a
   deadline is at most 7 days out (`MAX_ATTESTATION_LIFETIME`), and
   the nonce changes after every attested completion. Never reuse a
   signature from an earlier day.
6. **Never use the user's personal wallet** (namexs.ai) as deployer,
   test holder, or verifier. All actors are dedicated test wallets /
   Safes funded only with tBNB.

## 1. Prerequisites (all blocking, before S1)

From `FINAL_DEPLOYMENT_CHECKLIST.md` §1 — none of these may be
substituted with placeholders:

| #   | Item                                                                                                                                                                                                                                        | Status |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 1   | tBNB for gas — deployer funded with **≥ 0.05 tBNB** (deploy measured 8,307,890 gas on the fork dry-run, ~0.00083 tBNB at 0.1 gwei; the margin covers verification + the full smoke test). Faucet: https://testnet.bnbchain.org/faucet-smart | ☐      |
| 2   | Dedicated single-use deployer key (fresh; never a key holding real funds or the user's Agent ID wallet). Supplied via a secure channel, never in chat.                                                                                      | ☐      |
| 3   | Admin multisig (Safe) address on chain 97, threshold ≥ 2, independently verified per checklist §3 (Safe web app + out-of-band owner confirmation + BscScan creation trace + `ValidateSafe.s.sol` + test-sign).                              | ☐      |
| 4   | Quest-creator Safe address on chain 97, threshold ≥ 2, DISTINCT from the admin Safe, verified the same way. The deploy script rejects an EOA or non-Safe creator (PH7-M03).                                                                 | ☐      |
| 5   | First verifier address (`VERIFIER`, granted at deploy).                                                                                                                                                                                     | ☐      |
| 6   | Second verifier address (granted via timelock before S7 — needed for every threshold-2 step).                                                                                                                                               | ☐      |
| 7   | BscScan API key (via `BSCSCAN_API_KEY` env, never on a shared command line or in the repo).                                                                                                                                                 | ☐      |
| 8   | **Explicit user approval to broadcast this specific testnet deployment.**                                                                                                                                                                   | ☐      |

**Test wallets.** Two fresh EOAs, each funded with ~0.02 tBNB for gas:

| Wallet   | Role in this plan                                                                                 |
| -------- | ------------------------------------------------------------------------------------------------- |
| `$ALICE` | Holder 1. Completes Q1 (S6) and Q2 (S8); is the blocked party in S13.                             |
| `$BOB`   | Holder 2. Attempts the revert cases in S9/S10 (fresh nonce, no completions); completes Q5 in S13. |

Both receive a test Agent ID (minted by the admin Safe) before S5.
Neither wallet holds anything else; both keys are test-only.

**Tooling.** Foundry from `~/.foundry/bin` (`forge`, `cast`),
`solc 0.8.39` (pinned in `foundry.toml`), `jq`, `python3`.
Safe web app: https://app.safe.global (BSC Testnet network).
BscScan testnet: https://testnet.bscscan.com.

## 2. Timeline — the timelock critical path

`TIMELOCK_DELAY` is **2 days** (172,800 s). Four timelock operations
are required, and three of them sit on the critical path:

| Op   | Operation                                  | Scheduled | Executable | Gates                                          |
| ---- | ------------------------------------------ | --------- | ---------- | ---------------------------------------------- |
| OP-1 | `grantRole(VERIFIER_ROLE, $V2)`            | Day 0     | Day 2      | S7–S13 (threshold-2 quests need 2 verifiers)   |
| OP-2 | `revokeRole(VERIFIER_ROLE, $V2)`           | Day 2     | Day 4      | S12 (the guardrail proof happens at execution) |
| OP-3 | `grantRole(VERIFIER_ROLE, $V2)` (re-grant) | Day 4     | Day 6      | Final state (restores 2 verifiers)             |
| OP-4 | `setSupersedes(5, 2)`                      | Day 4     | Day 6      | S13 (the link is admin-only)                   |

**Sequential schedule (primary — follows the scenario order):**

| Day                    | Work                                                                                                                    | Scenarios                    |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| **Day 0** (deploy day) | Deploy + verify + mint Agent IDs; schedule OP-1                                                                         | S1, S2, S3, S4, setup        |
| **Day 2**              | Execute OP-1; create + complete T1/T2 quests; revert proofs; H01 proof; schedule OP-2                                   | S5, S6, S7, S8, S9, S10, S11 |
| **Day 4**              | Execute OP-2 → **REVERTS** (S12 proof); deactivate Q2 + Q3; re-execute OP-2 → succeeds; create Q5; schedule OP-3 + OP-4 | S12, S13 setup               |
| **Day 6**              | Execute OP-3 + OP-4; S13 completion checks; final BscScan sweep                                                         | S13 checks, S14              |

**Total: ~6 calendar days from deploy approval to full green.**
Active operator time is ~3–3.5 hours spread across the four working
days; the rest is timelock waiting. Per-scenario active time is noted
in each scenario header.

**Compressed schedule (optional — saves 2 days):** on Day 2, in
addition to S5–S11, schedule OP-3 (re-grant V2 — it is a no-op if
executed while V2 still holds the role, so execution order on Day 4
matters, see below), create Q5, and schedule OP-4 (the quest IDs are
predictable on a fresh deploy: Q5 is the 5th quest). On Day 4,
execute in this order: OP-2 (blocked → deactivate Q2+Q3 →
re-execute, succeeds), then OP-3 (now the grant takes effect),
then OP-4 (the supersedes link), then run the S13 completion checks
and S14. Total: **~4 calendar days**. ⚠️ Two cautions: (1) Q5 exists
from Day 2 without its supersedes link until Day 4 — **nobody may
complete Q5 before OP-4 executes**, because the link is not
retroactive (accounts that completed Q5 before the link keep their
completion). (2) On Day 4, OP-3 must execute **after** OP-2's
successful re-execution — executing OP-3 first would be a no-op
(V2 still holds the role) and the deployment would end with 1
verifier. If either discipline cannot be guaranteed, use the
sequential schedule.

**What the timelock does NOT delay:** Safe-direct actions need no
timelock — minting test Agent IDs (MockAgentId owner = admin Safe),
creating quests (creator Safe), deactivating quests (creator Safe),
and pausing (pauser = admin Safe). Only DEFAULT_ADMIN_ROLE actions
(grant/revoke roles, `setSupersedes`, validator approval) go through
the timelock.

## 3. Fixtures — quest plan and constants

Quest IDs are **1-based and sequential** on a fresh deploy
(`questId = ++_questCount`). If a redeploy happens, renumber from
the live `questCount()`. All five quests are `QuestType.OneTime` (1),
`ValidationKind.Attested` (2), `validator = address(0)`, `badgeId = 0`,
`maxCompletions = 0` (unlimited), window `startTime = now`,
`endTime = now + 30 days`.

| ID  | Title                 | Reward | Threshold | Created in | Purpose                                                |
| --- | --------------------- | ------ | --------- | ---------- | ------------------------------------------------------ |
| Q1  | `Smoke T1`            | 100    | 1         | S5         | Threshold-1 happy path                                 |
| Q2  | `Smoke T2`            | 100    | 2         | S7         | Threshold-2 happy path; the "old" quest for S12/S13    |
| Q3  | `High T2 control`     | 1,001  | 2         | S11        | H01 positive control (1,001 pts needs T2)              |
| Q4  | `Boundary T1 control` | 1,000  | 1         | S11        | H01 boundary control (exactly 1,000 is NOT high-value) |
| Q5  | `Smoke T1 recreate`   | 100    | 1         | S13        | Recreate of Q2; linked via `setSupersedes(5, 2)`       |

**Constants (from `QuestManager.sol`):**

| Constant                        | Value                                                                            |
| ------------------------------- | -------------------------------------------------------------------------------- |
| `MAX_REWARD_POINTS`             | 10,000                                                                           |
| `HIGH_VALUE_REWARD_POINTS`      | 1,000 (policy: Attested + reward > 1,000 ⇒ threshold ≥ 2)                        |
| `MIN/MAX_ATTESTATION_THRESHOLD` | 1 / 3                                                                            |
| `MAX_ATTESTATION_SIGNATURES`    | 5                                                                                |
| `MAX_ATTESTATION_LIFETIME`      | 7 days                                                                           |
| EIP-712 domain                  | name `AGENTHUB QuestManager`, version `1`, chainId 97, verifyingContract `$QM`   |
| `ATTESTATION_TYPEHASH`          | `0x7b0b621fd3b4b00f1d27a6f5af159d86d871bcac3a8a7088aeb3461b88ebaac2`             |
| Attestation struct              | `Attestation(address account, uint256 questId, uint256 nonce, uint256 deadline)` |

**Role hashes** (Appendix A) and **error selectors** (Appendix B)
are tabulated at the end of this document; they are needed for S3
and for the revert scenarios S9–S13.

---

## S1 — Deploy all contracts

**Goal:** deploy the full AGENTHUB stack to BSC testnet (chain 97)
with the production deploy script, and verify all 6 contracts on
BscScan. **Active time: ~30–45 min** (includes a ~5 min via-IR build
on a cold cache).

**Prerequisites:** §1 items 1–8 all satisfied; both Safes verified
(checklist §3); working tree clean at HEAD `e1b316b`
(`git status` clean, `git log -1 --oneline` shows `e1b316b`).

**⚠️ Deploy order — read this.** The deploy script deploys in
dependency order:

```
MockAgentId → AgentGate → TimelockController → Reputation
            → Achievement → QuestManager
```

QuestManager is deployed LAST because its constructor takes the
gate, reputation, and achievement addresses. (An earlier shorthand
listed "AgentGate → QuestManager → Reputation → Achievement" — that
order is not what the script does and is not deployable; the order
above is the script's actual order, confirmed in
`DeployAgentHub.s.sol` and in the fork dry-run.)

**Steps.**

1. Dry-run (no broadcast — the M05 guard still requires the env var):
   ```bash
   cd packages/contracts
   DEPLOYER_PRIVATE_KEY=<key> ADMIN_MULTISIG=$ADMIN_SAFE QUEST_CREATOR=$CREATOR_SAFE \
     VERIFIER=$V1 CONFIRM_TESTNET_DEPLOY=true \
     forge script script/DeployAgentHub.s.sol --fork-url $RPC
   ```
   Expected: `SIMULATION COMPLETE`, **6 CREATEs** (MockAgentId,
   AgentGate, Timelock, Reputation, Achievement, QuestManager) and
   **13 wiring CALLs** (12 + the VERIFIER grant), no
   `WiringCheckFailed`, no `NotASafe` / `UnknownSingleton` /
   `UnknownProxyCodehash` / `TestnetDeployNotConfirmed`. Total gas
   ≈ 8.3M (fork dry-run measured 8,307,890 with VERIFIER set).
   Confirm the gas cost fits the deployer balance before proceeding.
2. Broadcast + verify:
   ```bash
   BSCSCAN_API_KEY=<key> DEPLOYER_PRIVATE_KEY=<key> \
     ADMIN_MULTISIG=$ADMIN_SAFE QUEST_CREATOR=$CREATOR_SAFE \
     VERIFIER=$V1 CONFIRM_TESTNET_DEPLOY=true \
     forge script script/DeployAgentHub.s.sol --fork-url $RPC \
     --broadcast --verify
   ```
   (`foundry.toml` maps `BSCSCAN_API_KEY` to the `bsc-testnet`
   Etherscan config; `--verify` uses it. The key must never appear
   on a shared command line — export it from a secret manager.)
3. Record every deployed address + tx hash below, and copy the
   addresses into `apps/web/.env.local` (testnet values, see
   checklist §5.2) and into `docs/DEPLOYMENT_RECORD.md` (create it;
   it does not exist yet). Record `$DEPLOY_BLOCK` (block of the
   first deployment tx — needed for S14 event queries).
4. If `--verify` fails for any contract, verify it manually before
   continuing (constructor args come from the broadcast JSON —
   `broadcast/DeployAgentHub.s.sol/97/run-latest.json`,
   `transactions[].arguments`):
   ```bash
   forge verify-contract <address> <ContractName> \
     --chain 97 --constructor-args <args-from-broadcast-json>
   ```
   Constructor signatures: `MockAgentId()` (none);
   `AgentGate(address,uint256)`; `TimelockController(uint256,address[],address[],address)`;
   `Reputation(address)`; `Achievement(address)`;
   `QuestManager(address,address,address,address)`.

**Expected values:** 6 contracts deployed; `_verifyWiring` passed
(the script reverts otherwise); all 6 verified on BscScan testnet
(green checkmark on each contract page).

| Contract                   | Address (HASIL AKTUAL) | Deploy tx hash (HASIL AKTUAL) | BscScan verified (HASIL AKTUAL) |
| -------------------------- | ---------------------- | ----------------------------- | ------------------------------- |
| MockAgentId                |                        |                               | ☐                               |
| AgentGate                  |                        |                               | ☐                               |
| TimelockController         |                        |                               | ☐                               |
| Reputation                 |                        |                               | ☐                               |
| Achievement                |                        |                               | ☐                               |
| QuestManager               |                        |                               | ☐                               |
| **Deploy block**           |                        | **Total gas**                 |                                 |
| **Deployer balance after** |                        |                               |                                 |

---

## S2 — Verify all deployed addresses

**Goal:** prove the deployed addresses are wired to each other
exactly as deployed — read on-chain, compare against the S1 output.
**Active time: ~10 min.** Read-only (`cast call`).

**Prerequisites:** S1 complete.

**Steps** (run each; compare against the S1 table):

```bash
cast call $GATE "agentIdContract()(address)" --rpc-url $RPC
cast call $GATE "expectedChainId()(uint256)" --rpc-url $RPC
cast call $QM "gate()(address)" --rpc-url $RPC
cast call $QM "reputation()(address)" --rpc-url $RPC
cast call $QM "achievement()(address)" --rpc-url $RPC
cast call $QM "questCount()(uint256)" --rpc-url $RPC
```

| Check                    | Expected            | HASIL AKTUAL |
| ------------------------ | ------------------- | ------------ |
| `gate.agentIdContract()` | `$MOCK`             |              |
| `gate.expectedChainId()` | `97`                |              |
| `qm.gate()`              | `$GATE`             |              |
| `qm.reputation()`        | `$REP`              |              |
| `qm.achievement()`       | `$ACH`              |              |
| `qm.questCount()`        | `0` (no quests yet) |              |

---

## S3 — Verify ownership + roles

**Goal:** prove the role matrix (`docs/ROLE_MATRIX.md`) holds
on-chain and the deployer ends with **zero privilege** (PH7-M04).
**Active time: ~15 min.** Read-only.

**Prerequisites:** S1 complete.

**Steps.** `hasRole(bytes32,address)` with the role hashes from
Appendix A (or read the role constants from the contracts, e.g.
`cast call $QM "VERIFIER_ROLE()(bytes32)"`):

```bash
# Ownership (PH7-M04)
cast call $MOCK "owner()(address)" --rpc-url $RPC
# Admin is the timelock on all three AccessControl contracts
cast call $QM  "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 $TIMELOCK --rpc-url $RPC
cast call $REP "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 $TIMELOCK --rpc-url $RPC
cast call $ACH "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 $TIMELOCK --rpc-url $RPC
# Operational roles
cast call $REP "hasRole(bytes32,address)(bool)" 0x08dd1ffd17984138218681c16863231d15b3a8b44885cf4e34e2804b0b15faa9 $QM --rpc-url $RPC
cast call $ACH "hasRole(bytes32,address)(bool)" 0x114e74f6ea3bd819998f78687bfcb11b140da08e9b7d222fa9c1f1ba1f2aa122 $QM --rpc-url $RPC
cast call $ACH "hasRole(bytes32,address)(bool)" 0xa00144c395da084768e13ed238fd3b1cd040ce840901c1170be1eceffc7a7ded $ADMIN_SAFE --rpc-url $RPC
cast call $QM  "hasRole(bytes32,address)(bool)" 0x4112259a34054d6040a76e8d985093c9e8b0a52d820e856d7f4230fcaef428de $CREATOR_SAFE --rpc-url $RPC
cast call $QM  "hasRole(bytes32,address)(bool)" 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a $ADMIN_SAFE --rpc-url $RPC
cast call $QM  "hasRole(bytes32,address)(bool)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $V1 --rpc-url $RPC
# Deployer holds NOTHING (every row must be false)
for C in $QM $REP $ACH $TIMELOCK; do
  cast call $C "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 $DEPLOYER --rpc-url $RPC
done
cast call $QM "hasRole(bytes32,address)(bool)" 0x4112259a34054d6040a76e8d985093c9e8b0a52d820e856d7f4230fcaef428de $DEPLOYER --rpc-url $RPC
cast call $QM "hasRole(bytes32,address)(bool)" 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a $DEPLOYER --rpc-url $RPC
cast call $QM "hasRole(bytes32,address)(bool)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $DEPLOYER --rpc-url $RPC
# Unpaused
cast call $QM "paused()(bool)" --rpc-url $RPC
cast call $REP "paused()(bool)" --rpc-url $RPC
cast call $ACH "paused()(bool)" --rpc-url $RPC
```

| Check                                       | Expected                                                                          | HASIL AKTUAL |
| ------------------------------------------- | --------------------------------------------------------------------------------- | ------------ |
| `mock.owner()`                              | `$ADMIN_SAFE`                                                                     |              |
| `QM/REP/ACH DEFAULT_ADMIN_ROLE`             | `$TIMELOCK` (all three `true`)                                                    |              |
| `REP SCORE_SOURCE_ROLE`                     | `$QM`                                                                             |              |
| `ACH ISSUER_ROLE`                           | `$QM`                                                                             |              |
| `ACH BADGE_MANAGER_ROLE`                    | `$ADMIN_SAFE`                                                                     |              |
| `QM QUEST_CREATOR_ROLE`                     | `$CREATOR_SAFE`                                                                   |              |
| `QM PAUSER_ROLE`                            | `$ADMIN_SAFE` (production default; or the explicit `$PAUSER` if one was supplied) |              |
| `QM VERIFIER_ROLE`                          | `$V1`                                                                             |              |
| Deployer: admin on QM/REP/ACH/Timelock      | `false` × 4                                                                       |              |
| Deployer: creator / pauser / verifier on QM | `false` × 3                                                                       |              |
| `paused()` on QM / REP / ACH                | `false` × 3                                                                       |              |

Once this table is green, the deployer key may be discarded — it
holds no privilege anywhere.

---

## S4 — Verify the timelock

**Goal:** prove the timelock is a 2-day, self-administered
TimelockController with the admin Safe as proposer, executor, and
canceller. **Active time: ~5 min.** Read-only.

**Prerequisites:** S1 complete.

```bash
cast call $TIMELOCK "getMinDelay()(uint256)" --rpc-url $RPC
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" 0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1 $ADMIN_SAFE --rpc-url $RPC
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" 0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63 $ADMIN_SAFE --rpc-url $RPC
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" 0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783 $ADMIN_SAFE --rpc-url $RPC
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 $TIMELOCK --rpc-url $RPC
cast call $TIMELOCK "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 $ADMIN_SAFE --rpc-url $RPC
```

| Check                                      | Expected                                                          | HASIL AKTUAL |
| ------------------------------------------ | ----------------------------------------------------------------- | ------------ |
| `getMinDelay()`                            | `172800` (2 days)                                                 |              |
| `PROPOSER_ROLE`                            | `$ADMIN_SAFE`                                                     |              |
| `EXECUTOR_ROLE`                            | `$ADMIN_SAFE`                                                     |              |
| `CANCELLER_ROLE`                           | `$ADMIN_SAFE` (OZ grants it to every proposer in the constructor) |              |
| `DEFAULT_ADMIN_ROLE`                       | `$TIMELOCK` itself (self-administered)                            |              |
| `DEFAULT_ADMIN_ROLE` held by `$ADMIN_SAFE` | `false`                                                           |              |

---

## Setup A — Mint test Agent IDs (Day 0, after S4)

**Goal:** `$ALICE` and `$BOB` each hold one test Agent ID so they
can complete quests. No timelock: `MockAgentId.mint` is `onlyOwner`
and the owner is the admin Safe (PH7-M04).

**Steps (Safe UI — see Appendix F):** from the admin Safe, two
contract interactions to `$MOCK`: `mint($ALICE)`, `mint($BOB)`.
Owners confirm + execute each (2-of-3 quorum).

**Verify:**

```bash
cast call $GATE "isAgentHolder(address)(bool)" $ALICE --rpc-url $RPC   # true
cast call $GATE "isAgentHolder(address)(bool)" $BOB --rpc-url $RPC     # true
cast call $GATE "isAgentHolder(address)(bool)" $DEPLOYER --rpc-url $RPC # false
```

| Step                       | TX HASH (HASIL AKTUAL) | HASIL AKTUAL                 |
| -------------------------- | ---------------------- | ---------------------------- |
| `mint($ALICE)` (tokenId 1) |                        | `isAgentHolder($ALICE)` =    |
| `mint($BOB)` (tokenId 2)   |                        | `isAgentHolder($BOB)` =      |
| Negative control           | —                      | `isAgentHolder($DEPLOYER)` = |

## Setup B — Schedule OP-1: grant verifier 2 (Day 0)

**Goal:** start the 2-day clock for the second verifier, so it is
live on Day 2. `DeployAgentHub` grants at most one verifier, and
`createQuest` for a threshold-2 quest reverts while fewer than 2
verifiers exist (`InsufficientVerifiers`, PH7-M01) — so OP-1 must
be scheduled on deploy day.

**Steps.**

1. Compute the calldata (offline, no chain interaction):
   ```bash
   cast calldata "grantRole(bytes32,address)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $V2
   ```
2. From the admin Safe (Safe UI, contract interaction to
   `$TIMELOCK`), call `schedule` with:
   - `target` = `$QM`, `value` = `0`, `data` = calldata from step 1,
   - `predecessor` = `0x0000…0000` (32 zero bytes),
   - `salt` = `cast keccak "agenthub-smoke-grant-v2"` (record it below),
   - `delay` = `172800`.
     Owners confirm + execute.
3. Verify the operation exists and is Waiting:
   ```bash
   cast call $TIMELOCK "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" $QM 0 <data> 0x0000…0000 <salt> --rpc-url $RPC
   cast call $TIMELOCK "getOperationState(bytes32)(uint8)" <op-id> --rpc-url $RPC   # 1 = Waiting
   cast call $TIMELOCK "getTimestamp(bytes32)(uint256)" <op-id> --rpc-url $RPC      # ≈ now + 172800
   ```
   (`OperationState`: 0 Unset, 1 Waiting, 2 Ready, 3 Done.)

| Item                                            | HASIL AKTUAL |
| ----------------------------------------------- | ------------ |
| OP-1 salt                                       |              |
| OP-1 id (`hashOperation`)                       |              |
| OP-1 schedule tx hash                           |              |
| `getOperationState` after schedule (expect `1`) |              |
| `getTimestamp` (expect ≈ Day 0 + 2 days)        |              |

---

## S5 — Create an Attested threshold-1 quest

**Goal:** the creator Safe publishes Q1 (`Smoke T1`, 100 points,
threshold 1). **Active time: ~10 min.** (Day 2, after OP-1 executes
— see note.)

**Prerequisites:** OP-1 executed (Day 2). Strictly, a threshold-1
quest only needs 1 verifier, so S5 could run on Day 0 — but the
plan keeps all quest activity on Day 2 so the Day 2 working session
is a single block. If Day 0 time allows, S5 may be pulled forward;
nothing else changes.

**Execute OP-1 first (Day 2):** from the admin Safe, contract
interaction to `$TIMELOCK`: `execute($QM, 0, <grant calldata>,
0x0000…0000, <OP-1 salt>)` — same parameters as the schedule call.
Verify afterwards:

```bash
cast call $TIMELOCK "getOperationState(bytes32)(uint8)" <OP-1 id> --rpc-url $RPC  # 3 = Done
cast call $QM "hasRole(bytes32,address)(bool)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $V2 --rpc-url $RPC  # true
cast call $QM "verifierCount()(uint256)" --rpc-url $RPC  # 2
```

| Item         | TX HASH (HASIL AKTUAL) | HASIL AKTUAL                              |
| ------------ | ---------------------- | ----------------------------------------- |
| OP-1 execute |                        | `getOperationState` = ; `verifierCount` = |

**Create Q1.** From the creator Safe (Safe UI, contract interaction
to `$QM`), call `createQuest` with:

| Parameter              | Value                                            |
| ---------------------- | ------------------------------------------------ |
| `title`                | `Smoke T1`                                       |
| `description`          | `Live testnet smoke: threshold-1 attested quest` |
| `questType`            | `1` (OneTime)                                    |
| `validationKind`       | `2` (Attested)                                   |
| `validator`            | `0x0000000000000000000000000000000000000000`     |
| `rewardPoints`         | `100`                                            |
| `badgeId`              | `0`                                              |
| `startTime`            | current Unix time (`date +%s`)                   |
| `endTime`              | `startTime + 2592000` (30 days)                  |
| `maxCompletions`       | `0`                                              |
| `attestationThreshold` | `1`                                              |

Equivalent `cast` form (for reference — the live call goes through
the Safe UI; `cast` cannot sign for a Safe):

```bash
cast send $QM "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "Smoke T1" "Live testnet smoke: threshold-1 attested quest" 1 2 0x0000000000000000000000000000000000000000 \
  100 0 $START $END 0 1 --rpc-url $RPC   # sender must be $CREATOR_SAFE
```

**Verify:**

```bash
cast call $QM "questCount()(uint256)" --rpc-url $RPC  # 1
cast call $QM "getQuest(uint256)((uint256,address,string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint8))" 1 --rpc-url $RPC
# expect: (1, $CREATOR_SAFE, "Smoke T1", ..., 1, 2, 0x0.., 100, 0, <start>, <end>, 0, 0, true, 1)
cast call $QM "highestLiveThreshold()(uint8)" --rpc-url $RPC  # 1
```

| Check                                     | Expected                                       | HASIL AKTUAL |
| ----------------------------------------- | ---------------------------------------------- | ------------ |
| Q1 create tx hash                         | —                                              |              |
| `questCount()`                            | `1`                                            |              |
| `getQuest(1)` threshold / reward / active | `1` / `100` / `true`                           |              |
| `highestLiveThreshold()`                  | `1`                                            |              |
| `QuestCreated` event (S14)                | questId 1, creator `$CREATOR_SAFE`, reward 100 |              |

---

## S6 — Complete the threshold-1 quest (one verifier)

**Goal:** `$ALICE` completes Q1 with a single EIP-712 attestation
from verifier 1. Proves the threshold-1 happy path end to end:
sign → submit → points + events. **Active time: ~10 min.**

**Prerequisites:** S5 complete; `$ALICE` holds a test Agent ID.

**Steps.**

1. Read Alice's current nonce and pick a deadline (now + 1 day,
   well inside the 7-day maximum):
   ```bash
   cast call $QM "nonces(address)(uint256)" $ALICE --rpc-url $RPC   # expect 0
   DL=$(( $(date +%s) + 86400 ))
   ```
2. Verifier 1 signs the attestation. Typed-data JSON
   (Appendix C — fill in `$QM`, `$ALICE`, questId `1`, nonce `0`,
   deadline `$DL`), then:
   ```bash
   cast wallet sign --data --from-file attestation-q1-alice.json --private-key $V1_KEY
   ```
   (The verifier's key never leaves the verifier. Alternatively the
   verifier signs with their wallet's EIP-712 prompt
   — `signTypedData` with the same domain + message — and sends
   only the 65-byte signature back. The frontend's AttestationForm
   can verify the signature client-side before submit.)
   Sanity-check the signature before submitting:
   ```bash
   cast wallet verify --data --from-file attestation-q1-alice.json --address $V1 <signature>
   cast call $QM "hasRole(bytes32,address)(bool)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $V1 --rpc-url $RPC
   ```
3. Alice submits from her test wallet:
   ```bash
   cast send $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 1 $DL "[<signature>]" \
     --private-key $ALICE_KEY --rpc-url $RPC
   ```
   (Or via the frontend AttestationForm: paste signature + deadline,
   submit. Either route lands the same call.)
4. Verify:
   ```bash
   cast call $REP "points(address)(uint256)" $ALICE --rpc-url $RPC       # 100
   cast call $QM "hasCompleted(address,uint256)(bool)" $ALICE 1 --rpc-url $RPC  # true
   cast call $QM "nonces(address)(uint256)" $ALICE --rpc-url $RPC        # 1
   ```

| Check                                                                                | Expected                                                                                                        | HASIL AKTUAL |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- | ------------ |
| Alice nonce before                                                                   | `0`                                                                                                             |              |
| Deadline used                                                                        | now + 1 day                                                                                                     |              |
| S6 completion tx hash                                                                | —                                                                                                               |              |
| Gas used (reference: 244,840 fresh-account benchmark; fork dry-run measured 235,990) |                                                                                                                 |              |
| `points($ALICE)`                                                                     | `100`                                                                                                           |              |
| `hasCompleted($ALICE, 1)`                                                            | `true`                                                                                                          |              |
| Alice nonce after                                                                    | `1`                                                                                                             |              |
| Events (S14)                                                                         | `QuestCompleted(1, $ALICE, 100, 0)` + `PointsAdded($ALICE, 1, 100, 100)` + `AttestationUsed($ALICE, 1, 0, $V1)` |              |

---

## S7 — Create an Attested threshold-2 quest

**Goal:** the creator Safe publishes Q2 (`Smoke T2`, 100 points,
threshold 2). Proves threshold-2 creation works once 2 verifiers
exist (the M01 creation guard would have reverted this on Day 0).
**Active time: ~10 min.**

**Prerequisites:** OP-1 executed (`verifierCount() == 2`); S6 done.

**Steps.** From the creator Safe, `createQuest` with the same
parameters as S5 except `title` = `Smoke T2` and
`attestationThreshold` = `2`.

**Verify:**

```bash
cast call $QM "questCount()(uint256)" --rpc-url $RPC  # 2
cast call $QM "getQuest(uint256)((uint256,address,string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint8))" 2 --rpc-url $RPC
# expect threshold 2, reward 100, active true
cast call $QM "highestLiveThreshold()(uint8)" --rpc-url $RPC  # 2
cast call $QM "liveAttestedQuestCount(uint8)(uint256)" 2 --rpc-url $RPC  # 1
cast call $QM "liveAttestedQuestCount(uint8)(uint256)" 1 --rpc-url $RPC  # 1 (Q1)
```

| Check                                     | Expected             | HASIL AKTUAL |
| ----------------------------------------- | -------------------- | ------------ |
| Q2 create tx hash                         | —                    |              |
| `questCount()`                            | `2`                  |              |
| `getQuest(2)` threshold / reward / active | `2` / `100` / `true` |              |
| `highestLiveThreshold()`                  | `2`                  |              |
| `liveAttestedQuestCount(2)` / `(1)`       | `1` / `1`            |              |

---

## S8 — Complete the threshold-2 quest (two verifiers)

**Goal:** `$ALICE` completes Q2 with attestations from **both**
verifiers over the **same** digest (same account, questId, nonce,
deadline). Proves M-of-N threshold completion on-chain.
**Active time: ~10 min.**

**Prerequisites:** S7 complete.

**Steps.**

1. Read Alice's nonce (expect `1` after S6) and pick a deadline:
   ```bash
   cast call $QM "nonces(address)(uint256)" $ALICE --rpc-url $RPC   # expect 1
   DL=$(( $(date +%s) + 86400 ))
   ```
2. **Both** verifiers sign the SAME typed data (questId `2`,
   nonce `1`, the same deadline). Two signatures, one digest.
   Verify each recovers to its verifier (`cast wallet verify …`).
3. Alice submits both signatures in one call:
   ```bash
   cast send $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 $DL "[<sig-V1>,<sig-V2>]" \
     --private-key $ALICE_KEY --rpc-url $RPC
   ```
4. Verify:
   ```bash
   cast call $REP "points(address)(uint256)" $ALICE --rpc-url $RPC       # 200
   cast call $QM "hasCompleted(address,uint256)(bool)" $ALICE 2 --rpc-url $RPC  # true
   cast call $QM "nonces(address)(uint256)" $ALICE --rpc-url $RPC        # 2
   ```

| Check                                                 | Expected                                                                                                                              | HASIL AKTUAL |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| Alice nonce before                                    | `1`                                                                                                                                   |              |
| Deadline used                                         | now + 1 day                                                                                                                           |              |
| S8 completion tx hash                                 | —                                                                                                                                     |              |
| Gas used (reference: 255,766 fresh-account benchmark) |                                                                                                                                       |              |
| `points($ALICE)`                                      | `200`                                                                                                                                 |              |
| `hasCompleted($ALICE, 2)`                             | `true`                                                                                                                                |              |
| Alice nonce after                                     | `2` (consumed exactly once, not per signature)                                                                                        |              |
| Events (S14)                                          | `QuestCompleted(2, $ALICE, 100, 0)` + `PointsAdded($ALICE, 2, 100, 200)` + **two** `AttestationUsed` (one per signer, same nonce `1`) |              |

---

## S9 — Prove duplicate signatures are rejected

**Goal:** the same verifier signing twice in one attestation array
never counts as two verifiers — the call reverts with
`DuplicateAttestationSigner`. **Active time: ~10 min.**

**Prerequisites:** S8 complete. `$BOB` has a fresh nonce (`0`) and
has not completed Q2 — the revert must be attributable to the
duplicate, not to any other state.

**Steps.**

1. Read Bob's nonce (expect `0`) and pick a deadline:
   ```bash
   cast call $QM "nonces(address)(uint256)" $BOB --rpc-url $RPC   # expect 0
   DL=$(( $(date +%s) + 86400 ))
   ```
2. Verifier 1 signs ONE attestation for Bob / Q2 / nonce `0` /
   deadline. Submit it **twice** in the array.
3. **Pre-check with `cast call` first** (free, shows the exact
   revert data — record it):
   ```bash
   cast call $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 $DL "[<sig-V1>,<sig-V1>]" \
     --from $BOB --rpc-url $RPC
   ```
   Expected output:
   `Error: execution reverted: DuplicateAttestationSigner(<V1>)`
   with revert data starting `0x168e588e` (selector, Appendix B).
4. Submit the same call on-chain from Bob's wallet (it will fail;
   the failed tx is the evidence):
   ```bash
   cast send $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 $DL "[<sig-V1>,<sig-V1>]" \
     --private-key $BOB_KEY --rpc-url $RPC
   ```
   `cast send` exits non-zero and reports the revert. Record the
   tx hash from its output.
5. Verify the failure changed nothing:
   ```bash
   cast call $REP "points(address)(uint256)" $BOB --rpc-url $RPC   # 0
   cast call $QM "nonces(address)(uint256)" $BOB --rpc-url $RPC    # 0 (not burned)
   cast call $QM "hasCompleted(address,uint256)(bool)" $BOB 2 --rpc-url $RPC  # false
   cast receipt <tx-hash> --json --rpc-url $RPC | jq -r .status    # 0x0
   ```

**How to verify the revert on BscScan:** open
`https://testnet.bscscan.com/tx/<tx-hash>`. The tx shows
**Status: Fail**. Because QuestManager is verified (S1), BscScan
decodes the revert reason in the transaction overview as
`Fail with error 'DuplicateAttestationSigner(0x…<V1>…)'`.
Cross-check the error name + the signer argument against the
`cast call` output from step 3 — they must match exactly.

| Check                   | Expected                                              | HASIL AKTUAL |
| ----------------------- | ----------------------------------------------------- | ------------ |
| Bob nonce before        | `0`                                                   |              |
| `cast call` revert      | `DuplicateAttestationSigner($V1)`, data `0x168e588e…` |              |
| S9 failed tx hash       | —                                                     |              |
| Receipt `status`        | `0x0`                                                 |              |
| BscScan decoded error   | `DuplicateAttestationSigner($V1)`                     |              |
| `points($BOB)` after    | `0`                                                   |              |
| Bob nonce after         | `0`                                                   |              |
| `hasCompleted($BOB, 2)` | `false`                                               |              |

---

## S10 — Prove insufficient signatures are rejected

**Goal:** one valid signature on a threshold-2 quest reverts with
`InsufficientAttestations(1, 2)`. **Active time: ~5 min.**

**Prerequisites:** S9 complete (Bob's nonce is still `0` — the
failed S9 attempt burned nothing).

**Steps.** Same flow as S9, but submit the single V1 signature
alone for Bob / Q2 / nonce `0` / a fresh deadline:

```bash
cast call $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 $DL "[<sig-V1>]" \
  --from $BOB --rpc-url $RPC
# expect: Error: execution reverted: InsufficientAttestations(1, 2), data 0x78da11c2…
cast send $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 $DL "[<sig-V1>]" \
  --private-key $BOB_KEY --rpc-url $RPC
```

Then verify on BscScan (Status: Fail, decoded error
`InsufficientAttestations(1, 2)`) and that Bob's points (`0`),
nonce (`0`), and completion (`false`) are unchanged.

| Check                                   | Expected                                             | HASIL AKTUAL |
| --------------------------------------- | ---------------------------------------------------- | ------------ |
| Bob nonce before                        | `0`                                                  |              |
| `cast call` revert                      | `InsufficientAttestations(1, 2)`, data `0x78da11c2…` |              |
| S10 failed tx hash                      | —                                                    |              |
| Receipt `status`                        | `0x0`                                                |              |
| BscScan decoded error                   | `InsufficientAttestations(1, 2)`                     |              |
| `points($BOB)` / nonce / `hasCompleted` | `0` / `0` / `false`                                  |              |

---

## S11 — Prove a 1,001-point threshold-1 quest is rejected (PH7-H01)

**Goal:** the on-chain threshold policy (Phase 8, H01) — an Attested
quest with `rewardPoints > 1,000` **requires** threshold ≥ 2.
Creation at threshold 1 reverts with
`InsufficientAttestations(1, 2)`. Two positive controls prove the
boundary is exactly 1,000. **Active time: ~15 min.**

**Prerequisites:** S8 complete (`verifierCount() == 2` — the
controls need 2 verifiers for the threshold-2 case).

**Steps.**

1. **Pre-check with `cast call`** (sender = creator Safe; static,
   free):
   ```bash
   START=$(date +%s); END=$((START + 2592000))
   cast call $QM "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
     "High T1" "H01 negative test" 1 2 0x0000000000000000000000000000000000000000 \
     1001 0 $START $END 0 1 --from $CREATOR_SAFE --rpc-url $RPC
   # expect: Error: execution reverted: InsufficientAttestations(1, 2), data 0x78da11c2…
   ```
2. **On-chain evidence (optional but recommended):** submit the
   same creation through the creator Safe. The Safe UI simulation
   will show the revert before signing — that simulation output is
   itself valid evidence. If the owners agree, submit anyway to
   produce a failed tx on BscScan (Status: Fail, decoded error
   `InsufficientAttestations(1, 2)`). Either way, record which
   evidence was captured.
3. Verify no quest was created:
   ```bash
   cast call $QM "questCount()(uint256)" --rpc-url $RPC  # still 2
   ```
4. **Positive control 1 — 1,001 points at threshold 2 SUCCEEDS**
   (creates Q3). From the creator Safe, `createQuest` with
   `title` = `High T2 control`, `rewardPoints` = `1001`,
   `attestationThreshold` = `2`, otherwise as step 1.
5. **Positive control 2 — exactly 1,000 points at threshold 1
   SUCCEEDS** (creates Q4; the policy is `> 1,000`, so 1,000 is not
   high-value). From the creator Safe, `createQuest` with
   `title` = `Boundary T1 control`, `rewardPoints` = `1000`,
   `attestationThreshold` = `1`.
6. Verify:
   ```bash
   cast call $QM "questCount()(uint256)" --rpc-url $RPC  # 4
   cast call $QM "getQuest(uint256)((uint256,address,string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint8))" 3 --rpc-url $RPC  # 1001 pts, T2
   cast call $QM "getQuest(uint256)((uint256,address,string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint8))" 4 --rpc-url $RPC  # 1000 pts, T1
   cast call $QM "highestLiveThreshold()(uint8)" --rpc-url $RPC  # 2
   cast call $QM "liveAttestedQuestCount(uint8)(uint256)" 2 --rpc-url $RPC  # 2 (Q2 + Q3)
   ```

| Check                                | Expected                                             | HASIL AKTUAL |
| ------------------------------------ | ---------------------------------------------------- | ------------ |
| `cast call` revert (1,001/T1)        | `InsufficientAttestations(1, 2)`, data `0x78da11c2…` |              |
| S11 evidence route                   | Safe simulation output and/or failed tx              |              |
| S11 failed tx hash (if submitted)    | —                                                    |              |
| Receipt `status` (if submitted)      | `0x0`                                                |              |
| BscScan decoded error (if submitted) | `InsufficientAttestations(1, 2)`                     |              |
| `questCount()` after the revert      | `2`                                                  |              |
| Q3 create tx hash (1,001/T2)         | —                                                    |              |
| Q4 create tx hash (1,000/T1)         | —                                                    |              |
| `questCount()` after controls        | `4`                                                  |              |
| `highestLiveThreshold()`             | `2`                                                  |              |
| `liveAttestedQuestCount(2)`          | `2`                                                  |              |

## Setup C — Schedule OP-2: revoke verifier 2 (Day 2, after S11)

**Goal:** start the 2-day clock for the S12 guardrail proof. The
revoke is scheduled while threshold-2 quests are live, so its
execution on Day 4 must be **blocked** by the guardrail.

**Steps.**

1. Compute the calldata:
   ```bash
   cast calldata "revokeRole(bytes32,address)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $V2
   ```
2. From the admin Safe, `schedule` on `$TIMELOCK`:
   `target` = `$QM`, `value` = `0`, `data` = step-1 calldata,
   `predecessor` = zero bytes32,
   `salt` = `cast keccak "agenthub-smoke-revoke-v2"`,
   `delay` = `172800`.
3. Verify: `getOperationState` = `1` (Waiting); record the op id.

| Item                                            | HASIL AKTUAL |
| ----------------------------------------------- | ------------ |
| OP-2 salt                                       |              |
| OP-2 id (`hashOperation`)                       |              |
| OP-2 schedule tx hash                           |              |
| `getOperationState` after schedule (expect `1`) |              |

---

## S12 — Prove revoking a verifier is blocked while it would brick a live quest (PH7-M01)

**Goal:** the verifier-revoke guardrail — revoking verifier 2 while
a threshold-2 quest is live would leave 1 verifier < threshold 2,
so the timelock execution reverts with
`RevocationWouldBrickQuest(1, 2)`; the operation stays Ready and
the role stays held; deactivating the affected quests first unblocks
the revoke. **Active time: ~20 min across Day 4** (plus the OP-3
re-grant scheduled the same day).

**Prerequisites:** OP-2 scheduled (Day 2) and now Ready (Day 4);
Q2 and Q3 live (threshold 2); `verifierCount() == 2`.

**Steps — part 1: the blocked execution (Day 4).**

1. Confirm readiness:
   ```bash
   cast call $TIMELOCK "getOperationState(bytes32)(uint8)" <OP-2 id> --rpc-url $RPC  # 2 = Ready
   cast call $QM "highestLiveThreshold()(uint8)" --rpc-url $RPC  # 2
   cast call $QM "verifierCount()(uint256)" --rpc-url $RPC  # 2
   ```
2. **Pre-check with `cast call`** (sender = admin Safe):
   ```bash
   cast call $TIMELOCK "execute(address,uint256,bytes,bytes32,bytes32)" $QM 0 <revoke calldata> 0x0000…0000 <OP-2 salt> \
     --from $ADMIN_SAFE --rpc-url $RPC
   # expect: Error: execution reverted: RevocationWouldBrickQuest(1, 2), data 0x8df6077d…
   ```
3. **Submit the execution on-chain** from the admin Safe (Safe UI,
   contract interaction to `$TIMELOCK`, `execute` with the same
   parameters). The Safe simulation will show the revert — submit
   anyway: the failed execution is the proof, and the operation
   must remain Ready afterwards. Record the failed tx hash.
4. Verify the guardrail held:
   ```bash
   cast call $TIMELOCK "getOperationState(bytes32)(uint8)" <OP-2 id> --rpc-url $RPC  # still 2 = Ready
   cast call $QM "hasRole(bytes32,address)(bool)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $V2 --rpc-url $RPC  # true
   cast call $QM "verifierCount()(uint256)" --rpc-url $RPC  # 2
   cast receipt <tx-hash> --json --rpc-url $RPC | jq -r .status  # 0x0
   ```
   On BscScan the tx shows Status: Fail with decoded error
   `RevocationWouldBrickQuest(1, 2)`.

**Steps — part 2: the recovery path (Day 4, immediately after).**

5. Deactivate **both** live threshold-2 quests from the creator
   Safe (no timelock — the creator deactivates directly):
   `deactivateQuest(2)` and `deactivateQuest(3)`.
   Verify: `highestLiveThreshold()` drops to `1`
   (Q1 and Q4, both threshold 1, remain live).
6. Re-execute the **same** OP-2 operation from the admin Safe
   (it is still Ready — no re-scheduling needed). This time it
   succeeds.
7. Verify:
   ```bash
   cast call $TIMELOCK "getOperationState(bytes32)(uint8)" <OP-2 id> --rpc-url $RPC  # 3 = Done
   cast call $QM "hasRole(bytes32,address)(bool)" 0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09 $V2 --rpc-url $RPC  # false
   cast call $QM "verifierCount()(uint256)" --rpc-url $RPC  # 1
   ```

| Check                                      | Expected                                                                                   | HASIL AKTUAL |
| ------------------------------------------ | ------------------------------------------------------------------------------------------ | ------------ |
| OP-2 state before execute                  | `2` (Ready)                                                                                |              |
| `cast call` revert                         | `RevocationWouldBrickQuest(1, 2)`, data `0x8df6077d…`                                      |              |
| S12 blocked-execute tx hash                | —                                                                                          |              |
| Receipt `status`                           | `0x0`                                                                                      |              |
| BscScan decoded error                      | `RevocationWouldBrickQuest(1, 2)`                                                          |              |
| OP-2 state after failed execute            | `2` (Ready — not Done, not cancelled)                                                      |              |
| `$V2` still holds VERIFIER_ROLE            | `true`                                                                                     |              |
| `verifierCount()` after failed execute     | `2`                                                                                        |              |
| `deactivateQuest(2)` tx hash               | —                                                                                          |              |
| `deactivateQuest(3)` tx hash               | —                                                                                          |              |
| `highestLiveThreshold()` after deactivate  | `1`                                                                                        |              |
| OP-2 re-execute tx hash                    | —                                                                                          |              |
| OP-2 state after re-execute                | `3` (Done)                                                                                 |              |
| `$V2` holds VERIFIER_ROLE after re-execute | `false`                                                                                    |              |
| `verifierCount()` after re-execute         | `1`                                                                                        |              |
| Events (S14)                               | `QuestDeactivated(2)`, `QuestDeactivated(3)`, `RoleRevoked(VERIFIER_ROLE, $V2, $TIMELOCK)` |              |

## Setup D — Schedule OP-3 (re-grant verifier 2) + create Q5 + schedule OP-4 (Day 4, after S12)

**OP-3 — re-grant verifier 2** (restores the 2-verifier end state;
same calldata as OP-1, new salt
`cast keccak "agenthub-smoke-regrant-v2"`). From the admin Safe,
`schedule` on `$TIMELOCK`; verify state `1` (Waiting). Executes on
Day 6.

**Q5 — create the recreate quest.** From the creator Safe,
`createQuest` with `title` = `Smoke T1 recreate`,
`rewardPoints` = `100`, `attestationThreshold` = `1`, otherwise as
S5. Verify `questCount()` = `5`.

**OP-4 — link Q5 to Q2.** `setSupersedes` is admin-only, so it goes
through the timelock. Compute the calldata:

```bash
cast calldata "setSupersedes(uint256,uint256)" 5 2
```

From the admin Safe, `schedule` on `$TIMELOCK` with that calldata,
`target` = `$QM`, `salt` = `cast keccak "agenthub-smoke-supersedes-5-2"`,
`delay` = `172800`. Verify state `1` (Waiting). Executes on Day 6.

| Item                                           | HASIL AKTUAL |
| ---------------------------------------------- | ------------ |
| OP-3 salt / id / schedule tx hash / state      |              |
| Q5 create tx hash; `questCount()` (expect `5`) |              |
| OP-4 salt / id / schedule tx hash / state      |              |

---

## S13 — Prove the supersedes mechanism (PH7-L07)

**Goal:** deactivate + recreate cannot pay the same account twice.
Q2 was completed by Alice and deactivated (S12); Q5 recreates it
and is linked with `setSupersedes(5, 2)`. Alice's completion of Q5
reverts with `AlreadyCompletedSupersededQuest`; Bob — who never
completed Q2 — completes Q5 normally. **Active time: ~20 min on
Day 6** (plus OP-3/OP-4 execution).

**Prerequisites:** OP-3 + OP-4 Ready (Day 6); Q2 deactivated;
Alice completed Q2 (S8); Bob never completed Q2.

**Steps.**

1. Execute OP-3 and OP-4 from the admin Safe (two `execute` calls
   with the same parameters as their schedules). Verify:
   ```bash
   cast call $TIMELOCK "getOperationState(bytes32)(uint8)" <OP-3 id> --rpc-url $RPC  # 3
   cast call $TIMELOCK "getOperationState(bytes32)(uint8)" <OP-4 id> --rpc-url $RPC  # 3
   cast call $QM "verifierCount()(uint256)" --rpc-url $RPC  # 2
   cast call $QM "supersedes(uint256)(uint256)" 5 --rpc-url $RPC  # 2
   ```
2. **Alice is blocked.** Read her nonce (expect `2`), pick a
   deadline, have verifier 1 sign for Alice / Q5 / nonce `2`.
   Pre-check, then submit on-chain (it will fail):
   ```bash
   cast call $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 5 $DL "[<sig-V1>]" \
     --from $ALICE --rpc-url $RPC
   # expect: Error: execution reverted: AlreadyCompletedSupersededQuest($ALICE, 5, 2), data 0x89c03273…
   cast send $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 5 $DL "[<sig-V1>]" \
     --private-key $ALICE_KEY --rpc-url $RPC
   ```
   Verify on BscScan (Status: Fail, decoded error
   `AlreadyCompletedSupersededQuest(<alice>, 5, 2)`) and that
   Alice's points (`200`) and nonce (`2`) are unchanged.
3. **Bob completes.** Read his nonce (expect `0` — S9/S10 burned
   nothing), pick a deadline, have verifier 1 sign for Bob / Q5 /
   nonce `0`, submit:
   ```bash
   cast send $QM "completeQuestWithAttestation(uint256,uint256,bytes[])" 5 $DL "[<sig-V1>]" \
     --private-key $BOB_KEY --rpc-url $RPC
   ```
   Verify: `points($BOB)` = `100`, `hasCompleted($BOB, 5)` = `true`,
   Bob's nonce = `1`.

| Check                                            | Expected                                                                                                                         | HASIL AKTUAL |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| OP-3 execute tx hash; state after                | `3` (Done)                                                                                                                       |              |
| OP-4 execute tx hash; state after                | `3` (Done)                                                                                                                       |              |
| `verifierCount()` after OP-3                     | `2`                                                                                                                              |              |
| `supersedes(5)`                                  | `2`                                                                                                                              |              |
| Alice nonce before                               | `2`                                                                                                                              |              |
| `cast call` revert (Alice/Q5)                    | `AlreadyCompletedSupersededQuest($ALICE, 5, 2)`, data `0x89c03273…`                                                              |              |
| S13 Alice failed tx hash                         | —                                                                                                                                |              |
| Receipt `status`                                 | `0x0`                                                                                                                            |              |
| BscScan decoded error                            | `AlreadyCompletedSupersededQuest($ALICE, 5, 2)`                                                                                  |              |
| Alice points / nonce after                       | `200` / `2`                                                                                                                      |              |
| Bob nonce before                                 | `0`                                                                                                                              |              |
| S13 Bob completion tx hash                       | —                                                                                                                                |              |
| `points($BOB)` / nonce / `hasCompleted($BOB, 5)` | `100` / `1` / `true`                                                                                                             |              |
| Events (S14)                                     | `QuestSuperseded(5, 2)`, `QuestCompleted(5, $BOB, 100, 0)`, `PointsAdded($BOB, 5, 100, 100)`, `AttestationUsed($BOB, 5, 0, $V1)` |              |

---

## S14 — Verify all events + transactions on BscScan

**Goal:** every transaction in S1–S13 is accounted for on BscScan
testnet, and every expected event is present with the right
arguments. This is the audit pass over the whole run; run it
progressively (check each scenario's events as it completes) and
do the final sweep on Day 6. **Active time: ~30 min.**

**Prerequisites:** S1–S13 complete (or in progress, for the
progressive checks).

**Method.** For each contract, open its BscScan testnet page
(`https://testnet.bscscan.com/address/<address>#events`) and filter
by event, or query logs directly:

```bash
# Example: all QuestCompleted events from the deploy block
cast logs --from-block $DEPLOY_BLOCK --to-block latest --address $QM \
  --rpc-url $RPC "QuestCompleted(uint256,address,uint256,uint256)"
```

For each transaction, open `https://testnet.bscscan.com/tx/<hash>`
and confirm: Status (Success / Fail as expected), From/To, the
emitted events in the Logs tab, and — for failed txs — the decoded
custom error in the overview.

**Expected event counts (full run, from `$DEPLOY_BLOCK`):**

| Event                                                                  | Contract    | Expected count                                                                               | HASIL AKTUAL |
| ---------------------------------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------- | ------------ |
| `QuestCreated(uint256,address,uint8,uint8,uint256)`                    | QM          | 5 (Q1–Q5)                                                                                    |              |
| `QuestCompleted(uint256,address,uint256,uint256)`                      | QM          | 3 (Alice Q1, Alice Q2, Bob Q5)                                                               |              |
| `PointsAdded(address,uint256,uint256,uint256)`                         | Reputation  | 3 (100 + 100 + 100)                                                                          |              |
| `AttestationUsed(address,uint256,uint256,address)`                     | QM          | 4 (1 + 2 + 1 signers)                                                                        |              |
| `QuestDeactivated(uint256)`                                            | QM          | 2 (Q2, Q3)                                                                                   |              |
| `QuestSuperseded(uint256,uint256)`                                     | QM          | 1 (5, 2)                                                                                     |              |
| `RoleGranted(bytes32,address,address)`                                 | QM          | 7 (deploy 5: admin→deployer, creator, pauser, V1, admin→timelock; + grant V2; + re-grant V2) |              |
| `RoleRevoked(bytes32,address,address)`                                 | QM          | 2 (deployer renounces admin; revoke V2)                                                      |              |
| `CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)` | Timelock    | 4 (OP-1–OP-4)                                                                                |              |
| `CallExecuted(bytes32,uint256,address,uint256,bytes)`                  | Timelock    | 4 (OP-1, OP-2 re-execute, OP-3, OP-4; the blocked OP-2 execute emits none)                   |              |
| `OwnershipTransferred(address,address)`                                | MockAgentId | 2 (constructor 0→deployer; deploy deployer→admin Safe)                                       |              |
| `Transfer(address,address,uint256)`                                    | MockAgentId | 2 (mint to Alice, mint to Bob)                                                               |              |

**Per-scenario event checklist** (check each tx's Logs tab):

| Scenario              | Expected events on its tx(s)                                                                                                                                                                                                                 | Checked (HASIL AKTUAL) |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| S1 deploy             | `OwnershipTransferred` (mock), `RoleGranted` ×5 on QM + ×3 on Reputation + ×4 on Achievement + ×4 on Timelock (each count includes the constructor's admin grant to the deployer), `RoleRevoked` ×3 (deployer renounces admin on QM/REP/ACH) | ☐                      |
| Setup A mints         | `Transfer` (0→Alice, tokenId 1), `Transfer` (0→Bob, tokenId 2)                                                                                                                                                                               | ☐                      |
| OP-1 schedule/execute | `CallScheduled`, `CallExecuted`, `RoleGranted(VERIFIER_ROLE, $V2)`                                                                                                                                                                           | ☐                      |
| S5                    | `QuestCreated(1, $CREATOR_SAFE, OneTime, Attested, 100)`                                                                                                                                                                                     | ☐                      |
| S6                    | `QuestCompleted(1, $ALICE, 100, 0)`, `PointsAdded($ALICE, 1, 100, 100)`, `AttestationUsed($ALICE, 1, 0, $V1)`                                                                                                                                | ☐                      |
| S7                    | `QuestCreated(2, $CREATOR_SAFE, OneTime, Attested, 100)`                                                                                                                                                                                     | ☐                      |
| S8                    | `QuestCompleted(2, $ALICE, 100, 0)`, `PointsAdded($ALICE, 2, 100, 200)`, `AttestationUsed` ×2 (signers `$V1`, `$V2`, nonce `1`)                                                                                                              | ☐                      |
| S9                    | No events (tx failed); Status Fail; error `DuplicateAttestationSigner($V1)`                                                                                                                                                                  | ☐                      |
| S10                   | No events (tx failed); Status Fail; error `InsufficientAttestations(1, 2)`                                                                                                                                                                   | ☐                      |
| S11                   | Revert: no events; Status Fail (if submitted); error `InsufficientAttestations(1, 2)`. Controls: `QuestCreated(3, …, 1001)`, `QuestCreated(4, …, 1000)`                                                                                      | ☐                      |
| OP-2 schedule         | `CallScheduled`                                                                                                                                                                                                                              | ☐                      |
| S12 blocked execute   | No events (tx failed); Status Fail; error `RevocationWouldBrickQuest(1, 2)`                                                                                                                                                                  | ☐                      |
| S12 deactivate        | `QuestDeactivated(2)`, `QuestDeactivated(3)`                                                                                                                                                                                                 | ☐                      |
| S12 re-execute        | `CallExecuted`, `RoleRevoked(VERIFIER_ROLE, $V2, $TIMELOCK)`                                                                                                                                                                                 | ☐                      |
| OP-3 schedule/execute | `CallScheduled`, `CallExecuted`, `RoleGranted(VERIFIER_ROLE, $V2)`                                                                                                                                                                           | ☐                      |
| S13 create Q5         | `QuestCreated(5, $CREATOR_SAFE, OneTime, Attested, 100)`                                                                                                                                                                                     | ☐                      |
| OP-4 schedule/execute | `CallScheduled`, `CallExecuted`, `QuestSuperseded(5, 2)`                                                                                                                                                                                     | ☐                      |
| S13 Alice attempt     | No events (tx failed); Status Fail; error `AlreadyCompletedSupersededQuest($ALICE, 5, 2)`                                                                                                                                                    | ☐                      |
| S13 Bob completion    | `QuestCompleted(5, $BOB, 100, 0)`, `PointsAdded($BOB, 5, 100, 100)`, `AttestationUsed($BOB, 5, 0, $V1)`                                                                                                                                      | ☐                      |

**Transaction ledger** (fill every row during the run; a blank hash
means the step is not done):

| #   | Step                                                                                                                              | Tx hash (HASIL AKTUAL) | Status (HASIL AKTUAL) |
| --- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | --------------------- |
| 1   | S1 deploy (6 CREATEs + 13 wiring CALLs — record the broadcast tx hashes from `broadcast/DeployAgentHub.s.sol/97/run-latest.json`) |                        |                       |
| 2   | Setup A: `mint($ALICE)`                                                                                                           |                        |                       |
| 3   | Setup A: `mint($BOB)`                                                                                                             |                        |                       |
| 4   | Setup B: OP-1 schedule                                                                                                            |                        |                       |
| 5   | S5: OP-1 execute                                                                                                                  |                        |                       |
| 6   | S5: create Q1                                                                                                                     |                        |                       |
| 7   | S6: complete Q1 (Alice)                                                                                                           |                        |                       |
| 8   | S7: create Q2                                                                                                                     |                        |                       |
| 9   | S8: complete Q2 (Alice)                                                                                                           |                        |                       |
| 10  | S9: duplicate attempt (Bob) — FAIL expected                                                                                       |                        |                       |
| 11  | S10: insufficient attempt (Bob) — FAIL expected                                                                                   |                        |                       |
| 12  | S11: 1,001/T1 create attempt — FAIL expected (if submitted)                                                                       |                        |                       |
| 13  | S11: create Q3 (control)                                                                                                          |                        |                       |
| 14  | S11: create Q4 (control)                                                                                                          |                        |                       |
| 15  | Setup C: OP-2 schedule                                                                                                            |                        |                       |
| 16  | S12: OP-2 execute (blocked) — FAIL expected                                                                                       |                        |                       |
| 17  | S12: `deactivateQuest(2)`                                                                                                         |                        |                       |
| 18  | S12: `deactivateQuest(3)`                                                                                                         |                        |                       |
| 19  | S12: OP-2 re-execute                                                                                                              |                        |                       |
| 20  | Setup D: OP-3 schedule                                                                                                            |                        |                       |
| 21  | Setup D: create Q5                                                                                                                |                        |                       |
| 22  | Setup D: OP-4 schedule                                                                                                            |                        |                       |
| 23  | S13: OP-3 execute                                                                                                                 |                        |                       |
| 24  | S13: OP-4 execute                                                                                                                 |                        |                       |
| 25  | S13: Alice attempt (Bob Q5) — FAIL expected                                                                                       |                        |                       |
| 26  | S13: Bob completes Q5                                                                                                             |                        |                       |

---

## 5. Sign-off — R-010 closure criteria

The live smoke test closes R-010 (threshold attestation) when ALL
of the following hold:

- [ ] S1–S4 green: deployment + wiring + roles + timelock verified.
- [ ] S5–S8 green: threshold-1 and threshold-2 quests created and
      completed on-chain with real EIP-712 attestations.
- [ ] S9–S10 green: duplicate and insufficient signatures revert
      on-chain with the expected custom errors.
- [ ] S11 green: the H01 policy is enforced on-chain (1,001/T1
      reverts; 1,001/T2 and 1,000/T1 succeed).
- [ ] S12 green: the M01 guardrail blocks the revoke at execution
      time, and the deactivate-first recovery path works.
- [ ] S13 green: the L07 supersedes link blocks the double claim
      and leaves the recreate open to new completers.
- [ ] S14 green: every event and transaction is accounted for on
      BscScan; the ledger above is complete.
- [ ] This document's HASIL AKTUAL columns are filled, and the
      filled copy is stored with the deployment record
      (`docs/DEPLOYMENT_RECORD.md`).

**What this smoke test does NOT close:** the mainnet gate
(checklist §7) — external review (R-012), dependency upgrades,
mainnet multisig verification, and monitoring are still open.
Testnet success authorizes nothing on mainnet.

---

## Appendix A — Role hashes

`DEFAULT_ADMIN_ROLE` is `0x00…00`. All others are
`keccak256("<ROLE_NAME>")` (verified with `cast keccak`):

| Role                 | Hash                                                                 |
| -------------------- | -------------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | `0x0000000000000000000000000000000000000000000000000000000000000000` |
| `VERIFIER_ROLE`      | `0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09` |
| `QUEST_CREATOR_ROLE` | `0x4112259a34054d6040a76e8d985093c9e8b0a52d820e856d7f4230fcaef428de` |
| `PAUSER_ROLE`        | `0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a` |
| `SCORE_SOURCE_ROLE`  | `0x08dd1ffd17984138218681c16863231d15b3a8b44885cf4e34e2804b0b15faa9` |
| `ISSUER_ROLE`        | `0x114e74f6ea3bd819998f78687bfcb11b140da08e9b7d222fa9c1f1ba1f2aa122` |
| `BADGE_MANAGER_ROLE` | `0xa00144c395da084768e13ed238fd3b1cd040ce840901c1170be1eceffc7a7ded` |
| `PROPOSER_ROLE`      | `0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1` |
| `EXECUTOR_ROLE`      | `0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63` |
| `CANCELLER_ROLE`     | `0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783` |

## Appendix B — Custom-error selectors

First 4 bytes of `keccak256("<signature>")` (verified with
`cast sig`). A revert's raw data starts with the selector:

| Error                                                      | Selector     | Where it appears                                                                            |
| ---------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------- |
| `DuplicateAttestationSigner(address)`                      | `0x168e588e` | S9                                                                                          |
| `InsufficientAttestations(uint256,uint256)`                | `0x78da11c2` | S10 (completion), S11 (creation)                                                            |
| `RevocationWouldBrickQuest(uint256,uint256)`               | `0x8df6077d` | S12                                                                                         |
| `AlreadyCompletedSupersededQuest(address,uint256,uint256)` | `0x89c03273` | S13                                                                                         |
| `InsufficientVerifiers(uint256,uint256)`                   | `0x035cfd8c` | Guard: creating a T2 quest with 1 verifier (would fire if S7 ran before OP-1)               |
| `UnauthorizedVerifier(address)`                            | `0x1eb1c0a5` | Guard: a non-verifier's signature (unit-tested; not a live scenario)                        |
| `QuestNotFound(uint256)`                                   | `0xce02f597` | Guard: wrong questId (a sign the fixture numbering drifted — stop and check `questCount()`) |

## Appendix C — EIP-712 attestation template

Verifiers sign this typed data (one digest, all signers sign the
same digest for threshold quests). Fill in the four message fields
per completion; `chainId` is `97` and `verifyingContract` is `$QM`.

```json
{
  "types": {
    "EIP712Domain": [
      { "name": "name", "type": "string" },
      { "name": "version", "type": "string" },
      { "name": "chainId", "type": "uint256" },
      { "name": "verifyingContract", "type": "address" }
    ],
    "Attestation": [
      { "name": "account", "type": "address" },
      { "name": "questId", "type": "uint256" },
      { "name": "nonce", "type": "uint256" },
      { "name": "deadline", "type": "uint256" }
    ]
  },
  "primaryType": "Attestation",
  "domain": {
    "name": "AGENTHUB QuestManager",
    "version": "1",
    "chainId": 97,
    "verifyingContract": "<QM>"
  },
  "message": {
    "account": "<holder>",
    "questId": "<id>",
    "nonce": "<nonce>",
    "deadline": "<unix-seconds>"
  }
}
```

```bash
# Sign (verifier's machine, verifier's key only):
cast wallet sign --data --from-file attestation.json --private-key $VERIFIER_KEY
# Verify before submitting:
cast wallet verify --data --from-file attestation.json --address $VERIFIER <signature>
```

Rules: read the nonce fresh (`cast call $QM "nonces(address)"`);
deadline ≤ now + 7 days; for a threshold-2 quest both verifiers
sign the identical message (same nonce, same deadline). A signature
is bound to one account + one quest + one nonce — it cannot be
replayed anywhere else.

## Appendix D — Timelock operations reference

```solidity
schedule(address target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt, uint256 delay)
execute(address target, uint256 value, bytes payload, bytes32 predecessor, bytes32 salt)
hashOperation(address target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt) returns (bytes32)
getOperationState(bytes32 id) returns (uint8)  // 0 Unset, 1 Waiting, 2 Ready, 3 Done
getTimestamp(bytes32 id) returns (uint256)     // earliest execution time
cancel(bytes32 id)                             // CANCELLER_ROLE (admin Safe)
```

Conventions in this plan: `predecessor` is always the zero bytes32
(no operation depends on another); `delay` is always `172800`
(the minimum); each operation has a distinct salt (derived from a
label with `cast keccak "<label>"` — a reused salt + identical
parameters would collide with an earlier operation id). The caller
of `schedule` and `execute` is always the admin Safe
(PROposer + EXECUTOR). A failed `execute` leaves the operation
Ready — it can be re-executed or cancelled; it never needs
re-scheduling.

## Appendix E — Gas reference

| Operation                                 | Reference      | Source                                                                                                        |
| ----------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------- |
| Full deploy (6 CREATEs + 13 wiring CALLs) | 8,307,890 gas  | Fork dry-run (this workstream), current code                                                                  |
| Full deploy (older figure)                | 10,294,857 gas | Checklist §2 row 7 (older code/compiler) — superseded by the fork measurement above                           |
| Threshold-1 completion                    | 244,840 gas    | Unit-test benchmark, fresh account (Phase 8 §6)                                                               |
| Threshold-2 completion                    | 255,766 gas    | Unit-test benchmark, fresh account (Phase 8 §6)                                                               |
| Threshold-3 completion                    | 266,911 gas    | Unit-test benchmark, fresh account (Phase 8 §6)                                                               |
| Threshold-1 completion (fork)             | 235,990 gas    | Fork dry-run (first completion by that account — cold storage)                                                |
| Threshold-2 completion (fork)             | 195,351 gas    | Fork dry-run (second completion by the same account — warm storage; cheaper than the fresh-account benchmark) |

Live gas varies with warm/cold storage and the testnet gas price;
treat the numbers as budgeting guides, not assertions. At 0.1 gwei
the deploy costs ~0.00083 tBNB and a completion ~0.00002–0.00003
tBNB — the §1 funding (≥ 0.05 tBNB deployer, ~0.02 tBNB per test
wallet) has ample margin.

## Appendix F — Safe UI guide (admin + creator Safes)

Every Safe-originated call in this plan (mints, `createQuest`,
`deactivateQuest`, timelock `schedule`/`execute`) goes through the
Safe web app:

1. Open https://app.safe.global, connect a Safe owner's wallet,
   switch to **BNB Smart Chain Testnet** (chain 97), open the Safe.
2. **New Transaction → Contract interaction.** Paste the target
   contract address (`$MOCK` / `$QM` / `$TIMELOCK`). The ABI loads
   automatically from BscScan (contracts are verified in S1); if it
   does not, paste the ABI JSON from `apps/web/lib/abis/` (or the
   `out/` build artifacts).
3. Select the function, fill the parameters exactly as the
   scenario specifies. For `bytes` parameters (`data` in
   `schedule`/`execute`), paste the hex from
   `cast calldata "<sig>" <args>` — verify it starts with the right
   function selector before submitting.
4. **Add transaction** → the other owners confirm (threshold 2 of 3) → **Execute**. Record the tx hash from the Safe transaction
   list (it links to BscScan).
5. **Revert scenarios (S11, S12):** the Safe UI simulates the tx
   before execution and will show the revert. That simulation
   output is evidence — screenshot/record it. For S12 the execution
   must still be submitted on-chain (the failed execution is the
   proof and the operation must stay Ready); for S11 submission is
   optional (see the scenario).

## Appendix G — Troubleshooting

| Symptom                                                                        | Likely cause                                                                                                                                  | Action                                                                                                                                         |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Deploy script reverts `TestnetDeployNotConfirmed`                              | `CONFIRM_TESTNET_DEPLOY=true` not set                                                                                                         | Set it (required even for the dry-run) and retry.                                                                                              |
| Deploy script reverts `NotASafe` / `UnknownSingleton` / `UnknownProxyCodehash` | The supplied Safe address is not a genuine canonical Safe on chain 97, or threshold < 2                                                       | Stop. Re-verify the Safe per checklist §3; do not proceed with a different address without re-verification.                                    |
| `createQuest` reverts `InsufficientVerifiers(1, 2)`                            | OP-1 has not executed yet                                                                                                                     | Wait for / execute OP-1 first; threshold-2 creation needs 2 live verifiers.                                                                    |
| Completion reverts `QuestNotFound(n)`                                          | Quest numbering drifted (e.g. after a redeploy or an extra quest)                                                                             | Stop. Read `questCount()` and `getQuest` for the live IDs; do not guess.                                                                       |
| Completion reverts `UnauthorizedVerifier`                                      | The signature recovered to a non-verifier — wrong domain (chainId / QM address), stale nonce, or wrong questId/deadline in the signed message | Re-read the nonce, re-check the typed-data JSON (chainId 97, `$QM`, current nonce), have the verifier re-sign. Never edit a signature by hand. |
| Completion reverts `AttestationExpired` / `AttestationDeadlineTooFar`          | Deadline in the past, or more than 7 days out                                                                                                 | Sign a fresh attestation with deadline = now + 1 day.                                                                                          |
| Timelock `execute` reverts `TimelockUnexpectedOperationState`                  | Wrong parameters (the op id is a hash of ALL parameters — one wrong byte = a different, Unset operation) or too early (still Waiting)         | Recompute the op id with `hashOperation` from the exact schedule parameters; check `getTimestamp` — execute only after it passes.              |
| A `cast call` pre-check passes but the Safe execution fails                    | State changed between the check and the execution (e.g. a nonce was consumed, a quest deactivated)                                            | Re-run the pre-check immediately before submitting; the pre-check is only valid at the moment it runs.                                         |
| BscScan does not decode a revert reason                                        | The contract is not verified, or BscScan has not indexed the tx yet                                                                           | Confirm S1 verification for that contract; wait a minute and refresh. The `cast call` output remains the authoritative revert record.          |

## Appendix H — Fork dry-run (validation of this plan)

This procedure was validated end-to-end on 2026-11-20 against a
local anvil fork of BSC testnet (chain 97) — **90/90 checks PASS,
0 FAIL** — including the full deploy, both Safes via the canonical
factory, all four timelock operations (with time warps), all five
revert proofs with on-chain failed transactions, and the exact
event counts of S14. Full report, reproduction scripts, and the
raw log:
[`04-live-testnet-test-plan-fork-dryrun.md`](./04-live-testnet-test-plan-fork-dryrun.md)
and `fork-dryrun/` in this directory. The dry-run is labelled
**FORK DRY-RUN, BUKAN LIVE** everywhere it appears and must never
be cited as live-testnet evidence.
