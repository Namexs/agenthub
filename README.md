# AGENTHUB — Your Agent ID. Your Onchain Reputation.

Activity and reputation platform for Binance Agent ID holders, built for the
[Binance Wallet Agent ID Hackathon](https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf)
(total rewards 60,000 USDC).

AGENTHUB combines a quest marketplace, on-chain reputation, soulbound
(non-transferable) achievement badges, and a transparent leaderboard — all
gated by real Agent ID ownership on BNB Chain.

> **Status: contracts implemented, security-reviewed, and remediated.**
> All four contracts (AgentGate, QuestManager, Reputation, Achievement) are
> implemented with a TimelockController admin, a deployment script, and
> **193/193 Foundry tests passing** (baseline 120 before the remediation).
> A user-led review of the source found 2 design issues (quest completion
> did not prove the task was done; AgentGate did not pin the official
> Agent ID address on mainnet) — both are fixed and regression-tested; see
> `docs/REMEDIATION_REPORT.md`. **Nothing is deployed yet, and nothing has
> been submitted to the hackathon.** Testnet staging awaits the owner's
> go-ahead; final deployment targets BSC mainnet.

## Competition target

- **Final deployment: BNB Chain mainnet (chainId 56)**, source-verified on
  BscScan, with Agent ID actively used. Testnet (chainId 97) is staging only.
- **Submission deadline: 9 December 2026, 08:00 UTC (15:00 WIB).**
- Innovation Award eligibility needs a live product + at least 30 unique Agent
  ID addresses interacting during the submission period.

## Quality standard

Every feature must be genuinely usable and **provable by an on-chain
transaction** — not just look good. Quest completions, reputation changes, and
badge issues are all transactions with BscScan links. If it cannot be verified
on-chain, it does not ship as a feature.

## Repository layout

```
agenthub/
├── apps/web/                 Next.js 14 + TypeScript + Tailwind app
│   ├── app/                  App Router: landing, dashboard, quests,
│   │                         profile, leaderboard, campaigns, history, security
│   ├── components/           Navbar, ConnectButton, QuestCard, BadgeCard, ...
│   ├── hooks/                useAgentId, useReputation, useQuests
│   └── lib/                  env validation, wagmi config, contract ABIs
├── packages/
│   ├── contracts/            Foundry: 4 implemented contracts + validators
│   │   ├── src/              AgentGate, QuestManager, Reputation, Achievement,
│   │   │                     validators/, mocks/, interfaces/
│   │   ├── script/           DeployAgentHub.s.sol (dry-run only, no broadcast)
│   │   └── test/             193 tests (unit, fuzz, invariant, attack sim)
│   ├── shared/               Types + constants (chains, addresses, thresholds)
│   └── config/               Shared TS / ESLint / Tailwind preset (theme tokens)
├── docs/                     ARCHITECTURE, SECURITY, DEPLOYMENT, USER_GUIDE
└── .github/workflows/        CI (lint + typecheck + build + forge test)
```

## Quickstart

Prerequisites: Node.js 20+, pnpm 9.15.4, Foundry (forge 1.x).

```bash
# Install JS dependencies (workspace)
pnpm install

# Install Solidity dependencies (OpenZeppelin)
cd packages/contracts && forge install

# Run the web app (http://localhost:3000)
pnpm dev

# Build / lint / typecheck / test everything
pnpm build
pnpm lint
pnpm typecheck
pnpm test

# Contracts only
pnpm --filter @agenthub/contracts build
pnpm --filter @agenthub/contracts test
```

Copy `.env.example` to `apps/web/.env.local` to configure contract addresses
once they are deployed. Never commit real keys — see `docs/SECURITY.md`.

## Design system

Dark navy background, cyan + electric blue accents, glassmorphism, clean
typography (Inter), mobile-first. Design tokens live in a single source of
truth: `packages/config/tailwind/preset.js`, consumed by the app's Tailwind
config. See `docs/ARCHITECTURE.md` for the token table.

## Contracts (implemented)

1. `AgentGate` — Agent ID ownership verification; mainnet pins the official
   Agent ID contract, testnet/local accept the mock.
2. `QuestManager` — quest lifecycle + validated completions: CheckIn
   (explicit self-check-in), OnChain (validator contract), Attested
   (EIP-712 verifier attestation).
3. `Reputation` — points from validated events only; no admin score function.
4. `Achievement` — soulbound badges, issuer = QuestManager only.

Official Agent ID contract (BSC mainnet): `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`.
Local/testnet uses `MockAgentId` — the official contract is not on testnet.

## Docs

- [Architecture](docs/ARCHITECTURE.md) — system design, data flow, trust assumptions
- [Security](docs/SECURITY.md) — threat model, layered defense, red lines
- [Deployment](docs/DEPLOYMENT.md) — local → testnet staging → mainnet target
- [Deployment Plan](docs/DEPLOYMENT_PLAN.md) — deployment script, role wiring, trust assumptions
- [Quest Validation Design](docs/QUEST_VALIDATION_DESIGN.md) — CheckIn / OnChain / Attested
- [Remediation Report](docs/REMEDIATION_REPORT.md) — fixes for the 2 user-found design issues
- [New Threat Model](docs/NEW_THREAT_MODEL.md) — threats after the remediation
- [Regression Results](docs/REGRESSION_RESULTS.md) — test evidence vs the 120-test baseline
- [User Guide](docs/USER_GUIDE.md) — how to use AGENTHUB

## Security commitments (short version)

Non-custodial. No seed phrases, private keys, API secrets, or pairing codes —
ever. No web QR login, no stored login sessions, no hidden transfers, no
unlimited approvals. Reputation only grows through validated quest completions.
