// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act, waitFor } from '@testing-library/react';
import { privateKeyToAccount } from 'viem/accounts';
import { EVENT_SIGNATURES, type DecodedLog } from '@/lib/events';
import {
  ATTESTATION_DOMAIN_NAME,
  ATTESTATION_DOMAIN_VERSION,
  ATTESTATION_TYPES,
} from '@/lib/attestation';
import { useAgentId } from './useAgentId';
import { useChainGuard } from './useChainGuard';
import { useQuests } from './useQuests';
import { useCompleteQuest } from './useCompleteQuest';
import { useReputation } from './useReputation';
import { useAchievements } from './useAchievements';
import { useLeaderboard, LEADERBOARD_PAGE_SIZE } from './useLeaderboard';
import { useAttestation } from './useAttestation';
import { useTxHistory } from './useTxHistory';

// PHASE 8: hook tests with mocked wagmi + mocked contract config.
// The hooks are thin wiring over wagmi reads/writes and the pure lib
// (quests / attestation / events, unit-tested in lib/*.test.ts), so
// these tests pin the WIRING: which read feeds which return field,
// loading / error / empty states, holder vs non-holder, wrong network,
// and the tx lifecycle (pending -> confirming -> confirmed/failed).
//
// The real chain wiring is proven separately by the anvil integration
// test (lib/anvil-integration.test.ts + apps/web/scripts/anvil-integration.mjs).
//
// These tests only run where jsdom + @testing-library/react resolve
// (see vitest.config.ts); on a normal machine install them with
//   pnpm add -D @testing-library/react jsdom

type Address = `0x${string}`;

const ALICE = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8' as Address;
const GATE = '0x2222222222222222222222222222222222222222' as Address;
const QM = '0x3333333333333333333333333333333333333333' as Address;
const REP = '0x4444444444444444444444444444444444444444' as Address;
const ACH = '0x5555555555555555555555555555555555555555' as Address;
const AGENT_ID = '0x1111111111111111111111111111111111111111' as Address;
const VERIFIER_KEY = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d' as const; // 0x7099… (ALICE)
const VERIFIER_ROLE =
  '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' as Address;

interface ReadResult {
  data?: unknown;
  isLoading?: boolean;
  error?: unknown;
}
interface LogsResult {
  logs: DecodedLog[] | null;
  isLoading?: boolean;
  error?: string | null;
  updatedAt?: number | null;
  refetch?: () => void;
}

const mocks = vi.hoisted(() => ({
  account: {
    address: undefined as Address | undefined,
    isConnected: false,
    chainId: undefined as number | undefined,
  },
  reads: {} as Record<string, ReadResult>,
  multiReads: {} as Record<string, ReadResult>,
  write: {
    writeContract: vi.fn(),
    data: undefined as `0x${string}` | undefined,
    isPending: false,
    error: null as Error | null,
    reset: vi.fn(),
  },
  receipt: { isLoading: false, isSuccess: false, isError: false },
  switchChain: vi.fn(),
  switchPending: false,
  addresses: {
    agentId: undefined as Address | undefined,
    agentGate: undefined as Address | undefined,
    questManager: undefined as Address | undefined,
    reputation: undefined as Address | undefined,
    achievement: undefined as Address | undefined,
  },
  logsByEvent: {} as Record<string, LogsResult>,
}));

vi.mock('wagmi', () => ({
  useAccount: () => mocks.account,
  // Merge defaults so the mock behaves like the real wagmi hooks
  // (isLoading false, no error) unless a test overrides them.
  useReadContract: (opts: { functionName: string }) => ({
    data: undefined,
    isLoading: false,
    error: undefined,
    ...mocks.reads[opts.functionName],
  }),
  useReadContracts: (opts: { contracts: { functionName: string }[] }) => {
    const key = opts.contracts[0]?.functionName ?? '';
    return {
      data: undefined,
      isLoading: false,
      error: undefined,
      ...mocks.multiReads[key],
    };
  },
  useWriteContract: () => ({
    writeContract: mocks.write.writeContract,
    data: mocks.write.data,
    isPending: mocks.write.isPending,
    error: mocks.write.error,
    reset: mocks.write.reset,
  }),
  useWaitForTransactionReceipt: () => mocks.receipt,
  useSwitchChain: () => ({ switchChain: mocks.switchChain, isPending: mocks.switchPending }),
  usePublicClient: () => null,
}));

