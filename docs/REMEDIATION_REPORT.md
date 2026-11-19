# Security Review Remediation Report

**AGENTHUB — user-led source review follow-up**
**Date:** 2026-11-19
**Baseline:** `c568ee0` (code identical to `8b8751e`, the ZIP the user inspected)
**Remediation commits:** `8c5122f` (TEMUAN 2), `655cbb2` (TEMUAN 1 + 3),
`7d3d386` (TEMUAN 4), plus this report set (P3).
**Test result:** **193/193 passing** (baseline 120/120 — no test removed,
73 added; see `REGRESSION_RESULTS.md`).

## Background

On 2026-11-19 the project owner inspected the source ZIP (`8b8751e`) himself
and found 2 design problems. Neither was Critical/High, but both affect the
integrity of the platform, so he decided: **BELUM GO testnet** until both
are fixed and tested. This report documents the fixes, the proof, and what
remains open. The owner also reviewed Reputation and Achievement statically
(design sound on first look — not a formal audit); no changes were made to
those two contracts in this remediation.

## TEMUAN 1 (P1) — Quest completion did not prove the task was done

**Severity:** design flaw, integrity-critical. **Status: FIXED, proven.**

### Before

`QuestManager.completeQuest` (`c568ee0`, `src/QuestManager.sol`) checked only
Agent ID ownership, quest status/window, caps, duplicates, and cooldowns,
then awarded points and a badge. Calling the function was the entire proof.

```solidity
// c568ee0 — completeQuest: no validation of the actual task
function completeQuest(uint256 questId) external nonReentrant whenNotPaused {
    Quest storage quest = _quests[questId];
    if (quest.id == 0) revert QuestNotFound(questId);
    gate.requireAgentHolder(msg.sender);
    if (!quest.active) revert QuestNotActive(questId);
    // ... window / cap / duplicate / cooldown checks ...
    // ... award points + badge ...
}
```

### After

Every quest declares a `ValidationKind` at creation (`IQuestManager.sol:29`,
`QuestManager.sol:98-151`):

- `CheckIn` — explicit self-check-in; the call IS the activity, labeled honestly.
- `OnChain` — a validator contract (`IQuestValidator`) must confirm a live
  on-chain condition at completion time (`QuestManager.sol:233-238`).
- `Attested` — completion requires an EIP-712 attestation from a
  `VERIFIER_ROLE` signer via `completeQuestWithAttestation`
  (`QuestManager.sol:168-208`): per-account nonce, 7-day max lifetime,
  chainId + contract + account + questId binding, malleability-safe recovery,
  role checked at verification time (revocation invalidates outstanding
  attestations immediately).

`completeQuest` reverts with `AttestationRequired` on Attested quests, so
there is no path to complete one without an attestation. Full design:
`QUEST_VALIDATION_DESIGN.md`.

New files: `src/interfaces/IQuestValidator.sol`,
`src/validators/TokenBalanceValidator.sol` (fail-closed reference validator).

### Proof (regression tests)

- `test/Attestation.t.sol` — 24 tests: valid completion, replay rejection,
  wrong nonce/account/quest, cross-chain replay (chainId 56 domain),
  cross-contract replay (second QuestManager), unauthorized signer, verifier
  rotation (revoke invalidates immediately), admin-only role grant,
  expired / too-far / max-lifetime deadlines, malleable-signature rejection,
  empty/zero/short signatures, non-holder with valid attestation (nonce not
  consumed), failed completion does not burn the nonce, attested farming
  bounded by cooldown, paused reverts, 2 fuzz tests.
- `test/Validator.t.sol` — 14 tests: TokenBalanceValidator units + fuzz,
  live re-check on every completion, reverting/garbage/reentrant/always-true
  validators (reentrant → exactly one award).
- `test/QuestManager.t.sol` — 8 new tests: kind/validator creation rules,
  `AttestationRequired` / `QuestNotAttested` paths, dependency rejection.
- `test/AccessControl.t.sol` — verifier role matrix (1 test).
- `test/Integration.t.sol` — verifier granted through the 2-day timelock
  (1 test).
- `test/Invariant.t.sol` — a 5th quest (OnChain) added to the handler.

## TEMUAN 2 (P1) — AgentGate did not pin the official Agent ID address

**Severity:** design flaw, integrity-critical. **Status: FIXED, proven.**

### Before

`AgentGate`'s constructor (`c568ee0`, `src/AgentGate.sol:23-31`) accepted
**any** non-zero address with code as the Agent ID contract. On mainnet,
a deployment wired to the wrong ERC-721 would have trusted its holders as
Agent ID holders.

