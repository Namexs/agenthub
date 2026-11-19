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
  - Mainnet: a small amount of BNB for gas (deploying 4 contracts is a few dollars).
- `BSCSCAN_API_KEY` for source verification (works for testnet + mainnet).
- `.env` file (from `.env.example`) with `DEPLOYER_PRIVATE_KEY` — a
  dedicated deployer wallet, never a personal main wallet, never committed.

## 4. Deploy order (Phase 2)

Contracts deploy in build order; each step records its address before the next:

```bash
# 1. Testnet staging — mock Agent ID first (official contract is not on testnet)
forge script script/DeployMock.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast --verify

# 2-5. AGENTHUB contracts (scripts land in Phase 2, in this order)
#   AgentGate(mockAgentId) -> QuestManager(gate) -> Reputation(questManager)
#   -> Achievement(questManager)
#   Each deploy script asserts the expected chainId before broadcasting.

# 6. Mainnet — same scripts, official Agent ID address, --rpc-url $BSC_MAINNET_RPC_URL
#   Mainnet deploy requires the full checklist in section 6 to be complete.
```

After each deploy, update `apps/web/.env.local` with the new addresses
(`NEXT_PUBLIC_*_ADDRESS`) and redeploy the frontend.

## 5. BscScan verification

```bash
forge verify-contract <ADDRESS> <ContractName> \
  --chain-id 97 \
  --verifier bscscan \
  --verifier-url https://api-testnet.bscscan.com/api \
  --etherscan-api-key $BSCSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" <ARG>)
```

Mainnet uses `--chain-id 56` and `https://api.bscscan.com/api`.
Verification is mandatory for the hackathon submission — unverified contracts
are not eligible.

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