vi.mock('@/lib/contracts', () => ({
  AGENT_GATE_ABI: [],
  QUEST_MANAGER_ABI: [],
  REPUTATION_ABI: [],
  ACHIEVEMENT_ABI: [],
  AGENT_ID_ABI: [],
  contractAddresses: mocks.addresses,
  deployBlock: undefined,
}));

vi.mock('@/lib/env', () => ({
  env: { NEXT_PUBLIC_CHAIN_ID: 97 },
}));

vi.mock('./useContractLogs', () => ({
  // Merge the real hook's defaults (logs null, no error, no update yet)
  // so tests only override what they care about.
  useContractLogs: (args: { event: string }) => ({
    logs: null,
    isLoading: false,
    error: null,
    updatedAt: null,
    refetch: vi.fn(),
    ...mocks.logsByEvent[args.event],
  }),
}));

function resetMocks() {
  vi.clearAllMocks();
  mocks.account.address = undefined;
  mocks.account.isConnected = false;
  mocks.account.chainId = undefined;
  mocks.reads = {};
  mocks.multiReads = {};
  mocks.logsByEvent = {};
  mocks.addresses.agentId = undefined;
  mocks.addresses.agentGate = undefined;
  mocks.addresses.questManager = undefined;
  mocks.addresses.reputation = undefined;
  mocks.addresses.achievement = undefined;
  mocks.write.data = undefined;
  mocks.write.isPending = false;
  mocks.write.error = null;
  mocks.receipt.isLoading = false;
  mocks.receipt.isSuccess = false;
  mocks.receipt.isError = false;
  mocks.switchPending = false;
}

function connect(address: Address = ALICE, chainId = 97) {
  mocks.account.address = address;
  mocks.account.isConnected = true;
  mocks.account.chainId = chainId;
}

function deployAll() {
  mocks.addresses.agentId = AGENT_ID;
  mocks.addresses.agentGate = GATE;
  mocks.addresses.questManager = QM;
  mocks.addresses.reputation = REP;
  mocks.addresses.achievement = ACH;
}

function rawQuest(id: number, overrides: Record<string, unknown> = {}) {
  return {
    id: BigInt(id),
    creator: '0x1111111111111111111111111111111111111111',
    title: `Quest ${id}`,
    description: `Description ${id}`,
    questType: 1, // OneTime
    validationKind: 0, // CheckIn
    validator: '0x0000000000000000000000000000000000000000',
    rewardPoints: 50n,
    badgeId: 1n,
    startTime: 1000n,
    endTime: 2000n,
    maxCompletions: 0n,
    completions: 0n,
    active: true,
    ...overrides,
  };
}

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

