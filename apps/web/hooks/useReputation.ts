'use client';

import { useAccount } from 'wagmi';
import { contractAddresses } from '@/lib/contracts';

// Phase 1 stub: the Reputation contract is not deployed yet, so there is no
// on-chain data to read. Phase 2 wires this hook to useReadContract against
// IReputation.points / level. The shape is final — only the data source changes.
export function useReputation() {
  const { address, isConnected } = useAccount();
  const deployed = Boolean(contractAddresses.reputation);
  return {
    address,
    isConnected,
    deployed,
    points: null as number | null,
    level: null as number | null,
    isLoading: false,
  };
}
