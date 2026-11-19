import { describe, it, expect } from 'vitest';
import { bsc, bscTestnet } from 'viem/chains';
import { supportedChains, chainName } from './chains';

// PRE-TESTNET CLEANUP (item 3, closes M4): first unit tests for
// @agenthub/web chain helpers.

describe('supportedChains', () => {
  it('supports BSC testnet and BSC mainnet (testnet first)', () => {
    expect(supportedChains).toEqual([bscTestnet, bsc]);
    expect(supportedChains.map((c) => c.id)).toEqual([97, 56]);
  });
});

describe('chainName', () => {
  it('names the known chains', () => {
    expect(chainName(56)).toBe('BNB Smart Chain');
    expect(chainName(97)).toBe('BSC Testnet');
    expect(chainName(31337)).toBe('Local Anvil');
  });

  it('falls back to "Chain <id>" for unknown chains', () => {
    expect(chainName(1)).toBe('Chain 1');
    expect(chainName(137)).toBe('Chain 137');
  });
});
