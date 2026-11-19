import { GlassCard } from '@/components/GlassCard';
import { LeaderboardTable } from '@/components/LeaderboardTable';

export const metadata = { title: 'Leaderboard — AGENTHUB' };

export default function LeaderboardPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Leaderboard</h1>
      <p className="mt-2 text-sm text-ink-400">
        Ranked by validated on-chain activity — completed quests and reputation points. No spam, no
        manufactured volume.
      </p>
      <GlassCard className="mt-8 p-2 sm:p-4">
        <LeaderboardTable entries={[]} />
      </GlassCard>
      <p className="mt-4 text-sm text-ink-500">
        Rankings are computed from on-chain events (QuestCompleted, PointsAdded) once the contracts
        are live.
      </p>
    </div>
  );
}
