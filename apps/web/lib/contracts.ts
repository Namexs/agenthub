import { env } from './env';
import type { Address } from 'viem';

// Minimal ABIs — only the read functions the Phase 1 UI needs.
// Full ABIs are generated from the Foundry build in Phase 2 (forge build
// output) and replace these stubs.

export const AGENT_ID_ABI = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export const AGENT_GATE_ABI = [
  {
    type: 'function',
    name: 'isAgentHolder',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'agentIdContract',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
] as const;

export const contractAddresses = {
  agentId: (env.NEXT_PUBLIC_AGENT_ID_ADDRESS ?? undefined) as Address | undefined,
  agentGate: (env.NEXT_PUBLIC_AGENT_GATE_ADDRESS ?? undefined) as Address | undefined,
  questManager: (env.NEXT_PUBLIC_QUEST_MANAGER_ADDRESS ?? undefined) as Address | undefined,
  reputation: (env.NEXT_PUBLIC_REPUTATION_ADDRESS ?? undefined) as Address | undefined,
  achievement: (env.NEXT_PUBLIC_ACHIEVEMENT_ADDRESS ?? undefined) as Address | undefined,
} as const;
