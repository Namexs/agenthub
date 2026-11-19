'use client';

import { useMemo } from 'react';
import { useAccount } from 'wagmi';
import { contractAddresses } from '@/lib/contracts';
import { EVENT_SIGNATURES } from '@/lib/events';
import { useContractLogs } from './useContractLogs';
import type { Badge } from '@agenthub/shared';

// Soulbound badges (Phase 7). The badge catalogue comes from BadgeDefined
// events (name + tokenURI live only there — the contract exposes no
// metadata getter); ownership comes from BadgeIssued events for the
// connected account. Badges are soulbound, so an issued badge is never
// transferred away — the event history IS the ownership record.
// There is deliberately NO transfer function anywhere in this app.

export interface OwnedBadge extends Badge {
  earned: boolean;
  tokenId: number | null;
}

export function useAchievements() {
  const { address, isConnected } = useAccount();
  const achievement = contractAddresses.achievement;
  const deployed = Boolean(achievement);

  const {
    logs: definedLogs,
    isLoading: catalogueLoading,
    error: catalogueError,
  } = useContractLogs({
    address: achievement,
    event: EVENT_SIGNATURES.badgeDefined,
    enabled: deployed,
  });

  const {
    logs: issuedLogs,
    isLoading: issuedLoading,
    error: issuedError,
  } = useContractLogs({
    address: achievement,
    event: EVENT_SIGNATURES.badgeIssued,
    filter: address ? { account: address } : undefined,
    enabled: deployed && isConnected && Boolean(address),
  });

  const badges: OwnedBadge[] = useMemo(() => {
    const owned = new Map<number, number>();
    for (const log of issuedLogs ?? []) {
      owned.set(Number(log.args.badgeId ?? 0), Number(log.args.tokenId ?? 0));
    }
    const catalogue = new Map<number, OwnedBadge>();
    for (const log of definedLogs ?? []) {
      const badgeId = Number(log.args.badgeId ?? 0);
      if (badgeId === 0 || catalogue.has(badgeId)) continue;
      catalogue.set(badgeId, {
        badgeId,
        name: String(log.args.name ?? `Badge #${badgeId}`),
        description: '',
        tokenURI: String(log.args.tokenURI ?? ''),
        earned: owned.has(badgeId),
        tokenId: owned.get(badgeId) ?? null,
      });
    }
    // Badges issued but never defined in the fetched logs (should not
    // happen) still show up as earned with a placeholder name.
    for (const [badgeId, tokenId] of owned) {
      if (!catalogue.has(badgeId)) {
        catalogue.set(badgeId, {
          badgeId,
          name: `Badge #${badgeId}`,
          description: '',
          tokenURI: '',
          earned: true,
          tokenId,
        });
      }
    }
    return [...catalogue.values()].sort((a, b) => a.badgeId - b.badgeId);
  }, [definedLogs, issuedLogs]);

  return {
    badges,
    deployed,
    isLoading: catalogueLoading || issuedLoading,
    error: catalogueError ?? issuedError,
  };
}