describe('useAgentId', () => {
  beforeEach(resetMocks);

  it('reports not a holder when the wallet is not connected', () => {
    deployAll();
    const { result } = renderHook(() => useAgentId());
    expect(result.current.isConnected).toBe(false);
    expect(result.current.isHolder).toBeNull();
    expect(result.current.configured).toBe(true);
  });

  it('reports a holder via the gate (source: gate)', () => {
    deployAll();
    connect();
    mocks.reads['isAgentHolder'] = { data: true };
    const { result } = renderHook(() => useAgentId());
    expect(result.current.isHolder).toBe(true);
    expect(result.current.source).toBe('gate');
    expect(result.current.isLoading).toBe(false);
  });

  it('reports a non-holder via the gate', () => {
    deployAll();
    connect();
    mocks.reads['isAgentHolder'] = { data: false };
    const { result } = renderHook(() => useAgentId());
    expect(result.current.isHolder).toBe(false);
  });

  it('reports loading while the gate read is pending', () => {
    deployAll();
    connect();
    mocks.reads['isAgentHolder'] = { data: undefined, isLoading: true };
    const { result } = renderHook(() => useAgentId());
    expect(result.current.isLoading).toBe(true);
    expect(result.current.isHolder).toBeNull();
  });

  it('falls back to balanceOf when the gate is not deployed', () => {
    mocks.addresses.agentId = AGENT_ID; // gate deliberately unset
    connect();
    mocks.reads['balanceOf'] = { data: 1n };
    const { result } = renderHook(() => useAgentId());
    expect(result.current.isHolder).toBe(true);
    expect(result.current.source).toBe('agentId');
  });

  it('balanceOf 0 means not a holder on the fallback path', () => {
    mocks.addresses.agentId = AGENT_ID;
    connect();
    mocks.reads['balanceOf'] = { data: 0n };
    const { result } = renderHook(() => useAgentId());
    expect(result.current.isHolder).toBe(false);
  });

  it('reports unconfigured when neither address is set', () => {
    connect();
    const { result } = renderHook(() => useAgentId());
    expect(result.current.configured).toBe(false);
    expect(result.current.isHolder).toBeNull();
  });
});

describe('useChainGuard', () => {
  beforeEach(resetMocks);

  it('is supported when not connected', () => {
    const { result } = renderHook(() => useChainGuard());
    expect(result.current.isSupported).toBe(true);
    expect(result.current.expectedChainId).toBe(97);
    expect(result.current.expectedChainName).toBe('BSC Testnet');
    expect(result.current.currentChainName).toBeNull();
  });

  it('is supported on the expected chain', () => {
    connect(ALICE, 97);
    const { result } = renderHook(() => useChainGuard());
    expect(result.current.isSupported).toBe(true);
    expect(result.current.currentChainName).toBe('BSC Testnet');
  });

  it('is NOT supported on a different chain and names both chains', () => {
    connect(ALICE, 56);
    const { result } = renderHook(() => useChainGuard());
    expect(result.current.isSupported).toBe(false);
    expect(result.current.currentChainName).toBe('BNB Smart Chain');
    expect(result.current.expectedChainName).toBe('BSC Testnet');
  });

  it('names an unknown chain generically', () => {
    connect(ALICE, 1);
    const { result } = renderHook(() => useChainGuard());
    expect(result.current.currentChainName).toBe('Chain 1');
    expect(result.current.isSupported).toBe(false);
  });

  it('switchToExpected requests a switch to the expected chain', () => {
    connect(ALICE, 56);
    const { result } = renderHook(() => useChainGuard());
    act(() => result.current.switchToExpected());
    expect(mocks.switchChain).toHaveBeenCalledWith({ chainId: 97 });
    expect(mocks.switchChain).toHaveBeenCalledTimes(1);
  });

  it('exposes the switching pending state', () => {
    connect(ALICE, 56);
    mocks.switchPending = true;
    const { result } = renderHook(() => useChainGuard());
    expect(result.current.isSwitching).toBe(true);
  });
});

