'use client';

import { useAccount, useSwitchChain } from 'wagmi';
import { env } from '@/lib/env';
import { chainName } from '@/lib/chains';

// Wrong-network guard (Phase 7). The app targets ONE chain
// (NEXT_PUBLIC_CHAIN_ID); a wallet connected to any other chain sees a
// clear banner with a one-click switch — reads and writes are disabled
// until the chain matches, so the UI can never show another chain's data
// as if it were this chain's.

export function useChainGuard() {
  const { chainId, isConnected } = useAccount();
  const { switchChain, isPending: isSwitching } = useSwitchChain();
  const expectedChainId = env.NEXT_PUBLIC_CHAIN_ID;

  const isSupported = !isConnected || chainId === expectedChainId;

  return {
    chainId,
    isConnected,
    expectedChainId,
    expectedChainName: chainName(expectedChainId),
    currentChainName: chainId === undefined ? null : chainName(chainId),
    isSupported,
    isSwitching,
    switchToExpected: () => switchChain({ chainId: expectedChainId }),
  };
}
