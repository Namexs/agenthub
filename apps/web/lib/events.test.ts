import { describe, it, expect } from 'vitest';
import { parseAbiItem } from 'viem';
import {
  EVENT_SIGNATURES,
  aggregateLeaderboard,
  buildTxHistory,
  computeLevel,
  explorerAddressUrl,
  explorerTxUrl,
  type DecodedLog,
} from './events';

// PHASE 8: unit tests for the pure event-aggregation helpers. The
// hooks (useLeaderboard, useTxHistory, useReputation, useAchievements)
// fetch logs and hand them to these functions, so aggregation, dedup,
// ordering, and level math are all pinned here against synthetic logs.

const ALICE = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const BOB = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const CAROL = '0xcccccccccccccccccccccccccccccccccccccccc';

function log(
  tx: string,
  blockNumber: number,
  logIndex: number,
  args: Record<string, unknown>,
): DecodedLog {
  return {
    transactionHash: `0x${tx}` as `0x${string}`,
    blockNumber,
    logIndex,
    args,
  };
}

describe('computeLevel', () => {
  it('is 1-based and matches the contract thresholds [0, 100, 300, 700, 1500]', () => {
    expect(computeLevel(0)).toBe(1);
    expect(computeLevel(99)).toBe(1);
    expect(computeLevel(100)).toBe(2);
    expect(computeLevel(250)).toBe(2); // the anvil test's regression case
    expect(computeLevel(299)).toBe(2);
    expect(computeLevel(300)).toBe(3);
    expect(computeLevel(699)).toBe(3);
    expect(computeLevel(700)).toBe(4);
    expect(computeLevel(1499)).toBe(4);
    expect(computeLevel(1500)).toBe(5);
    expect(computeLevel(100_000)).toBe(5);
  });
});

describe('aggregateLeaderboard', () => {
  it('sums points and counts quests per account', () => {
    const entries = aggregateLeaderboard(
      [
        log('aa', 10, 0, { account: ALICE, questId: 1n }),
        log('ab', 11, 0, { account: ALICE, questId: 2n }),
        log('ac', 12, 0, { account: BOB, questId: 1n }),
      ],
      [
        log('aa', 10, 1, { account: ALICE, points: 50n }),
        log('ab', 11, 1, { account: ALICE, points: 100n }),
        log('ac', 12, 1, { account: BOB, points: 50n }),
      ],
    );
    expect(entries).toEqual([
      { rank: 1, address: ALICE, points: 150, level: 2, questsCompleted: 2 },
      { rank: 2, address: BOB, points: 50, level: 1, questsCompleted: 1 },
    ]);
  });

  it('deduplicates the same log delivered twice (overlapping fetches)', () => {
    const points = log('aa', 10, 1, { account: ALICE, points: 50n });
    const completed = log('aa', 10, 0, { account: ALICE, questId: 1n });
    const entries = aggregateLeaderboard([completed, completed], [points, points]);
    expect(entries).toEqual([
      { rank: 1, address: ALICE, points: 50, level: 1, questsCompleted: 1 },
    ]);
  });

  it('breaks point ties by address ascending (stable order)', () => {
    const entries = aggregateLeaderboard(
      [],
      [
        log('ac', 12, 1, { account: CAROL, points: 50n }),
        log('ab', 11, 1, { account: BOB, points: 50n }),
        log('aa', 10, 1, { account: ALICE, points: 50n }),
      ],
    );
    expect(entries.map((e) => e.address)).toEqual([ALICE, BOB, CAROL]);
    expect(entries.map((e) => e.rank)).toEqual([1, 2, 3]);
  });

  it('includes an account with only quest completions (0 points)', () => {
    const entries = aggregateLeaderboard([log('aa', 10, 0, { account: ALICE, questId: 1n })], []);
    expect(entries).toEqual([{ rank: 1, address: ALICE, points: 0, level: 1, questsCompleted: 1 }]);
  });

  it('skips logs without an account', () => {
    const entries = aggregateLeaderboard(
      [log('aa', 10, 0, { questId: 1n })],
      [log('ab', 11, 1, { points: 50n })],
    );
    expect(entries).toEqual([]);
  });

  it('returns an empty list for empty logs', () => {
    expect(aggregateLeaderboard([], [])).toEqual([]);
  });

  it('normalizes mixed-case addresses to one entry', () => {
    const entries = aggregateLeaderboard(
      [],
      [
        log('aa', 10, 1, { account: ALICE.toUpperCase(), points: 10n }),
        log('ab', 11, 1, { account: ALICE, points: 20n }),
      ],
    );
    expect(entries).toHaveLength(1);
    expect(entries[0]?.points).toBe(30);
  });
});