describe('useQuests', () => {
  beforeEach(resetMocks);

  it('reports undeployed with an empty list when no QuestManager is configured', () => {
    const { result } = renderHook(() => useQuests());
    expect(result.current.deployed).toBe(false);
    expect(result.current.quests).toEqual([]);
    expect(result.current.questCount).toBe(0);
    expect(result.current.error).toBeNull();
  });

  it('maps on-chain quests with per-account state', () => {
    deployAll();
    connect();
    mocks.reads['questCount'] = { data: 2n };
    mocks.multiReads['getQuest'] = {
      data: [
        { status: 'success', result: rawQuest(1) },
        { status: 'success', result: rawQuest(2, { title: 'Second', rewardPoints: 25n }) },
      ],
    };
    mocks.multiReads['hasCompleted'] = {
      data: [
        { status: 'success', result: true },
        { status: 'success', result: 0n },
        { status: 'success', result: false },
        { status: 'success', result: 12345n },
      ],
    };
    const { result } = renderHook(() => useQuests());
    expect(result.current.deployed).toBe(true);
    expect(result.current.questCount).toBe(2);
    expect(result.current.quests).toHaveLength(2);
    expect(result.current.quests[0]).toMatchObject({
      id: 1,
      title: 'Quest 1',
      rewardPoints: 50,
      state: { completed: true, nextCompletionAt: 0 },
    });
    expect(result.current.quests[1]).toMatchObject({
      id: 2,
      title: 'Second',
      rewardPoints: 25,
      state: { completed: false, nextCompletionAt: 12345 },
    });
    expect(result.current.error).toBeNull();
  });

  it('defaults state when the wallet is not connected', () => {
    deployAll();
    mocks.reads['questCount'] = { data: 1n };
    mocks.multiReads['getQuest'] = { data: [{ status: 'success', result: rawQuest(1) }] };
    const { result } = renderHook(() => useQuests());
    expect(result.current.quests[0]?.state).toEqual({ completed: false, nextCompletionAt: 0 });
  });

  it('filters out a quest whose getQuest call failed', () => {
    deployAll();
    mocks.reads['questCount'] = { data: 2n };
    mocks.multiReads['getQuest'] = {
      data: [
        { status: 'success', result: rawQuest(1) },
        { status: 'failure', error: new Error('reverted') },
      ],
    };
    const { result } = renderHook(() => useQuests());
    expect(result.current.quests).toHaveLength(1);
    expect(result.current.quests[0]?.id).toBe(1);
  });

  it('surfaces an RPC error from the count read', () => {
    deployAll();
    mocks.reads['questCount'] = { data: undefined, error: new Error('RPC boom') };
    const { result } = renderHook(() => useQuests());
    expect(result.current.error).toBe('RPC boom');
    expect(result.current.quests).toEqual([]);
  });

  it('reports loading while any read is pending', () => {
    deployAll();
    mocks.reads['questCount'] = { data: undefined, isLoading: true };
    const { result } = renderHook(() => useQuests());
    expect(result.current.isLoading).toBe(true);
  });

  it('reports zero quests when the count is 0 (empty state)', () => {
    deployAll();
    mocks.reads['questCount'] = { data: 0n };
    const { result } = renderHook(() => useQuests());
    expect(result.current.questCount).toBe(0);
    expect(result.current.quests).toEqual([]);
  });
});

describe('useCompleteQuest', () => {
  beforeEach(resetMocks);

  it('complete() writes completeQuest with the quest id', () => {
    deployAll();
    const { result } = renderHook(() => useCompleteQuest());
    act(() => result.current.complete(3));
    expect(mocks.write.writeContract).toHaveBeenCalledWith({
      address: QM,
      abi: [],
      functionName: 'completeQuest',
      args: [3n],
    });
  });

  it('completeWithAttestation() writes the attestation call with all three args', () => {
    deployAll();
    const sig = `0x${'ab'.repeat(65)}` as `0x${string}`;
    const { result } = renderHook(() => useCompleteQuest());
    act(() => result.current.completeWithAttestation(3, 1_700_003_600, sig));
    expect(mocks.write.writeContract).toHaveBeenCalledWith({
      address: QM,
      abi: [],
      functionName: 'completeQuestWithAttestation',
      args: [3n, 1_700_003_600n, sig],
    });
  });

  it('is a no-op when the QuestManager is not deployed', () => {
    const { result } = renderHook(() => useCompleteQuest());
    act(() => result.current.complete(3));
    act(() => result.current.completeWithAttestation(3, 1, `0x${'00'.repeat(65)}`));
    expect(mocks.write.writeContract).not.toHaveBeenCalled();
  });

  it('exposes pending / confirming / success through the lifecycle', () => {
    deployAll();
    mocks.write.isPending = true;
    const { result, rerender } = renderHook(() => useCompleteQuest());
    expect(result.current.isPending).toBe(true);
    expect(result.current.isSuccess).toBe(false);

    mocks.write.isPending = false;
    mocks.write.data = '0xhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhash';
    mocks.receipt.isLoading = true;
    rerender();
    expect(result.current.isConfirming).toBe(true);
    expect(result.current.isSuccess).toBe(false);

    mocks.receipt.isLoading = false;
    mocks.receipt.isSuccess = true;
    rerender();
    expect(result.current.isSuccess).toBe(true);
    expect(result.current.isFailed).toBe(false);
    expect(result.current.error).toBeNull();
  });

  it('a reverted receipt is a failure, not a completion', () => {
    deployAll();
    mocks.write.data = '0xhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhash';
    mocks.receipt.isError = true;
    const { result } = renderHook(() => useCompleteQuest());
    expect(result.current.isSuccess).toBe(false);
    expect(result.current.isFailed).toBe(true);
    expect(result.current.error).toBe('Transaction reverted on-chain');
  });

  it('a write error (e.g. user rejected) is a failure with the message', () => {
    deployAll();
    mocks.write.error = new Error('User rejected the request');
    const { result } = renderHook(() => useCompleteQuest());
    expect(result.current.isFailed).toBe(true);
    expect(result.current.error).toBe('User rejected the request');
  });
});

