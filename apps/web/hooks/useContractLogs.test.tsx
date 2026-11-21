// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act, waitFor } from '@testing-library/react';
import { EVENT_SIGNATURES } from '@/lib/events';
import { useContractLogs } from './useContractLogs';

// PHASE 8: tests for the real log fetcher (NOT mocked here — the other
// hooks mock it, see hooks.test.tsx). The public client is a vi.fn()
// stand-in; the deploy block comes from the mocked lib/contracts.
//
// Proves: logs are fetched from the DEPLOY BLOCK (never genesis), the
// viem log shape is mapped to DecodedLog, RPC errors surface, and a
// missing deploy-block config fails loudly instead of guessing.

type Address = `0x${string}`;

const QM = '0x3333333333333333333333333333333333333333' as Address;
const ALICE = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8' as Address;

const mocks = vi.hoisted(() => ({
  getLogs: vi.fn(),
  client: null as { getLogs: ReturnType<typeof vi.fn> } | null,
  deployBlock: undefined as number | undefined,
}));

vi.mock('wagmi', () => ({
  usePublicClient: () => mocks.client,
}));

vi.mock('@/lib/contracts', () => ({
  contractAddresses: {},
  get deployBlock() {
    return mocks.deployBlock;
  },
}));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getLogs = vi.fn();
  mocks.client = { getLogs: mocks.getLogs };
  mocks.deployBlock = 100;
});

function viemLog(tx: string, blockNumber: bigint, logIndex: number, args: Record<string, unknown>) {
  return { transactionHash: `0x${tx}`, blockNumber, logIndex, args };
}

