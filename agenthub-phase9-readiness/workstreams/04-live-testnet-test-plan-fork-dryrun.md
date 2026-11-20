# AGENTHUB — Phase 9, Workstream 4: Fork Dry-Run Report

> **⚠️ FORK DRY-RUN, BUKAN LIVE.** Everything in this document
> happened on a LOCAL anvil fork of BSC testnet running on this VM.
> Nothing was broadcast to any real chain. The addresses, transaction
> hashes, and block numbers below exist only on that fork (which has
> since been stopped) and MUST NOT be cited as live-testnet evidence.
> The live run is still entirely ahead of us — see
> [`04-live-testnet-test-plan.md`](./04-live-testnet-test-plan.md),
> whose HASIL AKTUAL columns remain empty.

## 1. Summary

| Item              | Value                                                                      |
| ----------------- | -------------------------------------------------------------------------- |
| Date              | 2026-11-20, ~00:51–00:57 WIB (3 runs; the final run below is run 3)        |
| Code under test   | Repo HEAD `e1b316b`, Solidity 0.8.39, `via_ir = true`                      |
| Fork source       | `https://bsc-testnet-rpc.publicnode.com` (chain 97, live head at run time) |
| Fork tool         | `anvil --fork-url <testnet-rpc> --port 8545` (local only)                  |
| **Result**        | **90/90 checks PASS, 0 FAIL** (final run)                                  |
| Scenarios covered | All 14 scenarios of the live test plan, end to end                         |

The dry-run proves: the deploy script runs against real chain-97
state (canonical Safe factory + singleton); every command in the
live plan executes as written; every expected value in the plan
matches on-chain behavior; all five revert proofs produce the
documented custom errors with on-chain failed transactions
(status `0x0`); the timelock flows (schedule → wait → execute,
failed execute leaves the operation Ready) behave as the plan
assumes; and the S14 event counts match exactly.

## 2. How it was run

Driver: `fork-dryrun/run-fork-dryrun.sh` (bash + cast + forge
script, ~410 lines, self-checking with PASS/FAIL per assertion).
Safe deployer: `fork-dryrun/DeployForkSafes.s.sol`.
Raw log of the final run: `fork-dryrun/fork-dryrun.log`
(also `fork-dryrun-driver.out`).

Sequence (mirrors the live plan, with the deviations in §3):

1. Start anvil fork of BSC testnet; verify chain-id 97 and that
   the canonical Safe factory/singleton code is visible through
   the fork.
2. Deploy two genuine Safe v1.4.1 proxies via the canonical
   factory (`0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67`),
   owners = anvil accounts 1/2/3, threshold 2-of-3.
3. Run the real `DeployAgentHub.s.sol` with `--broadcast` against
   the fork (`CONFIRM_TESTNET_DEPLOY=true`, `VERIFIER` = verifier 1).
4. Execute S2–S14 with `cast` (reads, Safe-impersonated sends,
   EIP-712 signing via `cast wallet sign --data`), warping time
   past each 2-day timelock delay.

All keys used are PUBLIC anvil/test keys (the anvil default
mnemonic; verifier keys `0xA11CE5` / `0xBEEF2` as in the unit
tests). No real private key was used, and no real funds exist on
the fork.

## 3. Deviations from the live plan (read before trusting any line)

| #   | Deviation                                                                                                                               | Impact on what the dry-run proves                                                                                                                                                                                        |
| --- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | Safe actions sent via `cast send --from <safe> --unlocked` (anvil impersonation) instead of the Safe web app with owner signatures.     | The dry-run proves the CALLS are correct, not the Safe UI flow. Owner quorum, Safe transaction service, and the Safe simulation UI are untested here.                                                                    |
| D2  | The 2-day timelock delays were skipped with `anvil_increaseTime` + `anvil_mine`.                                                        | The dry-run proves the schedule/execute/state-machine logic, not the wall-clock waiting or the operator discipline across days.                                                                                          |
| D3  | No BscScan exists on a fork. Event/revert verification used `cast logs` / `cast receipt --json` / `cast call` instead of BscScan pages. | The dry-run proves the events and revert data exist on-chain; it does NOT prove BscScan decodes them (that depends on S1 source verification, which itself was not exercised — `--verify` was not run against the fork). |
| D4  | The two Safes were freshly deployed on the fork (anvil owners).                                                                         | The dry-run proves the deploy script's SafeValidation passes for genuine canonical Safes; it says nothing about the team's real Safes (checklist §3 still required).                                                     |
| D5  | Fork state is a snapshot: the dry-run ran against the live testnet head at ~00:51–00:57 WIB on 2026-11-20.                              | Re-running later forks a different head; addresses in §5 are deterministic (same deployer nonce sequence) but the fork block numbers will differ.                                                                        |

