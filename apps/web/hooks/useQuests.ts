'use client';

import { LAUNCH_QUESTS } from '@/lib/quests';
import { contractAddresses } from '@/lib/contracts';

// Phase 1: static launch catalogue. Phase 2 replaces this with on-chain reads
// from QuestManager (getQuest / questCount) + completion state per wallet.
export function useQuests() {
  const deployed = Boolean(contractAddresses.questManager);
  return { quests: LAUNCH_QUESTS, deployed, isLoading: false };
}