```solidity
// c568ee0 — constructor: any contract address accepted
constructor(address agentId_, uint256 expectedChainId_) {
    if (agentId_ == address(0)) revert ZeroAddress();
    if (agentId_.code.length == 0) revert NoCodeAtAgentId(agentId_);
    if (expectedChainId_ == 0) revert InvalidChainId(expectedChainId_);
    if (expectedChainId_ != block.chainid) {
        revert WrongChain(expectedChainId_, block.chainid);
    }
    agentIdContract = agentId_;
    expectedChainId = expectedChainId_;
}
```

### After

`src/AgentGate.sol:23-56` pins the official address and allowlists chains:

```solidity
address public constant OFFICIAL_AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
uint256 public constant BSC_MAINNET_CHAIN_ID = 56;
uint256 public constant BSC_TESTNET_CHAIN_ID = 97;
uint256 public constant LOCAL_CHAIN_ID = 31337;

// constructor (after the existing checks, order preserved):
if (expectedChainId_ != BSC_MAINNET_CHAIN_ID
    && expectedChainId_ != BSC_TESTNET_CHAIN_ID
    && expectedChainId_ != LOCAL_CHAIN_ID) {
    revert UnsupportedChain(expectedChainId_);
}
if (expectedChainId_ == BSC_MAINNET_CHAIN_ID && agentId_ != OFFICIAL_AGENT_ID) {
    revert UnofficialAgentId(agentId_, expectedChainId_);
}
```

| Chain            | Accepted Agent ID                                 |
| ---------------- | ------------------------------------------------- |
| 56 (BSC mainnet) | ONLY `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` |
| 97 (BSC testnet) | MockAgentId (or any contract — testnet only)      |
| 31337 (local)    | Local mock                                        |
| any other        | Rejected (`UnsupportedChain`)                     |

New errors in `IAgentGate.sol:21-23`: `UnofficialAgentId`,
`UnsupportedChain`. The official address is the EIP-55 checksummed form,
verified with `cast --to-checksum-address`.

### Proof (regression tests)

- `test/AgentGateMainnet.t.sol` — 10 tests: official constant pinned;
  mainnet accepts the official address (mock code etched at it); mainnet
  rejects the mock, a fake ERC-721, and an arbitrary contract; testnet and
  local accept the mock; chains 1 and 137 rejected; `WrongChain` still fires
  before the mainnet lock on chain 31337. AgentGate suites: 28/28.
- `test/DeployScript.t.sol` — mainnet deploy with a mock or zero address
  reverts at the script level (defense in depth).

## TEMUAN 3 (P2) — QuestManager dependency validation

**Severity:** hardening. **Status: FIXED, proven (with a documented limit).**

### Before

The constructor (`c568ee0`) checked only that the three dependency addresses
were non-zero. An EOA or a wrong contract would have been accepted and the
failure would surface later, at first use.

### After

`src/QuestManager.sol:85-87` adds a code-length check for each dependency:

```solidity
if (gate_.code.length == 0) revert NoCodeAtDependency(gate_);
if (reputation_.code.length == 0) revert NoCodeAtDependency(reputation_);
if (achievement_.code.length == 0) revert NoCodeAtDependency(achievement_);
```

New error `NoCodeAtDependency` (`IQuestManager.sol:66`).

### Documented limit

A code-length check proves an address is a contract, **not** that it is the
right contract or a trustworthy one. A malicious or misconfigured contract
with the right function signatures could still be wired in. The mitigation
is deployment-time discipline, not a runtime check: the deployment script
deploys all four contracts itself in one run and asserts the wiring
(`_verifyWiring`), and the deployment trust assumptions are documented in
`DEPLOYMENT_PLAN.md` §4. Integration coverage: `test/Integration.t.sol`
(7 tests, incl. the full wiring through the timelock) and
`test/DeployScript.t.sol` (end-to-end completion through a deployed stack).

### Proof

- `test_ConstructorRejectsEoaDependencies` (QuestManager.t.sol) — all three
  dependencies rejected as EOAs.
- `test_DeployedStackWorksEndToEnd` (DeployScript.t.sol) — mint → create →
  complete → 100 points through the script-deployed stack.

## TEMUAN 4 (P2) — Deployment script

**Severity:** missing tooling (was manual). **Status: DONE, tested (dry-run only).**

New file `packages/contracts/script/DeployAgentHub.s.sol` (271 lines):

