import { env } from './env';
import type { Address } from 'viem';
import { AGENT_GATE_ABI } from './abis/AgentGate';
import { QUEST_MANAGER_ABI } from './abis/QuestManager';
import { REPUTATION_ABI } from './abis/Reputation';
import { ACHIEVEMENT_ABI } from './abis/Achievement';

// ABIs exported from the Foundry build (Phase 7) — committed TypeScript
// modules, see packages/contracts/script/export-abis.mjs. Regenerate
// after any contract change: `node packages/contracts/script/export-abis.mjs`
// (from the repo root, after `forge build`).
//
// The Agent ID contract is an EXTERNAL ERC-721 (Binance/SPACE ID), not
// one of ours — the frontend uses a minimal balanceOf ABI for it.

export { AGENT_GATE_ABI, QUEST_MANAGER_ABI, REPUTATION_ABI, ACHIEVEMENT_ABI };

export const AGENT_ID_ABI = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export const contractAddresses = {
  agentId: (env.NEXT_PUBLIC_AGENT_ID_ADDRESS ?? undefined) as Address | undefined,
  agentGate: (env.NEXT_PUBLIC_AGENT_GATE_ADDRESS ?? undefined) as Address | undefined,
  questManager: (env.NEXT_PUBLIC_QUEST_MANAGER_ADDRESS ?? undefined) as Address | undefined,
  reputation: (env.NEXT_PUBLIC_REPUTATION_ADDRESS ?? undefined) as Address | undefined,
  achievement: (env.NEXT_PUBLIC_ACHIEVEMENT_ADDRESS ?? undefined) as Address | undefined,
} as const;

/** Block the contracts were deployed at (event queries start here). */
export const deployBlock = env.NEXT_PUBLIC_DEPLOY_BLOCK;
