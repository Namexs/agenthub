# AGENTHUB — Your Agent ID. Your Onchain Reputation.

Activity and reputation platform for Binance Agent ID holders, built for the
[Binance Wallet Agent ID Hackathon](https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf)
(total rewards 60,000 USDC).

AGENTHUB combines a quest marketplace, on-chain reputation, soulbound
(non-transferable) achievement badges, and a transparent leaderboard — all
gated by real Agent ID ownership on BNB Chain.

> **Status: Phase 1 — Repository Foundation.** Scaffolding, tooling,
> contract interfaces, and documentation are in place. Contract
> implementations and the testnet deployment land in Phase 2.
> **Nothing is deployed yet, and nothing has been submitted to the hackathon.**

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
│   ├── contracts/            Foundry: interfaces + MockAgentId + tests
│   │   └── src/interfaces/   IAgentGate, IQuestManager, IReputation, IAchievement
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

## Contract build order (Phase 2)

1. `AgentGate` — Agent ID ownership verification
2. `QuestManager` — quest lifecycle + validated completions
3. `Reputation` — points from validated events only
4. `Achievement` — soulbound badges

Official Agent ID contract (BSC mainnet): `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`.
Local/testnet uses `MockAgentId` — the official contract is not on testnet.

## Docs

- [Architecture](docs/ARCHITECTURE.md) — system design, data flow, trust assumptions
- [Security](docs/SECURITY.md) — threat model, layered defense, red lines
- [Deployment](docs/DEPLOYMENT.md) — local → testnet staging → mainnet target
- [User Guide](docs/USER_GUIDE.md) — how to use AGENTHUB

## Security commitments (short version)

Non-custodial. No seed phrases, private keys, API secrets, or pairing codes —
ever. No web QR login, no stored login sessions, no hidden transfers, no
unlimited approvals. Reputation only grows through validated quest completions.
