import { GlassCard } from '@/components/GlassCard';

export const metadata = { title: 'Activity History — AGENTHUB' };

export default function HistoryPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Activity History</h1>
      <p className="mt-2 text-sm text-ink-400">
        Every AGENTHUB action is an on-chain transaction. This page lists your quest completions,
        points, and badges with BscScan links.
      </p>
      <GlassCard className="mt-8 p-6">
        <p className="py-6 text-center text-sm text-ink-400">
          No transactions yet — history appears after your first on-chain quest completion.
        </p>
      </GlassCard>
    </div>
  );
}
