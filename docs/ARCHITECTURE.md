# AGENTHUB — Architecture

## 1. Overview

AGENTHUB is an Agent ID-native activity and reputation platform on BNB Chain.
It answers one question for Agent ID holders: _what have I done, and can
anyone verify it?_ Every answer is an on-chain record.

```
                    ┌─────────────────────────┐
                    │  Binance Agent ID (ERC-721 soulbound)
                    │  0x60b9…022F (BSC mainnet)
                    └────────────┬────────────┘
                                 │ balanceOf(account) > 0
                    ┌────────────▼────────────┐
                    │  1. AgentGate           │  identity verification
                    └────────────┬────────────┘
                                 │ only Agent ID holders
                    ┌────────────▼────────────┐
                    │  2. QuestManager        │  quests + validated completions
                    └──────┬──────────┬───────┘
                           │          │
              ┌────────────▼──┐  ┌────▼────────────┐
              │ 3. Reputation │  │ 4. Achievement  │
              │ points/levels │  │ soulbound badges│
              └───────────────┘  └─────────────────┘
                           │          │
                    ┌──────▼──────────▼───────┐
                    │  Next.js frontend       │
                    │  reads events + state,  │
                    │  never holds custody    │
                    └─────────────────────────┘
```

## 2. Components

| Component             | Responsibility                                                                                                                                                                           |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AgentGate`           | Single source of truth for "does this address hold an Agent ID". Reads `balanceOf` on the trusted Agent ID contract and validates the expected chainId. All gated actions go through it. |
| `QuestManager`        | Quest creation (role-gated), completion recording, cooldowns, duplicate prevention. Calls Reputation + Achievement on validated completion.                                              |
| `Reputation`          | Points ledger. Points increase ONLY via authorized callers (QuestManager). No admin score function exists by design. Full event history is public.                                       |
| `Achievement`         | ERC-721 soulbound badges. Transfers and approvals revert. Issued only by authorized callers after validated completion.                                                                  |
| `MockAgentId`         | Local/testnet stand-in for the official Agent ID contract (which is not deployed on testnet). Mirrors soulbound behaviour. **Never deployed to mainnet.**                                |
| Frontend (`apps/web`) | Next.js App Router. Reads chain state via wagmi/viem, submits user-confirmed transactions, renders reputation/leaderboard from on-chain events. No backend, no session storage.          |
| `packages/shared`     | Types + constants shared by frontend and (later) indexers.                                                                                                                               |
| `packages/config`     | Shared TypeScript, ESLint, and Tailwind preset (design tokens).                                                                                                                          |

## 3. Build order (Phase 2)

Contracts are implemented and tested in dependency order:

1. **AgentGate** — everything else depends on identity verification.
2. **QuestManager** — the interaction engine; depends on AgentGate.
3. **Reputation** — the points ledger; written to only by QuestManager.
4. **Achievement** — badges; issued only by QuestManager.

Each step ships with unit + fuzz + invariant tests before the next begins.

## 4. Data flow

1. User connects an EVM wallet (injected connector; no QR login, no server session).
2. Frontend reads `balanceOf(user)` on the Agent ID contract (or `isAgentHolder`
   on AgentGate once deployed) and shows holder status.
3. User completes a quest → one user-confirmed transaction to
   `QuestManager.completeQuest(questId)`.
4. QuestManager validates (holder, active window, cooldown, not already
   completed) then calls `Reputation.addPoints` and, when applicable,
   `Achievement.issue` — all inside the same transaction.
5. Frontend reads `QuestCompleted` / `PointsAdded` / `BadgeIssued` events and
   contract state to render dashboard, profile, leaderboard, and history.

## 5. Environments

| Environment             | Chain                | Agent ID contract          | Purpose                         |
| ----------------------- | -------------------- | -------------------------- | ------------------------------- |
| Local                   | Anvil (31337)        | MockAgentId                | Development + integration tests |
| Staging                 | BSC Testnet (97)     | MockAgentId                | Public testing, hackathon demo  |
| **Production (target)** | **BSC Mainnet (56)** | **Official `0x60b9…022F`** | **Competition submission**      |

Mainnet is the competition target. Testnet exists to prove the system before
real users and real Agent IDs touch it. See `docs/DEPLOYMENT.md`.

## 6. Quality standard: provable on-chain

A feature is done only when a user can point at a transaction and say "that
happened". Concretely:

- Quest completion = `QuestCompleted` event + state change, linked on BscScan.
- Reputation change = `PointsAdded` event with the quest id that caused it.
- Badge = ERC-721 token owned by the user, verifiable via `ownerOf`/`hasBadge`.
- Leaderboard = derived from on-chain events, recomputable by anyone.

The UI never displays a state it cannot read from the chain (except clearly
labelled Phase 1 previews, which are removed in Phase 2).

## 7. Design system (theme)

Single source of truth: `packages/config/tailwind/preset.js`.

| Token                    | Value                            | Usage |
| ------------------------ | -------------------------------- | ----- |
| `navy.950` `#050816`     | Page background                  |
| `navy.900` `#0a0f24`     | Section background               |
| `navy.800` `#111c3f`     | Card background                  |
| `navy.700` `#1a2a55`     | Raised surface                   |
| `navy.600` `#24386e`     | Borders (strong)                 |
| `agent.400` `#22d3ee`    | Primary accent (cyan)            |
| `electric.500` `#3b82f6` | Secondary accent (electric blue) |
| `ink.100` `#f1f5f9`      | Primary text                     |
| `ink.400` `#94a3b8`      | Secondary text                   |

- Typography: Inter (via `next/font`), clean sans hierarchy.
- Glassmorphism: `bg-navy-800/60` + `backdrop-blur-glass` + `border-navy-600/60`
  - `shadow-glass` (see `components/GlassCard.tsx`).
- Mobile-first responsive layouts; sticky glass navbar; gradient CTAs
  (`from-agent-500 to-electric-600`) with cyan glow shadows.

## 8. Trust assumptions

- **Agent ID contract is trusted.** AgentGate trusts exactly one address per
  chain (official on mainnet, mock on testnet/local). If that address were
  wrong, gating would be wrong — hence the address is immutable at deploy time
  and documented in `docs/DEPLOYMENT.md`.
- **BNB Chain liveness.** Reads and writes assume the chain is available;
  the frontend degrades to "unavailable" states, never to invented data.
- **User's wallet is the signer.** AGENTHUB never signs for users and never
  sees private keys. A compromised wallet is outside the system's control.
- **No oracle / no backend.** All state is on-chain. There is no server that
  can lie about points or badges — but also no server to recover anything.
  On-chain mistakes are permanent; hence the test-first build order.
- **Admin roles are human-operated.** Quest creation and badge definition use
  role-gated admin functions. Production admin keys must be multisig (see
  `docs/SECURITY.md`); Phase 1 has no admin keys at all.
