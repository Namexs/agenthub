'use client';

import { useAccount, useConnect, useDisconnect } from 'wagmi';
import { formatAddress } from '@/lib/utils';

export function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <button
        type="button"
        onClick={() => disconnect()}
        className="rounded-pill border border-agent-400/50 bg-agent-500/10 px-4 py-2 text-sm font-medium text-agent-300 transition hover:bg-agent-500/20"
        title="Disconnect wallet"
      >
        {formatAddress(address)}
      </button>
    );
  }

  const injected = connectors[0];
  return (
    <button
      type="button"
      disabled={!injected || isPending}
      onClick={() => injected && connect({ connector: injected })}
      className="rounded-pill bg-gradient-to-r from-agent-500 to-electric-600 px-4 py-2 text-sm font-semibold text-white shadow-glow-cyan transition hover:opacity-90 disabled:opacity-50"
    >
      {isPending ? 'Connecting…' : 'Connect Binance Wallet'}
    </button>
  );
}
