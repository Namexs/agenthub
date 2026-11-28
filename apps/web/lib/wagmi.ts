import { http, createConfig, fallback } from 'wagmi';
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
    // The BSC dataseed rejects ALL eth_getLogs calls (verified live
    // 2026-11-24), which broke the leaderboard; publicnode serves them
    // (max 50,000 blocks per call, see useContractLogs) but is now
    // Cloudflare-blocked and silently drops old logs (ALICE's Nov 23
    // events missing, verified 2026-11-28). When the keyed NodeReal
    // RPC is configured it goes FIRST: it serves getLogs over the
    // full 50,000-block chunks. An RPC only reads chain data and
    // relays transactions — it never sees keys; signing stays in the
    // user's own wallet.
    [bscTestnet.id]: fallback([
      ...(env.NEXT_PUBLIC_BSC_TESTNET_RPC_URL
        ? [http(env.NEXT_PUBLIC_BSC_TESTNET_RPC_URL)]
        : []),
      http(),
      http('https://bsc-testnet-rpc.publicnode.com'),
    ]),
    [bsc.id]: fallback([http(), http('https://bsc-rpc.publicnode.com')]),
    [anvil.id]: http('http://127.0.0.1:8545'),
  },
  ssr: true,
});
