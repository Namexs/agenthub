import { http, createConfig } from 'wagmi';
import { bsc, bscTestnet } from 'viem/chains';
import { injected } from 'wagmi/connectors';

// Phase 1: injected wallet only (Binance Wallet / MetaMask / any EVM wallet).
// WalletConnect support is a Phase 2 addition (needs a project id).
export const wagmiConfig = createConfig({
  chains: [bscTestnet, bsc],
  connectors: [injected()],
  transports: {
    [bscTestnet.id]: http(),
    [bsc.id]: http(),
  },
  ssr: true,
});
