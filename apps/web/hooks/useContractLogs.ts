'use client';

import { useCallback, useEffect, useState } from 'react';
import { usePublicClient } from 'wagmi';
import { parseAbiItem, type AbiEvent, type Address } from 'viem';
import { deployBlock } from '@/lib/contracts';
import type { DecodedLog } from '@/lib/events';

// Shared one-shot log fetcher (Phase 7). Event-based features
// (leaderboard, history, badges, reputation history) all read logs from
// the deployment block — never from genesis, which public RPCs refuse
// over large ranges. When NEXT_PUBLIC_DEPLOY_BLOCK is unset, the hook
// reports a configuration error instead of guessing.
//
// Public RPCs also cap a single eth_getLogs range: one
// deployBlock-to-latest call over ~40k blocks is rejected by the BSC
// dataseed with "limit exceeded" (seen live 2026-11-23, leaderboard
// down). The fetch is therefore split into fixed-size chunks and the
// results concatenated; aggregation in lib/events.ts dedupes by
// (txHash, logIndex), so chunk boundaries are safe.
//
// This is a one-shot fetch (not a live subscription): the UI refetches
// on mount and when the caller asks for a refresh. A live subscription
// (watchContractEvent) is a later addition.

export interface UseContractLogsResult {
  logs: DecodedLog[] | null;
  isLoading: boolean;
  /** Human-readable error, or null. */
  error: string | null;
  /** Unix ms when the last successful fetch completed. */
  updatedAt: number | null;
  refetch: () => void;
}

/** Max blocks per eth_getLogs call (BSC dataseed rejects wide ranges). */
const LOG_CHUNK_BLOCKS = 2000n;

export function useContractLogs(args: {
  address: Address | undefined;
  /** Event signature string, e.g. EVENT_SIGNATURES.questCompleted. */
  event: string;
  /** Indexed-arg filter, e.g. { account: address }. Must be JSON-stable. */
  filter?: Record<string, unknown> | undefined;
  enabled?: boolean;
}): UseContractLogsResult {
  const client = usePublicClient();
  const [logs, setLogs] = useState<DecodedLog[] | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<number | null>(null);
  const [nonce, setNonce] = useState(0);

  const refetch = useCallback(() => setNonce((n) => n + 1), []);
  const filterKey = JSON.stringify(args.filter ?? {});
  const enabled = args.enabled ?? true;

  useEffect(() => {
    if (!enabled || !args.address || !client) {
      setLogs(null);
      setIsLoading(false);
      setError(null);
      return;
    }
    if (deployBlock === undefined) {
      setLogs(null);
      setIsLoading(false);
      setError('Deployment block not configured. Set NEXT_PUBLIC_DEPLOY_BLOCK.');
      return;
    }
    let cancelled = false;
    setIsLoading(true);
    setError(null);
    const filter = JSON.parse(filterKey) as Record<string, unknown>;
    // Narrowed to number by the undefined check above; capture it here
    // because narrowing does not survive into the async closure below.
    const startBlock = BigInt(deployBlock);
    const fetchAll = async (): Promise<DecodedLog[] | null> => {
      const latest = await client.getBlockNumber();
      const all: DecodedLog[] = [];
      let from = startBlock;
      while (from <= latest) {
        const to = from + LOG_CHUNK_BLOCKS - 1n < latest ? from + LOG_CHUNK_BLOCKS - 1n : latest;
        const chunk = await client.getLogs({
          address: args.address,
          // parseAbiItem on a runtime string returns a union that includes
          // AbiConstructor; the caller only ever passes event signatures
          // (EVENT_SIGNATURES), so the cast is safe.
          event: parseAbiItem(args.event) as AbiEvent,
          args: filter,
          fromBlock: from,
          toBlock: to,
        });
        if (cancelled) return null;
        all.push(
          ...chunk.map((log) => ({
            transactionHash: log.transactionHash,
            blockNumber: Number(log.blockNumber),
            logIndex: log.logIndex,
            // getLogs with a runtime-parsed event does not type the args;
            // the event signatures in EVENT_SIGNATURES define the shape.
            args: (log as unknown as { args?: Record<string, unknown> }).args ?? {},
          })),
        );
        from = to + 1n;
      }
      return all;
    };
    fetchAll()
      .then((fetched) => {
        if (cancelled || fetched === null) return;
        setLogs(fetched);
        setUpdatedAt(Date.now());
        setIsLoading(false);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : 'Failed to fetch on-chain events');
        setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
    // filterKey is the stable serialization of args.filter.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, args.address, args.event, client, filterKey, nonce]);

  return { logs, isLoading, error, updatedAt, refetch };
}
