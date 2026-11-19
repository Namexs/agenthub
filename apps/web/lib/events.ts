import {
  EXPLORERS,
  REPUTATION_LEVEL_THRESHOLDS,
  type Address,
  type LeaderboardEntry,
  type TxHistoryEntry,
} from '@agenthub/shared';

// Pure event-aggregation helpers (Phase 7). Every function here takes
// plain log data and returns plain UI data — no RPC, no React — so the
// logic is unit-tested in lib/events.test.ts (Phase 8) and reused by the
// hooks (useLeaderboard, useTxHistory, useReputation, useAchievements).

/** Event signatures (must match the contract ABIs exactly). */
export const EVENT_SIGNATURES = {
  questCompleted:
    'event QuestCompleted(uint256 indexed questId, address indexed account, uint256 rewardPoints, uint256 badgeTokenId)',
  pointsAdded:
    'event PointsAdded(address indexed account, uint256 indexed questId, uint256 points, uint256 newTotal)',
  badgeIssued:
    'event BadgeIssued(address indexed account, uint256 indexed badgeId, uint256 indexed tokenId)',
  badgeDefined: 'event BadgeDefined(uint256 indexed badgeId, string name, string tokenURI)',
  attestationUsed:
    'event AttestationUsed(address indexed account, uint256 indexed questId, uint256 nonce, address indexed signer)',
} as const;

/**
 * Compute a reputation level from points (mirrors the contract).
 * Levels are 1-based: level 1 = 0 points, level 2 = 100, level 3 = 300,
 * level 4 = 700, level 5 = 1500 (Reputation._levelThreshold). The anvil
 * integration test caught a 0-based version of this function — 250
 * points is level 2, not level 1.
 */
export function computeLevel(points: number): number {
  let level = 1;
  for (let i = 0; i < REPUTATION_LEVEL_THRESHOLDS.length; i++) {
    const threshold = REPUTATION_LEVEL_THRESHOLDS[i];
    if (threshold !== undefined && points >= threshold) level = i + 1;
  }
  return level;
}

/** Minimal decoded-log shape (what viem getLogs returns, trimmed). */
export interface DecodedLog {
  transactionHash: `0x${string}`;
  blockNumber: number;
  logIndex: number;
  args: Record<string, unknown>;
}

function logKey(log: DecodedLog): string {
  return `${log.transactionHash}:${log.logIndex}`;
}

/**
 * Aggregate a leaderboard from QuestCompleted + PointsAdded logs.
 * Deduplicates by (txHash, logIndex) — the same log must never count
 * twice if a fetch overlaps. Points come from PointsAdded (the
 * authoritative per-completion award); quest counts come from
 * QuestCompleted. Sorted by points desc, then address asc (stable).
 */
export function aggregateLeaderboard(
  questCompletedLogs: DecodedLog[],
  pointsAddedLogs: DecodedLog[],
): LeaderboardEntry[] {
  const byAccount = new Map<string, { points: number; quests: number }>();

  const seenPoints = new Set<string>();
  for (const log of pointsAddedLogs) {
    const key = logKey(log);
    if (seenPoints.has(key)) continue;
    seenPoints.add(key);
    const account = (log.args.account as string)?.toLowerCase();
    const points = Number(log.args.points ?? 0);
    if (!account) continue;
    const entry = byAccount.get(account) ?? { points: 0, quests: 0 };
    entry.points += points;
    byAccount.set(account, entry);
  }

  const seenQuests = new Set<string>();
  for (const log of questCompletedLogs) {
    const key = logKey(log);
    if (seenQuests.has(key)) continue;
    seenQuests.add(key);
    const account = (log.args.account as string)?.toLowerCase();
    if (!account) continue;
    const entry = byAccount.get(account) ?? { points: 0, quests: 0 };
    entry.quests += 1;
    byAccount.set(account, entry);
  }

  return [...byAccount.entries()]
    .map(([address, { points, quests }]) => ({
      address: address as Address,
      points,
      level: computeLevel(points),
      questsCompleted: quests,
    }))
    .sort((a, b) => b.points - a.points || a.address.localeCompare(b.address))
    .map((entry, i) => ({ rank: i + 1, ...entry }));
}

/**
 * Merge quest/points/badge/attestation logs into one history list,
 * newest first (blockNumber desc, then logIndex desc). Each entry keeps
 * its tx hash so the UI can link to BscScan.
 */
export function buildTxHistory(input: {
  questCompleted: DecodedLog[];
  pointsAdded: DecodedLog[];
  badgeIssued: DecodedLog[];
  attestationUsed: DecodedLog[];
}): TxHistoryEntry[] {
  const entries: TxHistoryEntry[] = [];
  const seen = new Set<string>();
  const push = (
    log: DecodedLog,
    entry: Omit<TxHistoryEntry, 'hash' | 'blockNumber' | 'logIndex'>,
  ) => {
    const key = logKey(log);
    if (seen.has(key)) return;
    seen.add(key);
    entries.push({
      ...entry,
      hash: log.transactionHash,
      blockNumber: log.blockNumber,
      logIndex: log.logIndex,
    });
  };

  for (const log of input.questCompleted) {
    push(log, {
      kind: 'quest',
      questId: Number(log.args.questId ?? 0),
      points: Number(log.args.rewardPoints ?? 0),
    });
  }
  for (const log of input.pointsAdded) {
    push(log, {
      kind: 'points',
      questId: Number(log.args.questId ?? 0),
      points: Number(log.args.points ?? 0),
    });
  }
  for (const log of input.badgeIssued) {
    push(log, {
      kind: 'badge',
      badgeId: Number(log.args.badgeId ?? 0),
      tokenId: Number(log.args.tokenId ?? 0),
    });
  }
  for (const log of input.attestationUsed) {
    push(log, {
      kind: 'attestation',
      questId: Number(log.args.questId ?? 0),
      signer: log.args.signer as Address,
    });
  }

  return entries.sort((a, b) => b.blockNumber - a.blockNumber || b.logIndex - a.logIndex);
}

/** BscScan (or local) URL for a transaction hash. Empty on local Anvil. */
export function explorerTxUrl(chainId: number, hash: string): string {
  const base = (EXPLORERS as Record<number, string | undefined>)[chainId];
  return base ? `${base}/tx/${hash}` : '';
}

/** BscScan (or local) URL for an address. Empty on local Anvil. */
export function explorerAddressUrl(chainId: number, address: string): string {
  const base = (EXPLORERS as Record<number, string | undefined>)[chainId];
  return base ? `${base}/address/${address}` : '';
}
