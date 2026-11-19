'use client';

import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { QUEST_MANAGER_ABI, contractAddresses } from '@/lib/contracts';

// Quest completion writes (Phase 7). Two paths, matching the contract:
// completeQuest for CheckIn/OnChain quests, completeQuestWithAttestation
// for Attested quests. The hook exposes the full transaction lifecycle —
// a submitted transaction is NOT a completed quest until the receipt
// confirms success. The UI must show pending → confirming → confirmed
// (or failed), never "done" at submit time.

export function useCompleteQuest() {
  const questManager = contractAddresses.questManager;
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const {
    isLoading: isConfirming,
    isSuccess,
    isError: receiptFailed,
  } = useWaitForTransactionReceipt({ hash });

  const complete = (questId: number) => {
    if (!questManager) return;
    writeContract({
      address: questManager,
      abi: QUEST_MANAGER_ABI,
      functionName: 'completeQuest',
      args: [BigInt(questId)],
    });
  };

  // PHASE 6 (R-010): threshold attestation — the contract takes a bytes[]
  // array (at least the quest's attestationThreshold distinct verifier
  // signatures over the same digest).
  const completeWithAttestation = (
    questId: number,
    deadline: number,
    signatures: `0x${string}`[],
  ) => {
    if (!questManager) return;
    writeContract({
      address: questManager,
      abi: QUEST_MANAGER_ABI,
      functionName: 'completeQuestWithAttestation',
      args: [BigInt(questId), BigInt(deadline), signatures],
    });
  };

  return {
    complete,
    completeWithAttestation,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    isFailed: Boolean(error) || receiptFailed,
    error: error
      ? (error as Error).message
      : receiptFailed
        ? 'Transaction reverted on-chain'
        : null,
    reset,
  };
}