- **Order:** MockAgentId (testnet/local only, when `AGENT_ID_ADDRESS` is
  unset) → AgentGate → TimelockController (2-day delay, multisig
  proposer/executor, NO optional admin — the timelock self-administers via
  proposals, per OZ guidance) → Reputation → Achievement → QuestManager.
- **Role wiring:** `SCORE_SOURCE_ROLE` + `ISSUER_ROLE` to QuestManager,
  `BADGE_MANAGER_ROLE` to the multisig, `QUEST_CREATOR_ROLE` to the creator,
  `PAUSER_ROLE` to the pauser, optional `VERIFIER_ROLE` to the first
  verifier; `DEFAULT_ADMIN_ROLE` to the timelock on all three contracts;
  the deployer renounces admin everywhere.
- **Post-deploy verification:** `_verifyWiring` asserts every identity link,
  every role, the timelock delay, and that the deployer holds **no** role
  anywhere — the script reverts if any check fails.
- **Mainnet guards:** chain 56 requires the official Agent ID address AND
  the explicit `CONFIRM_MAINNET_DEPLOY=true` opt-in; without both, the
  script reverts. There is no automatic deployment to any network.
- **Structure:** parameterized `deploy(params, deployer)` (testable without
  env vars or keys) + thin env-driven `run()` wrapper with `startBroadcast`.
  The deployer address is derived from the key via `vm.addr`, never
  `msg.sender` (under broadcast, calls originate from the key's address).

### Proof

- `test/DeployScript.t.sol` — 15 tests, including `run()` end-to-end via
  `vm.setEnv` + `startBroadcast` with the public Anvil test key (local
  simulation only), mainnet refusal without confirmation, and mainnet
  deployment with confirmation + official address.
- CLI dry-run, local: `forge script script/DeployAgentHub.s.sol` —
  success, 8,467,332 gas, all 6 contracts + wiring simulated, no broadcast.
- CLI dry-run, BSC testnet fork (publicnode): `SIMULATION COMPLETE`,
  10,294,857 gas (~0.00103 BNB), 6 CREATEs + 11 role-wiring CALLs, no
  broadcast. (The BNB Chain dataseed RPC returned 403 from this VM; the
  publicnode endpoint worked.)
- **No deployment was performed.** No private key with funds was used; no
  real network received a transaction.

## P3 — Review package fixes

- **README.md:** the stale "Phase 1 — Repository Foundation / contracts not
  implemented" status is replaced with the true current status (contracts
  implemented, reviewed, remediated, 193/193 tests; nothing deployed,
  nothing submitted). Layout and contract sections updated; docs index now
  links the five new reports.
- **PACKAGE_MANIFEST.md** (repo root): commit hash, submodule commits, and
  a sha256 list of every tracked file in the described commit, with honest
  verification instructions (`git clone --recurse-submodules`, checkout the
  commit, run `scripts/verify-manifest.sh`). The manifest documents that
  `git archive` omits submodules and `.git` metadata, so a ZIP alone cannot
  prove its commit origin — the manifest + the verification script close
  that gap.
- **scripts/verify-manifest.sh / scripts/generate-manifest.sh:** recompute
  and compare file hashes; check submodule commits.
- The earlier mismatch (security report said snapshot `c666878`, ZIP was
  `8b8751e`) is addressed by the manifest: the described commit is recorded
  explicitly and is verifiable.

## What did NOT change

- `Reputation.sol` and `Achievement.sol`: no code changes (owner's static
  review found the design sound; not a formal audit).
- `MockAgentId.sol`: no changes.
- Frontend: no contract-call changes (the web app does not call
  `createQuest`/`completeQuest` yet — only a `balanceOf` ABI + placeholder
  UI), so the signature change does not break the build.
- No existing test was deleted or weakened; 48 `createQuest` call sites
  were updated to pass the explicit `CheckIn` kind with identical behavior
  (documented in `REGRESSION_RESULTS.md` §3).

## Remaining work (needs the owner)

1. **Testnet staging decision** — the remediation is complete and tested;
   the GO/NO-GO for BSC testnet deployment is the owner's call.
2. **Testnet blockers (unchanged):** tBNB for gas, a dedicated deployer key,
   the multisig/creator/pauser/verifier addresses, a BscScan API key for
   verification.
3. **External review** — this remediation was self-tested (unit/fuzz/
   invariant/attack simulation + Slither). An independent review is still
   recommended before mainnet.
4. **Verifier operations** — who holds VERIFIER_ROLE keys, key hygiene, and
   the revocation procedure must be decided before any Attested quest goes
   live (see `QUEST_VALIDATION_DESIGN.md` §2.3 and `NEW_THREAT_MODEL.md`
   T-ATT-01).
