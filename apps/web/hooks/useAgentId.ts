'use client';

import { useAccount, useReadContract } from 'wagmi';
import { AGENT_ID_ABI, contractAddresses } from '@/lib/contracts';

/**
 * Reads Agent ID ownership directly from the Agent ID contract
 * (balanceOf > 0). No backend, no session, no signature — pure on-chain read.
 * Returns `isHolder: null` while the check cannot run (wallet not connected
 * or Agent ID address not configured yet).
 */
export function useAgentId() {
  const { address, isConnected } = useAccount();
  const agentIdAddress = contractAddresses.agentId;

  const { data: balance, isLoading } = useReadContract({
    address: agentIdAddress,
    abi: AGENT_ID_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(isConnected && address && agentIdAddress) },
  });

  const configured = Boolean(agentIdAddress);
  const isHolder = configured && isConnected && balance !== undefined ? balance > 0n : null;

  return { address, isConnected, isHolder, isLoading, configured, agentIdAddress };
}