## 4. Results per scenario (final run)

| Scenario         | Checks | Result                 | Key evidence (FORK ONLY)                                                                                                                                                                                                           |
| ---------------- | ------ | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S1 Deploy        | 3      | ✅ PASS                | 6 contracts deployed; total gas **8,307,890**; `_verifyWiring` passed (script would have reverted otherwise)                                                                                                                       |
| S2 Addresses     | 5      | ✅ PASS                | `gate.agentIdContract`, `qm.gate/reputation/achievement`, `expectedChainId` all match deploy output                                                                                                                                |
| S3 Roles         | 16     | ✅ PASS                | Admin = timelock ×3; operational roles correct; deployer holds nothing; all unpaused                                                                                                                                               |
| S4 Timelock      | 6      | ✅ PASS                | `getMinDelay` = 172800; proposer/executor/canceller = admin Safe; self-administered                                                                                                                                                |
| Setup A mints    | 3      | ✅ PASS                | `isAgentHolder(alice/bob)` = true; deployer = false                                                                                                                                                                                |
| Setup B OP-1     | 5      | ✅ PASS                | Op states Waiting(1) → Ready(2) → Done(3); `verifierCount` = 2                                                                                                                                                                     |
| S5 Create T1     | 2      | ✅ PASS                | `questCount` = 1; `getQuest(1)` = (…, 100 pts, T1, active)                                                                                                                                                                         |
| S6 Complete T1   | 3      | ✅ PASS                | Alice points 100; nonce 0→1; tx `0x9dec8eba…` (FORK ONLY), gas 235,990                                                                                                                                                             |
| S7 Create T2     | 3      | ✅ PASS                | `questCount` = 2; `highestLiveThreshold` = 2; `liveAttestedQuestCount(2)` = 1                                                                                                                                                      |
| S8 Complete T2   | 3      | ✅ PASS                | Alice points 200; nonce 1→2 (once, not per signature); tx `0xb1235b9c…` (FORK ONLY), gas 195,351                                                                                                                                   |
| S9 Duplicate     | 4      | ✅ PASS                | `cast call` → `DuplicateAttestationSigner($V1)`, data `0x168e588e…`; on-chain tx status `0x0`; Bob points/nonce unchanged (0/0)                                                                                                    |
| S10 Insufficient | 4      | ✅ PASS                | `cast call` → `InsufficientAttestations(1, 2)`, data `0x78da11c2…`; on-chain tx status `0x0`; Bob unchanged                                                                                                                        |
| S11 H01          | 5      | ✅ PASS                | `cast call` → `InsufficientAttestations(1, 2)`; on-chain tx status `0x0`; `questCount` stayed 2; controls 1,001/T2 + 1,000/T1 created (count 4)                                                                                    |
| S12 Guardrail    | 11     | ✅ PASS                | `cast call` → `RevocationWouldBrickQuest(1, 2)`, data `0x8df6077d…`; blocked execute status `0x0`, op stayed Ready(2), role held; after deactivating Q2+Q3, re-execute succeeded (Done(3), `verifierCount` 1); re-grant restored 2 |
| S13 Supersedes   | 7      | ✅ PASS                | `supersedes(5)` = 2; Alice → `AlreadyCompletedSupersededQuest($ALICE, 5, 2)`, data `0x89c03273…`, points/nonce unchanged (200/2); Bob completed (points 100, nonce 1)                                                              |
| S14 Events       | 11     | ✅ PASS                | QuestCreated 5, QuestCompleted 3, PointsAdded 3, AttestationUsed 4, QuestDeactivated 2, QuestSuperseded 1, RoleGranted(QM) 7, RoleRevoked(QM) 2, CallScheduled 4, CallExecuted 4, OwnershipTransferred(mock) 2 — all exact         |
| **Total**        | **90** | **✅ 90 PASS, 0 FAIL** |                                                                                                                                                                                                                                    |

