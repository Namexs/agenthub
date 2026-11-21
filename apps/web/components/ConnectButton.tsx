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
        className="rounded-lg border border-navy-600 bg-navy-900 px-4 py-2 font-mono text-sm text-ink-200 transition-colors hover:border-ink-400"
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
      className="rounded-lg bg-agent-400 px-4 py-2 text-sm font-semibold text-navy-950 transition-colors hover:bg-agent-300 disabled:opacity-50"
    >
      {isPending ? 'Connecting…' : 'Connect Binance Wallet'}
    </button>
  );
}
