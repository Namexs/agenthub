import { describe, it, expect } from 'vitest';
import {
  CHAINS,
  AGENT_ID_MAINNET_ADDRESS,
  AGENT_ID_TESTNET_ADDRESS_PLACEHOLDER,
  EXPLORERS,
  REPUTATION_LEVEL_THRESHOLDS,
  DAILY_CHECKIN_COOLDOWN_SECONDS,
} from './constants';
import { QuestType } from './types';

// PRE-TESTNET CLEANUP (item 3, closes M4): first unit tests for
// @agenthub/shared. These pin the shared constants that the web app and
// the contracts must agree on — a drift here (wrong chain id, wrong
// official Agent ID address) would silently point the UI at the wrong
// network or the wrong identity contract.

describe('CHAINS', () => {
  it('uses the BSC chain ids', () => {
    expect(CHAINS.BSC_MAINNET).toBe(56);
    expect(CHAINS.BSC_TESTNET).toBe(97);
    expect(CHAINS.LOCAL_ANVIL).toBe(31337);
  });
});

describe('AGENT_ID_MAINNET_ADDRESS', () => {
  it('is the official Binance Agent ID contract (EIP-55 checksummed)', () => {
    expect(AGENT_ID_MAINNET_ADDRESS).toBe('0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F');
  });

  it('is a well-formed EVM address', () => {
    expect(AGENT_ID_MAINNET_ADDRESS).toMatch(/^0x[a-fA-F0-9]{40}$/);
  });
});

describe('AGENT_ID_TESTNET_ADDRESS_PLACEHOLDER', () => {
  it('is the zero address (never a real contract)', () => {
    expect(AGENT_ID_TESTNET_ADDRESS_PLACEHOLDER).toBe('0x0000000000000000000000000000000000000000');
  });
});

describe('EXPLORERS', () => {
  it('points at the right BscScan for each chain', () => {
    expect(EXPLORERS[56]).toBe('https://bscscan.com');
    expect(EXPLORERS[97]).toBe('https://testnet.bscscan.com');
    expect(EXPLORERS[31337]).toBe('');
  });
});

describe('REPUTATION_LEVEL_THRESHOLDS', () => {
  it('has 5 levels starting at 0 and strictly increasing', () => {
    expect(REPUTATION_LEVEL_THRESHOLDS).toEqual([0, 100, 300, 700, 1500]);
    expect(REPUTATION_LEVEL_THRESHOLDS).toHaveLength(5);
    let prev = -1;
    for (const t of REPUTATION_LEVEL_THRESHOLDS) {
      expect(t).toBeGreaterThan(prev);
      prev = t;
    }
  });
});

describe('DAILY_CHECKIN_COOLDOWN_SECONDS', () => {
  it('is exactly one day', () => {
    expect(DAILY_CHECKIN_COOLDOWN_SECONDS).toBe(24 * 60 * 60);
  });
});

describe('QuestType', () => {
  it('covers the four on-chain quest types', () => {
    expect(QuestType.DailyCheckIn).toBe('daily-checkin');
    expect(QuestType.OneTime).toBe('one-time');
    expect(QuestType.Weekly).toBe('weekly');
    expect(QuestType.Community).toBe('community');
  });
});
