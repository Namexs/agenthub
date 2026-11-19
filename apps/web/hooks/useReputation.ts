'use client';

import { useMemo } from 'react';
import { useAccount, useReadContract } from 'wagmi';
import { REPUTATION_ABI, contractAddresses } from '@/lib/contracts';
import { EVENT_SIGNATURES, buildTxHistory } from '@/lib/events';
import { useContractLogs } from './useContractLogs';

// On-chain reputation (Phase 7). Points + level come from direct reads;
// the history comes from PointsAdded events for the connected account.
// Points only ever increase through validated completions — there is no
// admin score function, so this hook has no write path by design.

export function useReputation() {
  const { address, isConnected } = useAccount();
  const reputation = contractAddresses.reputation;
  const deployed = Boolean(reputation);

  const { data: points, isLoading: pointsLoading } = useReadContract({
    address: reputation,
    abi: REPUTATION_ABI,
    functionName: 'points',
    args: address ? [address] : undefined,
    query: { enabled: deployed && isConnected && Boolean(address) },
  });

  const { data: level, isLoading: levelLoading } = useReadContract({
    address: reputation,
    abi: REPUTATION_ABI,
    functionName: 'level',
    args: address ? [address] : undefined,
    query: { enabled: deployed && isConnected && Boolean(address) },
  });

  const { data: totalEvents, isLoading: eventsLoading } = useReadContract({
    address: reputation,
    abi: REPUTATION_ABI,
    functionName: 'totalEvents',
    args: address ? [address] : undefined,
    query: { enabled: deployed && isConnected && Boolean(address) },
  });

  const {
    logs: pointsLogs,
    isLoading: historyLoading,
    error: historyError,
  } = useContractLogs({
    address: reputation,
    event: EVENT_SIGNATURES.pointsAdded,
    filter: address ? { account: address } : undefined,
    enabled: deployed && isConnected && Boolean(address),
  });

  const history = useMemo(
    () =>
      buildTxHistory({
        questCompleted: [],
        pointsAdded: pointsLogs ?? [],
        badgeIssued: [],
        attestationUsed: [],
      }),
    [pointsLogs],
  );

  return {
    address,
    isConnected,
    deployed,
    points: points === undefined ? null : Number(points),
    level: level === undefined ? null : Number(level),
    totalEvents: totalEvents === undefined ? null : Number(totalEvents),
    history,
    isLoading: pointsLoading || levelLoading || eventsLoading || historyLoading,
    error: historyError,
  };
}
