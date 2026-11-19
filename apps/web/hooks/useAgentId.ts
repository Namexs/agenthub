'use client';

import { useAccount, useReadContract } from 'wagmi';
import { AGENT_GATE_ABI, AGENT_ID_ABI, contractAddresses } from '@/lib/contracts';

/**
 * Agent ID holder check (Phase 7): reads AgentGate.isAgentHolder — the
 * same check the contracts enforce on every completion — instead of
 * reading the Agent ID contract directly. Falls back to a direct
 * balanceOf read when the gate is not deployed yet but the Agent ID
 * address is configured.
 *
 * Returns `isHolder: null` while the check cannot run (wallet not
 * connected, or neither address configured).
 */
export function useAgentId() {
  const { address, isConnected } = useAccount();
  const gateAddress = contractAddresses.agentGate;
  const agentIdAddress = contractAddresses.agentId;

  const { data: gateResult, isLoading: gateLoading } = useReadContract({
    address: gateAddress,
    abi: AGENT_GATE_ABI,
    functionName: 'isAgentHolder',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(isConnected && address && gateAddress) },
  });

  const { data: balance, isLoading: balanceLoading } = useReadContract({
    address: agentIdAddress,
    abi: AGENT_ID_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(isConnected && address && agentIdAddress && !gateAddress) },
  });

  const configured = Boolean(gateAddress ?? agentIdAddress);
  const isLoading = gateAddress ? gateLoading : balanceLoading;
  const isHolder =
    !configured || !isConnected
      ? null
      : gateAddress
        ? gateResult === undefined
          ? null
          : gateResult
        : balance === undefined
          ? null
          : balance > 0n;

  return {
    address,
    isConnected,
    isHolder,
    isLoading,
    configured,
    /** Which contract answered the check (for the UI to say honestly). */
    source: gateAddress ? ('gate' as const) : ('agentId' as const),
    agentIdAddress,
    gateAddress,
  };
}
