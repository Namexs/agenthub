'use client';

import { GlassCard } from '@/components/GlassCard';
import { AgentIdStatus } from '@/components/AgentIdStatus';
import { TxHistoryList } from '@/components/TxHistoryList';
import { useReputation } from '@/hooks/useReputation';
import { useTxHistory } from '@/hooks/useTxHistory';
import { useAchievements } from '@/hooks/useAchievements';
import { formatPoints } from '@/lib/utils';

export default function DashboardPage() {
  const reputation = useReputation();
  const history = useTxHistory();
  const achievements = useAchievements();
  const earnedBadges = achievements.badges.filter((b) => b.earned).length;

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
      <p className="mt-2 text-sm text-ink-400">
        Your Agent ID activity at a glance. Live on-chain data.
      </p>
      <div className="mt-8 grid gap-5 md:grid-cols-3">
        <GlassCard className="p-5">
          <p className="text-xs font-semibold uppercase tracking-widest text-ink-500">Agent ID</p>
          <div className="mt-3">
            <AgentIdStatus />
          </div>
        </GlassCard>
        <GlassCard className="p-5">
          <p className="text-xs font-semibold uppercase tracking-widest text-ink-500">Reputation</p>
          {!reputation.deployed ? (
            <p className="mt-3 text-sm text-ink-400">Reputation contract not deployed yet</p>
          ) : !reputation.isConnected ? (
            <p className="mt-3 text-sm text-ink-400">Connect your wallet to see your reputation.</p>
          ) : reputation.isLoading ? (
            <p className="mt-3 text-sm text-ink-400">Loading…</p>
          ) : (
            <>
              <p className="mt-3 text-2xl font-bold text-ink-100">
                {formatPoints(reputation.points ?? 0)} pts
              </p>
              <p className="mt-1 text-sm text-ink-400">
                Level {reputation.level ?? 0} · {reputation.totalEvents ?? 0} scoring events ·{' '}
                {earnedBadges} badge{earnedBadges === 1 ? '' : 's'} earned
              </p>
            </>
          )}
        </GlassCard>
        <GlassCard className="p-5">
          <p className="text-xs font-semibold uppercase tracking-widest text-ink-500">
            Quests completed
          </p>
          {!history.deployed ? (
            <p className="mt-3 text-sm text-ink-400">QuestManager not deployed yet</p>
          ) : !reputation.isConnected ? (
            <p className="mt-3 text-sm text-ink-400">Connect your wallet.</p>
          ) : history.isLoading ? (
            <p className="mt-3 text-sm text-ink-400">Loading…</p>
          ) : (
            <>
              <p className="mt-3 text-2xl font-bold text-ink-100">
                {history.entries.filter((e) => e.kind === 'quest').length}
              </p>
              <p className="mt-1 text-sm text-ink-400">on-chain completions</p>
            </>
          )}
        </GlassCard>
      </div>
      <GlassCard className="mt-5 p-5">
        <h2 className="text-lg font-semibold">Recent activity</h2>
        {!history.deployed ? (
          <p className="mt-2 text-sm text-ink-400">
            No on-chain activity yet. Contracts are not deployed.
          </p>
        ) : history.error ? (
          <p className="mt-2 text-sm text-red-300">Could not load activity: {history.error}</p>
        ) : history.isLoading ? (
          <p className="mt-2 text-sm text-ink-400">Loading…</p>
        ) : (
          <TxHistoryList entries={history.entries.slice(0, 5)} />
        )}
      </GlassCard>
    </div>
  );
}
