'use client';

import { useMemo, useState } from 'react';
import { contractAddresses } from '@/lib/contracts';
import { EVENT_SIGNATURES, aggregateLeaderboard } from '@/lib/events';
import { useContractLogs } from './useContractLogs';

// Leaderboard from on-chain events (Phase 7). Points from PointsAdded,
// quest counts from QuestCompleted, aggregated + deduplicated by
// aggregateLeaderboard. Paginated client-side (10 per page). The "last
// updated" time is the last successful log fetch — the ranking is a
// snapshot of on-chain events, never a static list.

export const LEADERBOARD_PAGE_SIZE = 10;

export function useLeaderboard() {
  const questManager = contractAddresses.questManager;
  const reputation = contractAddresses.reputation;
  const deployed = Boolean(questManager && reputation);
  const [page, setPage] = useState(1);

  const {
    logs: completedLogs,
    isLoading: completedLoading,
    error: completedError,
    updatedAt: completedUpdatedAt,
    refetch: refetchCompleted,
  } = useContractLogs({
    address: questManager,
    event: EVENT_SIGNATURES.questCompleted,
    enabled: deployed,
  });

  const {
    logs: pointsLogs,
    isLoading: pointsLoading,
    error: pointsError,
    updatedAt: pointsUpdatedAt,
    refetch: refetchPoints,
  } = useContractLogs({
    address: reputation,
    event: EVENT_SIGNATURES.pointsAdded,
    enabled: deployed,
  });

  const entries = useMemo(
    () => aggregateLeaderboard(completedLogs ?? [], pointsLogs ?? []),
    [completedLogs, pointsLogs],
  );

  const totalPages = Math.max(1, Math.ceil(entries.length / LEADERBOARD_PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const pageEntries = entries.slice(
    (currentPage - 1) * LEADERBOARD_PAGE_SIZE,
    currentPage * LEADERBOARD_PAGE_SIZE,
  );

  const updatedAt =
    completedUpdatedAt === null || pointsUpdatedAt === null
      ? null
      : Math.min(completedUpdatedAt, pointsUpdatedAt);

  return {
    entries: pageEntries,
    totalEntries: entries.length,
    page: currentPage,
    totalPages,
    setPage,
    deployed,
    isLoading: completedLoading || pointsLoading,
    error: completedError ?? pointsError,
    updatedAt,
    refetch: () => {
      refetchCompleted();
      refetchPoints();
    },
  };
}
