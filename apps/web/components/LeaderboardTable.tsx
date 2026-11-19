import type { LeaderboardEntry } from '@agenthub/shared';
import { formatAddress } from '@/lib/utils';

export function LeaderboardTable({ entries }: { entries: LeaderboardEntry[] }) {
  if (entries.length === 0) {
    return (
      <p className="py-8 text-center text-sm text-ink-400">
        No ranked agents yet — the leaderboard fills up once quests are completed on-chain.
      </p>
    );
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-navy-600/60 text-xs uppercase tracking-wide text-ink-500">
            <th className="px-4 py-3 font-medium">Rank</th>
            <th className="px-4 py-3 font-medium">Agent</th>
            <th className="px-4 py-3 font-medium">Level</th>
            <th className="px-4 py-3 font-medium">Quests</th>
            <th className="px-4 py-3 text-right font-medium">Points</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr key={entry.address} className="border-b border-navy-700/40 last:border-0">
              <td className="px-4 py-3 font-semibold text-ink-100">#{entry.rank}</td>
              <td className="px-4 py-3 font-mono text-ink-200">{formatAddress(entry.address)}</td>
              <td className="px-4 py-3 text-ink-200">Lv {entry.level}</td>
              <td className="px-4 py-3 text-ink-200">{entry.questsCompleted}</td>
              <td className="px-4 py-3 text-right font-semibold text-agent-300">
                {entry.points.toLocaleString('en-US')}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
