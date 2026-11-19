import { http, createConfig } from 'wagmi';
import { bsc, bscTestnet } from 'viem/chains';
import { injected } from 'wagmi/connectors';
import { env } from './env';

// Phase 1: injected wallet only (Binance Wallet / MetaMask / any EVM wallet).
// WalletConnect support is a Phase 2 addition (needs a project id).
//
// The default chain follows the validated NEXT_PUBLIC_CHAIN_ID, and
// importing ./env runs the chain <-> Agent ID consistency check (M5) at
// startup: a misconfigured build fails loudly here instead of silently
// connecting to the wrong network.
export const wagmiConfig = createConfig({
  chains: env.NEXT_PUBLIC_CHAIN_ID === 56 ? [bsc, bscTestnet] : [bscTestnet, bsc],
  connectors: [injected()],
  transports: {
    [bscTestnet.id]: http(),
    [bsc.id]: http(),
  },
  ssr: true,
});