describe('useReputation', () => {
  beforeEach(resetMocks);

  it('maps points, level, totalEvents, and history from logs', () => {
    deployAll();
    connect();
    mocks.reads['points'] = { data: 250n };
    mocks.reads['level'] = { data: 2n };
    mocks.reads['totalEvents'] = { data: 3n };
    mocks.logsByEvent[EVENT_SIGNATURES.pointsAdded] = {
      logs: [
        log('a1', 10, 1, { account: ALICE, questId: 1n, points: 50n }),
        log('a2', 11, 1, { account: ALICE, questId: 2n, points: 200n }),
      ],
    };
    const { result } = renderHook(() => useReputation());
    expect(result.current.deployed).toBe(true);
    expect(result.current.points).toBe(250);
    expect(result.current.level).toBe(2);
    expect(result.current.totalEvents).toBe(3);
    expect(result.current.history).toHaveLength(2);
    expect(result.current.history[0]).toMatchObject({ kind: 'points', points: 200 });
    expect(result.current.error).toBeNull();
  });

  it('returns nulls while the reads are pending', () => {
    deployAll();
    connect();
    mocks.reads['points'] = { data: undefined, isLoading: true };
    const { result } = renderHook(() => useReputation());
    expect(result.current.points).toBeNull();
    expect(result.current.level).toBeNull();
    expect(result.current.totalEvents).toBeNull();
    expect(result.current.isLoading).toBe(true);
  });

  it('surfaces a history fetch error', () => {
    deployAll();
    connect();
    mocks.logsByEvent[EVENT_SIGNATURES.pointsAdded] = {
      logs: null,
      error: 'RPC rate limited',
    };
    const { result } = renderHook(() => useReputation());
    expect(result.current.error).toBe('RPC rate limited');
  });

  it('reports undeployed with nulls when Reputation is not configured', () => {
    connect();
    const { result } = renderHook(() => useReputation());
    expect(result.current.deployed).toBe(false);
    expect(result.current.points).toBeNull();
    expect(result.current.history).toEqual([]);
  });
});