describe('useContractLogs', () => {
  it('fetches logs from the deploy block and maps them to DecodedLog', async () => {
    mocks.getLogs.mockResolvedValue([
      viemLog('a1', 120n, 0, { account: ALICE, questId: 1n }),
      viemLog('a2', 121n, 1, { account: ALICE, questId: 2n }),
    ]);
    const { result } = renderHook(() =>
      useContractLogs({
        address: QM,
        event: EVENT_SIGNATURES.questCompleted,
        filter: { account: ALICE },
        enabled: true,
      }),
    );
    await waitFor(() => expect(result.current.logs).toHaveLength(2));
    expect(result.current.logs).toEqual([
      {
        transactionHash: '0xa1',
        blockNumber: 120,
        logIndex: 0,
        args: { account: ALICE, questId: 1n },
      },
      {
        transactionHash: '0xa2',
        blockNumber: 121,
        logIndex: 1,
        args: { account: ALICE, questId: 2n },
      },
    ]);
    expect(result.current.error).toBeNull();
    expect(result.current.updatedAt).toEqual(expect.any(Number));
    expect(mocks.getLogs).toHaveBeenCalledTimes(1);
    const call = mocks.getLogs.mock.calls[0]?.[0] as Record<string, unknown>;
    expect(call.address).toBe(QM);
    expect(call.fromBlock).toBe(100n); // deploy block — never 0n/genesis
    expect(call.toBlock).toBe('latest');
    expect(call.args).toEqual({ account: ALICE });
    expect((call.event as { name?: string }).name).toBe('QuestCompleted');
  });

  it('shows a loading state while the fetch is in flight', async () => {
    let resolveLogs: (logs: unknown[]) => void = () => {};
    mocks.getLogs.mockImplementation(
      () => new Promise((resolve) => (resolveLogs = resolve as (logs: unknown[]) => void)),
    );
    const { result } = renderHook(() =>
      useContractLogs({
        address: QM,
        event: EVENT_SIGNATURES.questCompleted,
        enabled: true,
      }),
    );
    await waitFor(() => expect(result.current.isLoading).toBe(true));
    expect(result.current.logs).toBeNull();
    act(() => resolveLogs([]));
    await waitFor(() => expect(result.current.isLoading).toBe(false));
    expect(result.current.logs).toEqual([]);
  });

  it('fails loudly when the deploy block is not configured (no genesis guess)', async () => {
    mocks.deployBlock = undefined;
    const { result } = renderHook(() =>
      useContractLogs({
        address: QM,
        event: EVENT_SIGNATURES.questCompleted,
        enabled: true,
      }),
    );
    await waitFor(() =>
      expect(result.current.error).toBe(
        'Deployment block not configured. Set NEXT_PUBLIC_DEPLOY_BLOCK.',
      ),
    );
    expect(result.current.logs).toBeNull();
    expect(mocks.getLogs).not.toHaveBeenCalled();
  });

  it('surfaces an RPC error and keeps logs null', async () => {
    mocks.getLogs.mockRejectedValue(new Error('RPC rate limited'));
    const { result } = renderHook(() =>
      useContractLogs({
        address: QM,
        event: EVENT_SIGNATURES.questCompleted,
        enabled: true,
      }),
    );
    await waitFor(() => expect(result.current.error).toBe('RPC rate limited'));
    expect(result.current.logs).toBeNull();
    expect(result.current.isLoading).toBe(false);
  });

  it('does not fetch when disabled', async () => {
    const { result } = renderHook(() =>
      useContractLogs({
        address: QM,
        event: EVENT_SIGNATURES.questCompleted,
        enabled: false,
      }),
    );
    // Give the effect a tick to (not) run.
    await act(async () => {
      await new Promise((r) => setTimeout(r, 10));
    });
    expect(mocks.getLogs).not.toHaveBeenCalled();
    expect(result.current.logs).toBeNull();
    expect(result.current.error).toBeNull();
  });

  it('does not fetch without an address or a client', async () => {
    const { result: noAddress } = renderHook(() =>
      useContractLogs({
        address: undefined,
        event: EVENT_SIGNATURES.questCompleted,
        enabled: true,
      }),
    );
    await act(async () => {
      await new Promise((r) => setTimeout(r, 10));
    });
    expect(mocks.getLogs).not.toHaveBeenCalled();
    expect(noAddress.current.logs).toBeNull();

    mocks.client = null;
    const { result: noClient } = renderHook(() =>
      useContractLogs({
        address: QM,
        event: EVENT_SIGNATURES.questCompleted,
        enabled: true,
      }),
    );
    await act(async () => {
      await new Promise((r) => setTimeout(r, 10));
    });
    expect(mocks.getLogs).not.toHaveBeenCalled();
    expect(noClient.current.logs).toBeNull();
  });

  it('refetch() re-runs the fetch', async () => {
    mocks.getLogs.mockResolvedValue([]);
    const { result } = renderHook(() =>
      useContractLogs({
        address: QM,
        event: EVENT_SIGNATURES.questCompleted,
        enabled: true,
      }),
    );
    await waitFor(() => expect(result.current.logs).toEqual([]));
    expect(mocks.getLogs).toHaveBeenCalledTimes(1);
    act(() => result.current.refetch());
    await waitFor(() => expect(mocks.getLogs).toHaveBeenCalledTimes(2));
  });

  it('re-fetches when the filter changes', async () => {
    mocks.getLogs.mockResolvedValue([]);
    const { result, rerender } = renderHook(
      ({ filter }: { filter: Record<string, unknown> | undefined }) =>
        useContractLogs({
          address: QM,
          event: EVENT_SIGNATURES.questCompleted,
          filter,
          enabled: true,
        }),
      { initialProps: { filter: { account: ALICE } as Record<string, unknown> | undefined } },
    );
    await waitFor(() => expect(mocks.getLogs).toHaveBeenCalledTimes(1));
    rerender({ filter: undefined });
    await waitFor(() => expect(mocks.getLogs).toHaveBeenCalledTimes(2));
    const secondCall = mocks.getLogs.mock.calls[1]?.[0] as Record<string, unknown>;
    expect(secondCall.args).toEqual({});
    expect(result.current.logs).toEqual([]);
  });
});