## 5. Fork-only addresses (ephemeral — NOT real testnet)

Deterministic across the three runs (same deployer nonce sequence
on the fork). These contracts exist only on the stopped local fork.

| Contract / actor            | Fork address                                 |
| --------------------------- | -------------------------------------------- |
| MockAgentId                 | `0xcdbf721Ae23D7340E90cD55251146ff3356b5979` |
| AgentGate                   | `0xF7144b91045C96b9300d8012b5dD2514088C79fF` |
| TimelockController          | `0x668B0Afb7d3Ca832C1ca739BfD4405B25178E9A8` |
| Reputation                  | `0x73866F4409B3E236ec4ABb48C915e9D0cCd27884` |
| Achievement                 | `0xBfC92bc58f965e9E8e17AABf95FdE2750B7ef40b` |
| QuestManager                | `0x58bB6D4F4c1eC10eA7D2d29A2354f2fE30B6498b` |
| Admin Safe (fork)           | `0xe0dF7b814767A09369D3E69654eb74f7778ee74F` |
| Creator Safe (fork)         | `0xda10d1A02d0F1754D71121D367bB62636e212d27` |
| Verifier 1 (key `0xA11CE5`) | `0x9950bc7D7d0bAF695CA9927361739B16b7BC48d3` |
| Verifier 2 (key `0xBEEF2`)  | `0xd81230B81c9445a80109D122F0dAd42dC8aA2802` |
| Alice (anvil 1)             | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` |
| Bob (anvil 2)               | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` |
| Deploy block (final run)    | `143738374` (fork head at run time)          |

Fork-only transaction hashes (revert proofs — for the record, not
for citation): S6 `0x9dec8eba03fe56a8107510c73a179ef9460c6a83a97c87c352487967a6058af5`,
S8 `0xb1235b9cf6e33c14282166215711a85e8705deea9e872d8faa9ae79277a610d9`,
S9 (failed) `0x9c8346c7e7f5ee02a080a4d99d16b60b7e4c364a7c95b05c0c495818d4ab42f3`,
S10 (failed) `0x9ffae94aa730823cbc78974feefdfacc1b0cbb950b331a1876b899d0bf10dfbd`,
S11 (failed) `0xa0a24b8bf1c6b97001cbc3d26b52edacdd2bbae3fb6da6f3805e62484238a0a9`,
S12 blocked execute (failed) `0x85876449f996fc7f3011cfbb993c95b2c8f963671c0e0a6612265ad5b13dc908`,
S13 Bob `0x8d0ece5f6d0639ba3d5c515f4b9efedefbb4da54ca7e6de144b04ffe2e40697c`.

## 6. Measured values carried into the live plan

