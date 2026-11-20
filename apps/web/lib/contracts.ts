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

// Minimal QuestManager read ABI (Phase 8). The full QUEST_MANAGER_ABI
// (99 entries) makes wagmi's useReadContracts type inference exceed
// TypeScript's instantiation depth (TS2589, useQuests.ts) — the four
// read functions below are all useQuests needs. Entries are copied
// VERBATIM from the committed QUEST_MANAGER_ABI; abi-parity.test.ts
// asserts each entry deep-equals its full-ABI counterpart, so drift
// fails CI. Regenerate this subset by hand only when one of these four
// functions changes (update the test expectation with it).
export const QUEST_MANAGER_READ_ABI = [
  {
    type: 'function',
    name: 'questCount',
    inputs: [],
    outputs: [{ name: '', type: 'uint256', internalType: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getQuest',
    inputs: [{ name: 'questId', type: 'uint256', internalType: 'uint256' }],
    outputs: [
      {
        name: 'quest',
        type: 'tuple',
        internalType: 'struct IQuestManager.Quest',
        components: [
          { name: 'id', type: 'uint256', internalType: 'uint256' },
          { name: 'creator', type: 'address', internalType: 'address' },
          { name: 'title', type: 'string', internalType: 'string' },
          { name: 'description', type: 'string', internalType: 'string' },
          { name: 'questType', type: 'uint8', internalType: 'enum IQuestManager.QuestType' },
          {
            name: 'validationKind',
            type: 'uint8',
            internalType: 'enum IQuestManager.ValidationKind',
          },
          { name: 'validator', type: 'address', internalType: 'address' },
          { name: 'rewardPoints', type: 'uint256', internalType: 'uint256' },
          { name: 'badgeId', type: 'uint256', internalType: 'uint256' },
          { name: 'startTime', type: 'uint256', internalType: 'uint256' },
          { name: 'endTime', type: 'uint256', internalType: 'uint256' },
          { name: 'maxCompletions', type: 'uint256', internalType: 'uint256' },
          { name: 'completions', type: 'uint256', internalType: 'uint256' },
          { name: 'active', type: 'bool', internalType: 'bool' },
          { name: 'attestationThreshold', type: 'uint8', internalType: 'uint8' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'hasCompleted',
    inputs: [
      { name: 'account', type: 'address', internalType: 'address' },
      { name: 'questId', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool', internalType: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'nextCompletionAt',
    inputs: [
      { name: 'account', type: 'address', internalType: 'address' },
      { name: 'questId', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [{ name: 'readyAt', type: 'uint256', internalType: 'uint256' }],
    stateMutability: 'view',
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
