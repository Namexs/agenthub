'use client';

import { GlassCard } from '@/components/GlassCard';
import { TxHistoryList } from '@/components/TxHistoryList';
import { useTxHistory } from '@/hooks/useTxHistory';

export default function HistoryPage() {
  const history = useTxHistory();

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Activity History</h1>
      <p className="mt-2 text-sm text-ink-400">
        Every AGENTHUB action is an on-chain transaction. This page lists your quest completions,
        points, and badges with BscScan links.
      </p>
      <GlassCard className="mt-8 p-6">
        {!history.deployed ? (
          <p className="py-6 text-center text-sm text-ink-400">
            Contracts not deployed yet — history appears after the testnet deploy.
          </p>
        ) : history.isLoading ? (
          <p className="py-6 text-center text-sm text-ink-400">Loading your on-chain history…</p>
        ) : history.error ? (
          <p className="py-6 text-center text-sm text-red-300">
            Could not load history: {history.error}
          </p>
        ) : (
          <TxHistoryList entries={history.entries} />
        )}
      </GlassCard>
    </div>
  );
}
