'use client';

import { useMemo } from 'react';
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { QUEST_MANAGER_ABI, contractAddresses } from '@/lib/contracts';
import { mapQuest, type QuestState, type RawQuest } from '@/lib/quests';
import type { Quest } from '@agenthub/shared';

// On-chain quest list (Phase 7). Reads questCount, then getQuest for
// every id (multicall), then — for the connected wallet — hasCompleted
// and nextCompletionAt per quest (multicall). While the contracts are
// not deployed, the hook reports deployed: false and the page shows the
// static launch catalogue with an honest label.

export interface QuestWithState extends Quest {
  state: QuestState;
}

export function useQuests() {
  const { address, isConnected } = useAccount();
  const questManager = contractAddresses.questManager;
  const deployed = Boolean(questManager);

  const {
    data: count,
    isLoading: countLoading,
    error: countError,
  } = useReadContract({
    address: questManager,
    abi: QUEST_MANAGER_ABI,
    functionName: 'questCount',
    query: { enabled: deployed },
  });

  const questIds = useMemo(() => {
    const n = count === undefined ? 0 : Number(count);
    return Array.from({ length: n }, (_, i) => i + 1);
  }, [count]);

  const {
    data: questsRaw,
    isLoading: questsLoading,
    error: questsError,
  } = useReadContracts({
    contracts: questIds.map((id) => ({
      address: questManager as `0x${string}`,
      abi: QUEST_MANAGER_ABI,
      functionName: 'getQuest',
      args: [BigInt(id)],
    })),
    query: { enabled: deployed && questIds.length > 0 },
  });

  const { data: stateRaw, isLoading: stateLoading } = useReadContracts({
    contracts: questIds.flatMap((id) => [
      {
        address: questManager as `0x${string}`,
        abi: QUEST_MANAGER_ABI,
        functionName: 'hasCompleted',
        args: [address as `0x${string}`, BigInt(id)],
      },
      {
        address: questManager as `0x${string}`,
        abi: QUEST_MANAGER_ABI,
        functionName: 'nextCompletionAt',
        args: [address as `0x${string}`, BigInt(id)],
      },
    ]),
    query: { enabled: deployed && isConnected && Boolean(address) && questIds.length > 0 },
  });

  const quests: QuestWithState[] = useMemo(() => {
    if (!questsRaw) return [];
    return questsRaw
      .map((entry, i) => {
        if (entry.status !== 'success' || !entry.result) return null;
        const quest = mapQuest(entry.result as unknown as RawQuest);
        const completedEntry = stateRaw?.[i * 2];
        const nextEntry = stateRaw?.[i * 2 + 1];
        const state: QuestState = {
          completed: completedEntry?.status === 'success' ? Boolean(completedEntry.result) : false,
          nextCompletionAt:
            nextEntry?.status === 'success' ? Number(nextEntry.result as bigint) : 0,
        };
        return { ...quest, state };
      })
      .filter((q): q is QuestWithState => q !== null);
  }, [questsRaw, stateRaw]);

  const error = countError ?? questsError;
  return {
    quests,
    deployed,
    questCount: questIds.length,
    isLoading: countLoading || questsLoading || stateLoading,
    error: error ? (error as Error).message : null,
  };
}
