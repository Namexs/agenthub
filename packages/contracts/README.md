# @agenthub/contracts

Foundry project for AGENTHUB smart contracts.

## Phase 1 status

Interfaces + architecture only. Full implementations land in Phase 2, in this
build order:

1. `AgentGate` — Agent ID ownership verification (`IAgentGate`)
2. `QuestManager` — quest lifecycle + validated completions (`IQuestManager`)
3. `Reputation` — points from validated events only (`IReputation`)
4. `Achievement` — soulbound badges (`IAchievement`)

`MockAgentId` (local/testnet only) mirrors the official Agent ID token's
soulbound behaviour so tests exercise production assumptions.

## Commands

```bash
pnpm --filter @agenthub/contracts build   # forge build
pnpm --filter @agenthub/contracts test    # forge test (unit + fuzz)
```

Production Agent ID (BSC mainnet, chainId 56):
`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
