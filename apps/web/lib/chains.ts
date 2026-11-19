import { anvil, bsc, bscTestnet } from 'viem/chains';
import { CHAINS } from '@agenthub/shared';

// Mainnet (56) is the competition target; testnet (97) is staging.
// Local Anvil (31337) is the integration-test chain (Phase 7): the
// frontend is tested against a local deployment before any testnet use.
export const supportedChains = [bscTestnet, bsc, anvil] as const;

export function chainName(chainId: number): string {
  switch (chainId) {
    case CHAINS.BSC_MAINNET:
      return 'BNB Smart Chain';
    case CHAINS.BSC_TESTNET:
      return 'BSC Testnet';
    case CHAINS.LOCAL_ANVIL:
      return 'Local Anvil';
    default:
      return `Chain ${chainId}`;
  }
}