describe('useAchievements', () => {
  beforeEach(resetMocks);

  it('merges the badge catalogue with ownership', () => {
    deployAll();
    connect();
    mocks.logsByEvent[EVENT_SIGNATURES.badgeDefined] = {
      logs: [
        log('d1', 5, 0, { badgeId: 1n, name: 'First Steps', tokenURI: 'ipfs://one' }),
        log('d2', 6, 0, { badgeId: 2n, name: 'Explorer', tokenURI: 'ipfs://two' }),
      ],
    };
    mocks.logsByEvent[EVENT_SIGNATURES.badgeIssued] = {
      logs: [log('i1', 10, 2, { account: ALICE, badgeId: 1n, tokenId: 7n })],
    };
    const { result } = renderHook(() => useAchievements());
    expect(result.current.badges).toEqual([
      {
        badgeId: 1,
        name: 'First Steps',
        description: '',
        tokenURI: 'ipfs://one',
        earned: true,
        tokenId: 7,
      },
      {
        badgeId: 2,
        name: 'Explorer',
        description: '',
        tokenURI: 'ipfs://two',
        earned: false,
        tokenId: null,
      },
    ]);
  });

  it('shows an issued-but-undefined badge with a placeholder name', () => {
    deployAll();
    connect();
    mocks.logsByEvent[EVENT_SIGNATURES.badgeDefined] = { logs: [] };
    mocks.logsByEvent[EVENT_SIGNATURES.badgeIssued] = {
      logs: [log('i1', 10, 2, { account: ALICE, badgeId: 9n, tokenId: 3n })],
    };
    const { result } = renderHook(() => useAchievements());
    expect(result.current.badges).toEqual([
      {
        badgeId: 9,
        name: 'Badge #9',
        description: '',
        tokenURI: '',
        earned: true,
        tokenId: 3,
      },
    ]);
  });

  it('returns an empty catalogue when nothing is defined (empty state)', () => {
    deployAll();
    connect();
    mocks.logsByEvent[EVENT_SIGNATURES.badgeDefined] = { logs: [] };
    mocks.logsByEvent[EVENT_SIGNATURES.badgeIssued] = { logs: [] };
    const { result } = renderHook(() => useAchievements());
    expect(result.current.badges).toEqual([]);
    expect(result.current.error).toBeNull();
  });

  it('surfaces a catalogue fetch error', () => {
    deployAll();
    mocks.logsByEvent[EVENT_SIGNATURES.badgeDefined] = {
      logs: null,
      error: 'RPC down',
    };
    const { result } = renderHook(() => useAchievements());
    expect(result.current.error).toBe('RPC down');
  });
});

describe('useLeaderboard', () => {
  beforeEach(resetMocks);

  function seedEntries(n: number) {
    const completed: DecodedLog[] = [];
    const points: DecodedLog[] = [];
    for (let i = 0; i < n; i++) {
      const account = `0x${String(i).padStart(40, '0')}` as `0x${string}`;
      completed.push(log(`c${i}`, 10 + i, 0, { account, questId: 1n }));
      points.push(log(`p${i}`, 10 + i, 1, { account, questId: 1n, points: BigInt((n - i) * 10) }));
    }
    mocks.logsByEvent[EVENT_SIGNATURES.questCompleted] = { logs: completed, updatedAt: 1000 };
    mocks.logsByEvent[EVENT_SIGNATURES.pointsAdded] = { logs: points, updatedAt: 2000 };
  }

  it('aggregates entries from logs with rank and last-updated time', () => {
    deployAll();
    seedEntries(3);
    const { result } = renderHook(() => useLeaderboard());
    expect(result.current.deployed).toBe(true);
    expect(result.current.totalEntries).toBe(3);
    expect(result.current.entries[0]).toMatchObject({ rank: 1, points: 30 });
    // updatedAt is the min of the two fetches (the older snapshot).
    expect(result.current.updatedAt).toBe(1000);
    expect(result.current.totalPages).toBe(1);
  });

  it('paginates at 10 entries per page', () => {
    deployAll();
    seedEntries(12);
    const { result } = renderHook(() => useLeaderboard());
    expect(LEADERBOARD_PAGE_SIZE).toBe(10);
    expect(result.current.totalPages).toBe(2);
    expect(result.current.page).toBe(1);
    expect(result.current.entries).toHaveLength(10);
    act(() => result.current.setPage(2));
    expect(result.current.page).toBe(2);
    expect(result.current.entries).toHaveLength(2);
  });

  it('clamps a page number above the total', () => {
    deployAll();
    seedEntries(3);
    const { result } = renderHook(() => useLeaderboard());
    act(() => result.current.setPage(99));
    expect(result.current.page).toBe(1);
    expect(result.current.entries).toHaveLength(3);
  });

  it('returns an empty ranking when there are no logs (empty state)', () => {
    deployAll();
    mocks.logsByEvent[EVENT_SIGNATURES.questCompleted] = { logs: [] };
    mocks.logsByEvent[EVENT_SIGNATURES.pointsAdded] = { logs: [] };
    const { result } = renderHook(() => useLeaderboard());
    expect(result.current.totalEntries).toBe(0);
    expect(result.current.entries).toEqual([]);
    expect(result.current.totalPages).toBe(1);
    expect(result.current.updatedAt).toBeNull();
  });

  it('surfaces a fetch error from either log source', () => {
    deployAll();
    mocks.logsByEvent[EVENT_SIGNATURES.questCompleted] = { logs: null, error: 'RPC down' };
    mocks.logsByEvent[EVENT_SIGNATURES.pointsAdded] = { logs: [] };
    const { result } = renderHook(() => useLeaderboard());
    expect(result.current.error).toBe('RPC down');
  });

  it('refetch() refreshes both log sources', () => {
    deployAll();
    const refetchCompleted = vi.fn();
    const refetchPoints = vi.fn();
    mocks.logsByEvent[EVENT_SIGNATURES.questCompleted] = {
      logs: [],
      refetch: refetchCompleted,
    };
    mocks.logsByEvent[EVENT_SIGNATURES.pointsAdded] = { logs: [], refetch: refetchPoints };
    const { result } = renderHook(() => useLeaderboard());
    act(() => result.current.refetch());
    expect(refetchCompleted).toHaveBeenCalledTimes(1);
    expect(refetchPoints).toHaveBeenCalledTimes(1);
  });
});

