'use client';

import { GlassCard } from '@/components/GlassCard';
import { LeaderboardTable } from '@/components/LeaderboardTable';
import { useLeaderboard } from '@/hooks/useLeaderboard';

export default function LeaderboardPage() {
  const leaderboard = useLeaderboard();

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Leaderboard</h1>
      <p className="mt-2 text-sm text-ink-400">
        Ranked by validated on-chain activity — completed quests and reputation points. No spam, no
        manufactured volume.
      </p>
      <GlassCard className="mt-8 p-2 sm:p-4">
        {!leaderboard.deployed ? (
          <p className="py-8 text-center text-sm text-ink-400">
            Contracts not deployed yet — the leaderboard fills up once quests are completed
            on-chain.
          </p>
        ) : leaderboard.isLoading ? (
          <p className="py-8 text-center text-sm text-ink-400">
            Loading rankings from on-chain events…
          </p>
        ) : leaderboard.error ? (
          <p className="py-8 text-center text-sm text-red-300">
            Could not load the leaderboard: {leaderboard.error}
          </p>
        ) : (
          <>
            <LeaderboardTable entries={leaderboard.entries} />
            {leaderboard.totalPages > 1 && (
              <div className="flex items-center justify-between px-4 py-3 text-sm">
                <button
                  type="button"
                  onClick={() => leaderboard.setPage(leaderboard.page - 1)}
                  disabled={leaderboard.page <= 1}
                  className="rounded-pill border border-navy-600 px-4 py-1.5 text-ink-200 transition hover:border-agent-400/60 disabled:opacity-50"
                >
                  Previous
                </button>
                <span className="text-ink-400">
                  Page {leaderboard.page} of {leaderboard.totalPages} · {leaderboard.totalEntries}{' '}
                  ranked agents
                </span>
                <button
                  type="button"
                  onClick={() => leaderboard.setPage(leaderboard.page + 1)}
                  disabled={leaderboard.page >= leaderboard.totalPages}
                  className="rounded-pill border border-navy-600 px-4 py-1.5 text-ink-200 transition hover:border-agent-400/60 disabled:opacity-50"
                >
                  Next
                </button>
              </div>
            )}
          </>
        )}
      </GlassCard>
      <p className="mt-4 text-sm text-ink-500">
        Rankings are computed from on-chain events (QuestCompleted, PointsAdded)
        {leaderboard.updatedAt
          ? ` — last updated ${new Date(leaderboard.updatedAt).toLocaleTimeString()}`
          : ''}
        .{' '}
        <button
          type="button"
          onClick={leaderboard.refetch}
          disabled={!leaderboard.deployed || leaderboard.isLoading}
          className="text-electric-300 underline disabled:opacity-50"
        >
          Refresh
        </button>
      </p>
    </div>
  );
}
