# AGENTHUB — Deployment

## 1. Target

**Final deployment for the competition: BNB Chain mainnet (chainId 56),
source-verified on BscScan, with Agent ID actively used.**
BSC testnet (chainId 97) is staging — a proving ground, not the destination.
Nothing is deployed in Phase 1.

## 2. Environments

| Environment | Chain          | RPC (default)                                  | Agent ID               | Purpose                 |
| ----------- | -------------- | ---------------------------------------------- | ---------------------- | ----------------------- |
| Local       | Anvil 31337    | http://127.0.0.1:8545                          | MockAgentId            | Dev + integration tests |
| Staging     | BSC Testnet 97 | https://data-seed-prebsc-1-s1.binance.org:8545 | MockAgentId            | Public testing, demo    |
| Production  | BSC Mainnet 56 | https://bsc-dataseed1.binance.org              | Official `0x60b9…022F` | Competition submission  |

## 3. Prerequisites (Phase 2)

- Foundry (`forge` 1.x) and a funded deployer wallet:
  - Testnet: tBNB from the [BNB Chain testnet faucet](https://testnet.bnbchain.org/faucet-smart).
  - Mainnet: a small amount of BNB for gas (deploying 6 contracts is a few dollars).
- `BSCSCAN_API_KEY` for source verification (works for testnet + mainnet).
  Foundry reads it via the `[etherscan]` mapping in
  `packages/contracts/foundry.toml` (bsc + bsc-testnet) — see §5.
- `.env` file (from `.env.example`) with `DEPLOYER_PRIVATE_KEY` — a
  dedicated deployer wallet, never a personal main wallet, never committed.
- `ADMIN_MULTISIG` (a genuine Safe on the target chain, threshold ≥ 2)
  and `QUEST_CREATOR` — both required by the deploy script; see
  `docs/DEPLOYMENT_PLAN.md` §3 for the full variable list.

## 4. Deploy order

One script deploys the whole stack in dependency order — see
`docs/DEPLOYMENT_PLAN.md` (the authoritative procedure) and
`agenthub-final-pretestnet/FINAL_DEPLOYMENT_CHECKLIST.md` (the
operational checklist, incl. the 8 blocking user inputs):

```bash
cd packages/contracts

# Dry-run first (simulation only — no broadcast, no funds spent):
DEPLOYER_PRIVATE_KEY=<key> \
ADMIN_MULTISIG=<0x..> QUEST_CREATOR=<0x..> \
[PAUSER=<0x..>] [VERIFIER=<0x..>] [AGENT_ID_ADDRESS=<0x..>] \
forge script script/DeployAgentHub.s.sol --fork-url <rpc-url>

# Only after reviewing the dry-run output AND getting explicit approval:
# same command + --broadcast --verify
```

Order (single run): MockAgentId (testnet/local only, when
`AGENT_ID_ADDRESS` is unset) → AgentGate → TimelockController
(2-day delay) → Reputation → Achievement → QuestManager, then role
wiring, MockAgentId ownership transfer to the multisig (PH7-M04),
admin handover to the timelock, deployer renounce, and
post-deploy verification (`_verifyWiring` reverts on any mismatch —
30 checks on testnet/local, 29 on mainnet where no mock is deployed,
including `mock.owner() == multisig`). The script validates
`ADMIN_MULTISIG` AND `QUEST_CREATOR` as genuine Safes (canonical
singleton + proxy codehash + threshold ≥ 2) BEFORE deploying anything
(PH7-M03). Testnet requires `CONFIRM_TESTNET_DEPLOY=true` (PH7-M05);
mainnet additionally requires the official Agent ID address and
`CONFIRM_MAINNET_DEPLOY=true`.

After each deploy, update `apps/web/.env.local` with the new addresses
(`NEXT_PUBLIC_*_ADDRESS`, `NEXT_PUBLIC_DEPLOY_BLOCK`) and redeploy the
frontend.

## 5. BscScan verification

`forge script ... --broadcast --verify` verifies automatically.
To verify one contract manually:

```bash
forge verify-contract <ADDRESS> <ContractName> \
  --chain 97 \
  --verifier etherscan \
  --constructor-args $(cast abi-encode "constructor(...)" <ARGS>)
```

Notes (Phase H, verified 2026-11-19):

- The verifier is `etherscan` (BscScan is Etherscan-compatible) —
  `--verifier bscscan` is not a valid foundry value and fails
  immediately. `--chain 97` / `--chain 56` resolve the BscScan API
  URLs from foundry's built-in config; no `--verifier-url` needed.
- The API key comes from `BSCSCAN_API_KEY` via the `[etherscan]`
  mapping in `packages/contracts/foundry.toml`. Foundry does NOT
  read `BSCSCAN_API_KEY` on its own — without that mapping,
  verification fails with "ETHERSCAN_API_KEY must be set".
  (Alternatively: export `ETHERSCAN_API_KEY=$BSCSCAN_API_KEY` or
  pass `--etherscan-api-key "$BSCSCAN_API_KEY"`.)
- Without `BSCSCAN_API_KEY` set, verification fails fast with
  "environment variable `BSCSCAN_API_KEY` not found". Build, test,
  and CI are unaffected (the mapping is only evaluated when
  verifying).

Mainnet uses `--chain 56`. Verification is mandatory for the
hackathon submission — unverified contracts are not eligible.

## 6. Mainnet checklist (all must be true before mainnet deploy)

- [ ] All four contracts implemented, with unit + fuzz + invariant tests green.
- [ ] Full testnet deploy exercised end-to-end by at least 2 wallets
      (quest create → complete → points → badge → leaderboard).
- [ ] Independent security review completed; findings fixed or documented.
- [ ] Admin roles assigned to a multisig (no single-key admin).
- [ ] Pause mechanism tested on testnet.
- [ ] Frontend pointed at mainnet addresses; staging frontend kept for testnet.
- [ ] BscScan verification passing for every contract.
- [ ] Submission draft reviewed (project name, website, contract addresses,
      Agent ID usage description).

## 7. Rollback and incident handling

- Contracts are non-upgradeable in Phase 1 design. A critical bug means:
  pause → deploy a fixed version → migrate quest definitions → announce.
- User points/badges live in the deployed contracts; a redeploy starts fresh
  state, so mainnet deploys must be right the first time — hence the
  testnet-first rule and the review gate.
- Never deploy to mainnet from a dirty working tree or without a tagged release.

## 8. Frontend deployment (Vercel)

- Connect the GitHub repo; framework preset Next.js; root directory `apps/web`.
- Environment variables (per environment, in Vercel — never in the repo):
  `NEXT_PUBLIC_CHAIN_ID`, `NEXT_PUBLIC_AGENT_ID_ADDRESS`,
  `NEXT_PUBLIC_*_ADDRESS`, `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`.
- Preview deployments for every PR; production deploy from `main` only.