describe('useAttestation', () => {
  beforeEach(resetMocks);

  async function signFor(
    account: Address,
    questId: number,
    nonce: number,
    deadline: number,
  ): Promise<`0x${string}`> {
    return privateKeyToAccount(VERIFIER_KEY).signTypedData({
      domain: {
        name: ATTESTATION_DOMAIN_NAME,
        version: ATTESTATION_DOMAIN_VERSION,
        chainId: 97,
        verifyingContract: QM,
      },
      types: ATTESTATION_TYPES,
      primaryType: 'Attestation',
      message: {
        account,
        questId: BigInt(questId),
        nonce: BigInt(nonce),
        deadline: BigInt(deadline),
      },
    });
  }

  function setupRole(roleResult: boolean) {
    mocks.reads['nonces'] = { data: 1n };
    mocks.reads['VERIFIER_ROLE'] = { data: VERIFIER_ROLE };
    mocks.reads['hasRole'] = { data: roleResult };
  }

  it('exposes the on-chain nonce for the connected account', () => {
    deployAll();
    connect();
    setupRole(true);
    const { result } = renderHook(() => useAttestation(3));
    expect(result.current.verification.nonce).toBe(1);
    expect(result.current.verification.nonceLoading).toBe(false);
  });

  it('requires a connected wallet before checking', async () => {
    deployAll();
    // Deliberately not connected.
    const { result } = renderHook(() => useAttestation(3));
    let checkResult: unknown;
    await act(async () => {
      checkResult = await result.current.check(`0x${'00'.repeat(65)}`, 1_700_003_600);
    });
    expect(checkResult).toMatchObject({
      valid: false,
      errors: ['Connect your wallet and wait for the nonce to load first'],
    });
  });

  it('accepts a valid attestation from a VERIFIER_ROLE holder', async () => {
    deployAll();
    connect();
    setupRole(true);
    const { result } = renderHook(() => useAttestation(3));
    const deadline = Math.floor(Date.now() / 1000) + 3600;
    const sig = await signFor(ALICE, 3, 1, deadline);
    await act(async () => {
      await result.current.check(sig, deadline);
    });
    await waitFor(() => expect(result.current.verification.valid).toBe(true));
    expect(result.current.verification.signer).toBe(ALICE); // ALICE is the verifier key holder here
    expect(result.current.verification.isVerifier).toBe(true);
    expect(result.current.verification.errors).toEqual([]);
  });

  it('rejects a valid signature from an account WITHOUT VERIFIER_ROLE', async () => {
    deployAll();
    connect();
    setupRole(false);
    const { result } = renderHook(() => useAttestation(3));
    const deadline = Math.floor(Date.now() / 1000) + 3600;
    const sig = await signFor(ALICE, 3, 1, deadline);
    await act(async () => {
      await result.current.check(sig, deadline);
    });
    expect(result.current.verification.valid).toBe(false);
    expect(result.current.verification.isVerifier).toBe(false);
    expect(result.current.verification.errors).toContain(
      'Recovered signer does not hold VERIFIER_ROLE',
    );
  });

  it('rejects an expired attestation', async () => {
    deployAll();
    connect();
    setupRole(true);
    const { result } = renderHook(() => useAttestation(3));
    const deadline = Math.floor(Date.now() / 1000) - 10;
    const sig = await signFor(ALICE, 3, 1, deadline);
    await act(async () => {
      await result.current.check(sig, deadline);
    });
    expect(result.current.verification.valid).toBe(false);
    expect(result.current.verification.errors).toContain('Attestation has expired');
  });

  it('reset() clears the check result', async () => {
    deployAll();
    connect();
    setupRole(true);
    const { result } = renderHook(() => useAttestation(3));
    const deadline = Math.floor(Date.now() / 1000) + 3600;
    const sig = await signFor(ALICE, 3, 1, deadline);
    await act(async () => {
      await result.current.check(sig, deadline);
    });
    expect(result.current.verification.valid).toBe(true);
    act(() => result.current.reset());
    expect(result.current.verification.valid).toBe(false);
    expect(result.current.verification.signer).toBeNull();
  });
});

