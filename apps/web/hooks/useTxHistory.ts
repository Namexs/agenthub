'use client';

import { useMemo } from 'react';
import { useAccount } from 'wagmi';
import { contractAddresses } from '@/lib/contracts';
import { EVENT_SIGNATURES, buildTxHistory } from '@/lib/events';
import { useContractLogs } from './useContractLogs';

// Transaction history (Phase 7). Merges the connected account's
// QuestCompleted + PointsAdded + BadgeIssued + AttestationUsed logs into
// one list, newest first. Every entry keeps its tx hash for the BscScan
// link. Completion, reputation, and badge events from the SAME
// transaction appear as separate rows (they are separate logs) —
// deduplicated by (txHash, logIndex) inside buildTxHistory.

export function useTxHistory() {
  const { address, isConnected } = useAccount();
  const questManager = contractAddresses.questManager;
  const reputation = contractAddresses.reputation;
  const achievement = contractAddresses.achievement;
  const deployed = Boolean(questManager && reputation && achievement);
  const filter = address ? { account: address } : undefined;
  const enabled = deployed && isConnected && Boolean(address);

  const {
    logs: completedLogs,
    isLoading: cLoading,
    error: cError,
  } = useContractLogs({
    address: questManager,
    event: EVENT_SIGNATURES.questCompleted,
    filter,
    enabled,
  });
  const {
    logs: pointsLogs,
    isLoading: pLoading,
    error: pError,
  } = useContractLogs({
    address: reputation,
    event: EVENT_SIGNATURES.pointsAdded,
    filter,
    enabled,
  });
  const {
    logs: badgeLogs,
    isLoading: bLoading,
    error: bError,
  } = useContractLogs({
    address: achievement,
    event: EVENT_SIGNATURES.badgeIssued,
    filter,
    enabled,
  });
  const {
    logs: attestationLogs,
    isLoading: aLoading,
    error: aError,
  } = useContractLogs({
    address: questManager,
    event: EVENT_SIGNATURES.attestationUsed,
    filter,
    enabled,
  });

  const entries = useMemo(
    () =>
      buildTxHistory({
        questCompleted: completedLogs ?? [],
        pointsAdded: pointsLogs ?? [],
        badgeIssued: badgeLogs ?? [],
        attestationUsed: attestationLogs ?? [],
      }),
    [completedLogs, pointsLogs, badgeLogs, attestationLogs],
  );

  return {
    entries,
    deployed,
    isLoading: cLoading || pLoading || bLoading || aLoading,
    error: cError ?? pError ?? bError ?? aError,
  };
}
