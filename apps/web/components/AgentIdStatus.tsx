'use client';

import { useAgentId } from '@/hooks/useAgentId';
import { formatAddress } from '@/lib/utils';

// Shows the live on-chain Agent ID check result. Nothing here is faked:
// "not configured" means the address env var is empty (Phase 1),
// "checking" means an RPC read is in flight.
export function AgentIdStatus() {
  const { isConnected, isHolder, isLoading, configured, agentIdAddress } = useAgentId();

  if (!isConnected) {
    return (
      <p className="text-sm text-ink-400">Connect your wallet to check your Agent ID status.</p>
    );
  }
  if (!configured) {
    return (
      <p className="text-sm text-ink-400">
        Agent ID contract address is not configured yet (Phase 1 — set NEXT_PUBLIC_AGENT_ID_ADDRESS
        after the testnet deploy).
      </p>
    );
  }
  if (isLoading || isHolder === null) {
    return <p className="text-sm text-ink-400">Checking Agent ID on-chain…</p>;
  }
  return (
    <p className="text-sm">
      {isHolder ? (
        <span className="font-medium text-agent-300">
          Agent ID verified — you hold an Agent ID.
        </span>
      ) : (
        <span className="font-medium text-amber-300">
          No Agent ID found on this wallet (checked {formatAddress(agentIdAddress ?? '')}).
        </span>
      )}
    </p>
  );
}