describe('buildTxHistory', () => {
  it('merges all four log kinds newest-first', () => {
    const entries = buildTxHistory({
      questCompleted: [log('a1', 10, 0, { questId: 1n, rewardPoints: 50n })],
      pointsAdded: [log('a1', 10, 1, { questId: 1n, points: 50n })],
      badgeIssued: [log('a1', 10, 2, { badgeId: 1n, tokenId: 7n })],
      attestationUsed: [log('a2', 9, 0, { questId: 3n, signer: BOB })],
    });
    expect(entries.map((e) => [e.kind, e.blockNumber, e.logIndex])).toEqual([
      ['badge', 10, 2],
      ['points', 10, 1],
      ['quest', 10, 0],
      ['attestation', 9, 0],
    ]);
    expect(entries[0]).toMatchObject({
      kind: 'badge',
      badgeId: 1,
      tokenId: 7,
      hash: '0xa1',
      blockNumber: 10,
      logIndex: 2,
    });
    expect(entries[3]).toMatchObject({ kind: 'attestation', questId: 3, signer: BOB });
  });

  it('deduplicates the same (txHash, logIndex) across categories', () => {
    // A log delivered under two categories must appear once, as the
    // first category that claims it.
    const dup = log('a1', 10, 0, { questId: 1n, rewardPoints: 50n, points: 50n });
    const entries = buildTxHistory({
      questCompleted: [dup],
      pointsAdded: [dup],
      badgeIssued: [],
      attestationUsed: [],
    });
    expect(entries).toHaveLength(1);
    expect(entries[0]?.kind).toBe('quest');
  });

  it('returns an empty list for empty logs', () => {
    expect(
      buildTxHistory({ questCompleted: [], pointsAdded: [], badgeIssued: [], attestationUsed: [] }),
    ).toEqual([]);
  });
});

describe('explorer URLs', () => {
  it('points at BscScan per chain', () => {
    expect(explorerTxUrl(56, '0xabc')).toBe('https://bscscan.com/tx/0xabc');
    expect(explorerTxUrl(97, '0xabc')).toBe('https://testnet.bscscan.com/tx/0xabc');
    expect(explorerAddressUrl(56, ALICE)).toBe(`https://bscscan.com/address/${ALICE}`);
    expect(explorerAddressUrl(97, ALICE)).toBe(`https://testnet.bscscan.com/address/${ALICE}`);
  });

  it('returns an empty string on local Anvil (no explorer)', () => {
    expect(explorerTxUrl(31337, '0xabc')).toBe('');
    expect(explorerAddressUrl(31337, ALICE)).toBe('');
  });

  it('returns an empty string for an unknown chain', () => {
    expect(explorerTxUrl(1, '0xabc')).toBe('');
  });
});

describe('EVENT_SIGNATURES', () => {
  it('every signature string parses as a viem event ABI item', () => {
    for (const [name, sig] of Object.entries(EVENT_SIGNATURES)) {
      const parsed = parseAbiItem(sig);
      expect(parsed.type, `${name} must parse as an event`).toBe('event');
    }
  });

  it('covers exactly the five events the app reads', () => {
    expect(Object.keys(EVENT_SIGNATURES).sort()).toEqual([
      'attestationUsed',
      'badgeDefined',
      'badgeIssued',
      'pointsAdded',
      'questCompleted',
    ]);
  });
});
