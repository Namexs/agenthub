import { http, createConfig } from 'wagmi';
import { anvil, bsc, bscTestnet } from 'viem/chains';
import type { Chain } from 'viem';
import { injected } from 'wagmi/connectors';
import { env } from './env';

// Phase 7: injected wallet only (Binance Wallet / MetaMask / any EVM wallet).
// WalletConnect support is a later addition (needs a project id).
//
// The default chain follows the validated NEXT_PUBLIC_CHAIN_ID, and
// importing ./env runs the chain <-> Agent ID consistency check (M5) at
// startup: a misconfigured build fails loudly here instead of silently
// connecting to the wrong network. Anvil (31337) is the local
// integration-test chain: the frontend is tested against a local
// deployment (see FRONTEND_INTEGRATION_REPORT.md) before any testnet use.
const chains: readonly [Chain, ...Chain[]] =
  env.NEXT_PUBLIC_CHAIN_ID === 56
    ? [bsc, bscTestnet]
    : env.NEXT_PUBLIC_CHAIN_ID === 31337
      ? [anvil, bscTestnet, bsc]
      : [bscTestnet, bsc];

export const wagmiConfig = createConfig({
  chains,
  connectors: [injected()],
  transports: {
    [bscTestnet.id]: http(),
    [bsc.id]: http(),
    [anvil.id]: http('http://127.0.0.1:8545'),
  },
  ssr: true,
});
