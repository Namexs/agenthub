# AGENTHUB — Testnet Deployment Readiness (Phase H)

**Date:** 2026-11-19. **Phase:** H — Testnet deployment preparation.
**Scope:** the deploy script, Safe validation, live BSC testnet (97)
state, BscScan verification config, env validation, deployment order,
and post-deploy verification — **no broadcast**. Nothing in this phase
touched the real testnet with a write: the full deployment ran against
a local anvil fork of testnet, and every live-chain read was read-only.
**Verdict: GATE H — PASSED.** The deployment machinery is proven
end-to-end with the current script against a genuine Safe on a chain-97
fork. All 8 user inputs from the deployment checklist are still
missing — that is expected, documented in §6, and blocks any real
broadcast.

## 1. What was verified

### 1.1 Deploy script (read in full)

`packages/contracts/script/DeployAgentHub.s.sol` — `run()` (env-driven)

- `deploy()` (parameterized, unit-tested core):

* Chain guard: only 56 / 97 / 31337 (`UnsupportedChain` otherwise).
* Mainnet requires `CONFIRM_MAINNET_DEPLOY=true` AND the official
  Agent ID (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`); both are
  enforced in the script and again in `AgentGate`.
* `ADMIN_MULTISIG` is validated as a GENUINE Safe **before anything
  deploys** (canonical singleton v1.3.0/v1.4.1 + canonical proxy
  codehash + `VERSION()` + threshold ≥ 2). Explicit singleton/codehash
  overrides are rejected on 56/97 — the canonical path cannot be
  bypassed. On 31337 only, the explicit path is allowed.
* Order: MockAgentId (97/31337, only when `AGENT_ID_ADDRESS` is unset)
  → AgentGate → TimelockController (2-day delay, multisig
  proposer/executor, self-administered, no optional admin) →
  Reputation → Achievement → QuestManager → role wiring → admin
  handover to the timelock → deployer renounces → `_verifyWiring`.
* `_verifyWiring` runs **29 checks** (counted from the code: 5 identity
  - 5 timelock + 3 admin + 6 operational roles + 10 deployer-has-nothing)
    and reverts the whole deployment on any mismatch. The deployer ends
    with zero privileges.
* Missing required env fails fast: `forge script` without
  `ADMIN_MULTISIG` aborts with
  `vm.envAddress: environment variable "ADMIN_MULTISIG" not found`
  (exit 1, before any transaction — evidence
  `phase-h-bscscan-env-probes.log` §C). Same for `QUEST_CREATOR` and
  `DEPLOYER_PRIVATE_KEY` (all read via `vm.envAddress`/`vm.envUint`).

### 1.2 Live BSC testnet reads (read-only, publicnode)

`phase-h-live-testnet-reads.log` (2026-11-19, block 143,639,153):

| Check                                        | Result                                                                  |
| -------------------------------------------- | ----------------------------------------------------------------------- |
| Chain id                                     | 97                                                                      |
| Gas price                                    | 138,367,187 wei (~0.138 gwei)                                           |
| Official Agent ID `0x60B9…B022F` code        | `0x` — does NOT exist on testnet (MockAgentId is required, as designed) |
| Previous dry-run "Safe" `0x1111…1111` code   | `0x` — no code (see §2)                                                 |
| Safe singleton v1.4.1 `0x4167…7461a`         | Deployed, `VERSION()` = "1.4.1"                                         |
| Safe singleton v1.3.0 `0xd9Db…9552`          | Deployed, `VERSION()` = "1.3.0"                                         |
| SafeProxyFactory v1.4.1 `0x4e1D…ec67`        | Deployed                                                                |
| GnosisSafeProxyFactory v1.3.0 `0xa6B7…96AB2` | Deployed                                                                |

### 1.3 Full deployment on a chain-97 fork (the core proof)

The previous testnet dry-run (committed broadcast file, 10,294,857
gas) **predates SafeValidation**: its file timestamp is 2026-11-19
07:45 UTC; the validation was integrated at 08:56 UTC (commit
`657502f`) and hardened at 09:39 UTC (`ba32dc5`). It used placeholder
`ADMIN_MULTISIG = 0x1111…1111` (no code — see §1.2), which the
current script rejects. That dry-run proves the deploy mechanics and
gas, but NOT that the current script passes on testnet. Phase H
re-ran the proof properly:

- **Setup:** anvil forked from BSC testnet (publicnode) at block
  143,638,489, `--chain-id 97`, local port 8546. A genuine Safe proxy
  was created on the fork via the canonical v1.4.1 factory (2 owners,
  threshold 2) — fork state only, discarded afterwards. The deployer
  was a fresh throwaway key, funded only on the fork via
  `anvil_setBalance`; the key file was deleted at the end of the
  phase and the fork shut down.
- **ValidateSafe (positive):** `threshold 2`, 2 owners, `OK:
ADMIN_MULTISIG is a genuine Safe with threshold >= 2`, exit 0.
- **ValidateSafe (negative):** `ADMIN_MULTISIG=0x1111…1111` reverts
  with `NotASafe(0x1111…, "no code")`, exit 1 — the guard bites on
  the current script.
- **Deploy:** `forge script DeployAgentHub.s.sol --rpc-url
<local fork> --broadcast` (to the LOCAL fork only), exit 0,
  `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL` — 6 CREATEs + 12 wiring
  CALLs (18 txs; 12 calls because a verifier was granted, vs 11 in
  the old dry-run). Estimated gas 10,937,808; actual gas used
  8,378,658 (`phase-h-fork-deploy.log`). Fork-only addresses (not
  real testnet deployments): MockAgentId `0x1CAAD50d…a433`,
  AgentGate `0xE403096A…02F9`, Timelock `0x64548FDa…27F6`,
  Reputation `0x02d57280…18b9`, Achievement `0x77E4fE4E…4bB8`,
  QuestManager `0xf563c294…B117`.
- **Post-deploy verification** (checklist §4.3 items 8–14, all read
  against the fork — `phase-h-fork-postdeploy-verify.log`):
  gate.agentId == MockAgentId ✓; minted a test Agent ID and
  `isAgentHolder(holder) == true`, `isAgentHolder(non-holder) ==
false` ✓; QuestManager gate/reputation/achievement point at the
  deployed contracts ✓; DEFAULT_ADMIN_ROLE == timelock on all three
  contracts ✓; SCORE_SOURCE_ROLE / ISSUER_ROLE == QuestManager ✓;
  BADGE_MANAGER_ROLE == Safe ✓; QUEST_CREATOR_ROLE == creator ✓;
  PAUSER_ROLE == Safe (default, `PAUSER` unset) ✓; VERIFIER_ROLE ==
  first verifier ✓; deployer holds NO role (6 checks, all false) ✓;
  timelock `getMinDelay() == 172800` (2 days), proposer/executor/
  canceller == Safe, self-administered, multisig NOT admin ✓;
  all three contracts unpaused ✓.

### 1.4 Funding math

At the live testnet gas price (~0.138 gwei): actual deploy cost ≈
8,378,658 × 0.138 gwei ≈ **0.00116 tBNB** (estimate-based ≈ 0.0015
tBNB). The checklist's recommendation to fund the deployer with
**≥ 0.05 tBNB** has 30×+ margin for verification + smoke tests.
No change needed.

### 1.5 BscScan verification config — a real defect, fixed

**Foundry does NOT read `BSCSCAN_API_KEY`.** Proven 2026-11-19: with
only `BSCSCAN_API_KEY` set, `forge verify-contract --chain 97
--verifier etherscan` fails with `ETHERSCAN_API_KEY must be set to
use Etherscan as a verifier` — the same error as with no key at all.
With `ETHERSCAN_API_KEY` set to a bogus value, the key IS sent
(BscScan answers "Invalid API Key"). The repo documents
`BSCSCAN_API_KEY` (`.env.example`, checklist §1 item 7, §4.2 step 5),
so an operator following the docs would have hit a verification
failure on deployment day.

**Fix:** added an `[etherscan]` section to
`packages/contracts/foundry.toml` mapping both BSC chains to the
documented variable (env interpolation — no key material in the
file):

```toml
[etherscan]
bsc = { key = "${BSCSCAN_API_KEY}" }
bsc-testnet = { key = "${BSCSCAN_API_KEY}" }
```

Proven working: with `BSCSCAN_API_KEY=<bogus>`, verification on both
chain 97 and chain 56 now sends the key (BscScan answers "Invalid API
Key" instead of "must be set"). Without the variable set, verification
fails fast with `environment variable BSCSCAN_API_KEY not found`.
Build, test, and CI are unaffected — the mapping is only evaluated
when verifying (`forge build` / `forge test` exit 0 without the
variable set; `forge script` without `--verify` never touches it).
`--chain 97` / `--chain 56` resolve the BscScan API URLs from
foundry's built-in config (probe: `forge verify-contract --chain 97`
prints "deployed on bsc-testnet" and starts verifying).

## 2. Documentation fixes in this phase

| File                    | Problem                                                                                                                                                                                  | Fix                                                                                                                    |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `docs/DEPLOYMENT.md` §4 | Stale Phase 1/2 deploy order (via `DeployMock.s.sol`, then "scripts land in Phase 2", QuestManager before Reputation/Achievement — impossible, the QM constructor takes their addresses) | Rewritten to the real single-script deploy + order, pointing at `DEPLOYMENT_PLAN.md` (authoritative) and the checklist |
| `docs/DEPLOYMENT.md` §3 | "deploying 4 contracts"                                                                                                                                                                  | 6 contracts (MockAgentId + Timelock included)                                                                          |
| `docs/DEPLOYMENT.md` §5 | `--verifier bscscan` is INVALID in foundry 1.9.0 (possible values: etherscan, sourcify, blockscout, oklink, custom) — the documented command fails immediately                           | Rewritten: `--verifier etherscan`, `--chain 97/56`, the `BSCSCAN_API_KEY` mapping note, fail-fast behavior             |
| `.env.example`          | Missing `ADMIN_MULTISIG`, `QUEST_CREATOR`, `PAUSER`, `VERIFIER` (all read by the deploy script) and `NEXT_PUBLIC_DEPLOY_BLOCK` (required by the frontend once contracts are configured)  | All added, placeholders only                                                                                           |
| `.env.example`          | Testnet RPC                                                                                                                                                                              | Publicnode added as a commented fallback (see §3)                                                                      |

`docs/DEPLOYMENT_PLAN.md` (2026-11-19) was checked against the script
and is accurate — no changes. Note its §3 dry-run evidence refers to
the pre-SafeValidation dry-run (§1.3); this report supersedes that
evidence.

## 3. Operational findings (no code change)

- **RPC reliability:** the `.env.example` testnet RPC
  (`data-seed-prebsc-1-s1.binance.org:8545`) timed out repeatedly
  from this VM (5 timeouts in one batch, ~240s total).
  `bsc-testnet-rpc.publicnode.com` answered the same reads in ~2.5s.
  `DEPLOYMENT_PLAN.md` §3 already recommends publicnode (the dataseed
  returned 403 from the build VM earlier). Deployment day should use
  publicnode (or another reliable endpoint) as primary.
- **Anvil test accounts are heavily used on BSC testnet** (live
  nonces: account #0: 20,028; #1: 4,208; #2: 1,905; #3: 1,230;
  #4: 483). Fork simulations must use fresh keys — the well-known
  anvil accounts caused "insufficient funds" rejections in this
  phase's first fork attempts (nonce mismatch against fork state).
  Fresh key + `anvil_setBalance` is the working pattern.
- **Broadcast files are gitignored.** The fork deploy's broadcast
  record (`packages/contracts/broadcast/…/97/run-latest.json`) and
  the old dry-run files are local-only, not committed. The deployment
  record for the real deploy (`docs/DEPLOYMENT_RECORD.md`, to be
  created on deployment day per the checklist) is what must be kept.

## 4. Files changed in this phase

| File                                                     | Change                                                                                                             |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `packages/contracts/foundry.toml`                        | `[etherscan]` mapping: bsc + bsc-testnet keys from `${BSCSCAN_API_KEY}`                                            |
| `docs/DEPLOYMENT.md`                                     | §3 (6 contracts), §4 (real deploy order), §5 (valid verifier + key mapping)                                        |
| `.env.example`                                           | Added `ADMIN_MULTISIG`, `QUEST_CREATOR`, `PAUSER`, `VERIFIER`, `NEXT_PUBLIC_DEPLOY_BLOCK`; publicnode RPC fallback |
| `agenthub-final-release/TESTNET_DEPLOYMENT_READINESS.md` | This report                                                                                                        |
| `agenthub-final-release/logs/phase-h-*`                  | 4 evidence logs (fork deploy, post-deploy verification, live testnet reads, BscScan/env probes)                    |

No contract code, no frontend code, and no test was changed in this
phase. No deployment was broadcast anywhere.

## 5. What is still missing (BLOCKING — from the user)

Unchanged from the checklist §1 — none of these has been received.
Phase H validated structure only and invented no addresses.

| #   | Item                                                                   | Status       |
| --- | ---------------------------------------------------------------------- | ------------ |
| 1   | tBNB for gas (≥ 0.05 tBNB recommended)                                 | NOT RECEIVED |
| 2   | Dedicated deployer key (single-use, via a secure channel — never chat) | NOT RECEIVED |
| 3   | Admin multisig (Safe) address on BSC testnet, threshold ≥ 2            | NOT RECEIVED |
| 4   | Quest creator address                                                  | NOT RECEIVED |
| 5   | First verifier address (optional — can be granted later via timelock)  | NOT RECEIVED |
| 6   | Pauser address (optional — defaults to the multisig)                   | NOT RECEIVED |
| 7   | BscScan API key                                                        | NOT RECEIVED |
| 8   | Explicit approval to broadcast this specific testnet deployment        | NOT RECEIVED |

Before any broadcast, the Safe in item 3 must additionally pass the
5-step independent verification in `DEPLOYMENT_PLAN.md` §5.1 (Safe
web app, out-of-band owner confirmation, BscScan creation trace,
`ValidateSafe.s.sol`, test-sign) — the on-chain check proves the
address IS a genuine Safe, not that it is THE TEAM'S Safe.

## 6. Gate H verdict

**GATE H — PASSED.** The deploy script, Safe validation, BscScan
config, env handling, deployment order, and post-deploy verification
are all proven against live testnet state and a full fork deployment
with a genuine Safe. The 8 deployment inputs remain with the user;
no broadcast is authorized or attempted.