describe('useTxHistory', () => {
  beforeEach(resetMocks);

  it('merges all four log kinds newest-first', () => {
    deployAll();
    connect();
    mocks.logsByEvent[EVENT_SIGNATURES.questCompleted] = {
      logs: [log('a1', 10, 0, { questId: 1n, rewardPoints: 50n })],
    };
    mocks.logsByEvent[EVENT_SIGNATURES.pointsAdded] = {
      logs: [log('a1', 10, 1, { questId: 1n, points: 50n })],
    };
    mocks.logsByEvent[EVENT_SIGNATURES.badgeIssued] = {
      logs: [log('a1', 10, 2, { badgeId: 1n, tokenId: 7n })],
    };
    mocks.logsByEvent[EVENT_SIGNATURES.attestationUsed] = {
      logs: [log('a2', 9, 0, { questId: 3n, signer: ALICE })],
    };
    const { result } = renderHook(() => useTxHistory());
    expect(result.current.deployed).toBe(true);
    expect(result.current.entries.map((e) => e.kind)).toEqual([
      'badge',
      'points',
      'quest',
      'attestation',
    ]);
    expect(result.current.entries[0]?.hash).toBe('0xa1');
  });

  it('returns an empty list when there are no logs', () => {
    deployAll();
    connect();
    const { result } = renderHook(() => useTxHistory());
    expect(result.current.entries).toEqual([]);
    expect(result.current.error).toBeNull();
  });

  it('surfaces the first fetch error', () => {
    deployAll();
    connect();
    mocks.logsByEvent[EVENT_SIGNATURES.badgeIssued] = { logs: null, error: 'RPC down' };
    const { result } = renderHook(() => useTxHistory());
    expect(result.current.error).toBe('RPC down');
  });

  it('reports undeployed when any of the three contracts is missing', () => {
    mocks.addresses.questManager = QM;
    mocks.addresses.reputation = REP;
    // achievement deliberately unset
    connect();
    const { result } = renderHook(() => useTxHistory());
    expect(result.current.deployed).toBe(false);
  });
});