| Measurement                                                              | Value                                                              | Where used                                                                                                       |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| Deploy total gas (6 CREATEs + 13 wiring CALLs, VERIFIER set)             | 8,307,890                                                          | Live plan §1 funding + Appendix E (supersedes the checklist's older 10,294,857, measured on older code/compiler) |
| T1 completion gas (cold account)                                         | 235,990 (`0x399d6`)                                                | Appendix E (vs 244,840 fresh-account unit benchmark)                                                             |
| T2 completion gas (warm account — second completion by the same account) | 195,351 (`0x2fb17`)                                                | Appendix E — documents that gas varies with warm/cold storage; live values are guides, not assertions            |
| Revert selectors observed live on the fork                               | `0x168e588e`, `0x78da11c2`, `0x8df6077d`, `0x89c03273`             | Appendix B (match the `cast sig` computations exactly)                                                           |
| `cast call` revert output format                                         | `Error: execution reverted: <Name>(args)` + raw data with selector | S9–S13 pre-check steps                                                                                           |

## 7. Issues found while building the dry-run (driver issues, not contract bugs)

Three runs were needed. None of the failures was a contract defect;
all were driver/tooling mistakes, each fixed in the driver and
documented here so the live run does not repeat them:

1. **Run 1 — Safe factory "no code" + short private key.**
   The first run's anvil fork had not served the factory code when
   the script ran (transient; a fork-state sanity check was added
   to the driver and later runs passed), and the verifier-2 test
   key was 63 hex chars (odd length — `cast` refuses it). Fixed
   with `printf '%064x'` key padding.
2. **Run 2 — `cast send --unlocked` needs prior impersonation.**
   This cast version's `--unlocked` sends via `eth_sendTransaction`
   and anvil rejects it ("No Signer available") unless
   `anvil_impersonateAccount` was called first for that address.
   The driver now impersonates both Safes up front. (Live-plan
   relevance: none — the live run uses the Safe UI, not
   impersonation — but the note is kept here for anyone re-running
   the fork driver.)
3. **Run 2 — `cast receipt --field` returned empty.** Switched to
   `cast receipt --json | jq -r .status` / `.gasUsed`.
4. **Run 3 (89/90) — `getQuest` tuple decoding.** `cast call`
   needs the struct return type written as a nested tuple:
   `getQuest(uint256)((uint256,address,…))` — single parens fail
   with "could not decode output". The live plan's S5/S7/S11
   commands use the corrected double-paren form (verified in the
   final run: `getQuest(1)` decoded to
   `(1, 0xda10…, "Smoke T1", …, 1, 2, 0x0…, 100, 0, …, 0, 0, true, 1)`).
5. **Reverted transactions need `eth_sendTransaction` for a hash.**
   `cast send` refuses to return a tx hash for a call that reverts
   (it errors at estimation/simulation). The driver's `send_raw`
   helper (impersonate + `eth_sendTransaction` via curl) lands the
   reverting call on-chain and returns its hash — that is how the
   S9–S12 failed-tx receipts (status `0x0`) were captured.
   (Live-plan relevance: for EOA sends, `cast send` still reports
   the revert and the hash appears in its output; for Safe sends,
   the Safe UI simulation shows the revert before submission.)

## 8. What the dry-run does NOT prove

- Nothing about the live chain: no live address, no live tx, no
  live BscScan decoding, no live Safe quorum, no live gas price.
- Source verification (`--verify` / BscScan) was not exercised —
  it cannot run against a fork.
- The frontend smoke (checklist §5.2) is out of scope for this
  workstream.
- The 2-day waits are real on live testnet; the dry-run's time
  warps compress ~6 days of wall-clock into ~35 seconds. Operator
  discipline across days (fresh attestations, no early Q5
  completion in the compressed schedule) is untested by the
  dry-run and is called out explicitly in the live plan.

## 9. Reproduction

```bash
cd ~/workspace/agenthub/agenthub-phase9-readiness/workstreams/fork-dryrun
./run-fork-dryrun.sh   # ~40 s; writes fork-dryrun.log; exit 0 iff all checks pass
```

Requirements: Foundry in `~/.foundry/bin`, network access to a BSC
testnet RPC, repo at HEAD `7dff852` (the driver runs
`DeployAgentHub.s.sol` from the repo). The driver starts its own
anvil fork on port 8545, cleans up its broadcast artifacts
(`broadcast/…/97/`) afterwards, and kills anvil on exit. It never
touches a real chain: every transaction goes to `127.0.0.1:8545`.

## 10. Second run — re-validated at HEAD `7dff852` (coordinator)

The dry-run was re-executed in full by the Phase 9 coordinator after
the Workstream 2 deploy-script changes (`7dff852`: distinct-Safes
guard PH9-D01 + `DeployMock` guard PH9-D02), to confirm the new
guards do not break the deploy flow.

| Item             | Run 1 (`e1b316b`)         | Run 2 (`7dff852`)                                          |
| ---------------- | ------------------------- | ---------------------------------------------------------- |
| Date             | 2026-11-20 ~00:51         | 2026-11-20 ~08:14                                          |
| Result           | 90/90 PASS                | **90/90 PASS**                                             |
| Deploy total gas | 8,307,890                 | **8,307,890**                                              |
| S6 (T1) gas      | 235,990                   | 235,990                                                    |
| S8 (T2) gas      | 195,351                   | 195,351                                                    |
| Log              | `fork-dryrun-e1b316b.log` | `fork-dryrun-7dff852.log` (`fork-dryrun.log` = latest run) |

Identical results: the new guards only add fail-closed reverts for
invalid configurations (same Safe twice, missing confirmation), and
the dry-run uses a valid configuration (two distinct Safes,
`CONFIRM_TESTNET_DEPLOY=true`), so the deploy path is unaffected.
The live plan remains validated against the current HEAD.
