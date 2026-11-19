'use client';

import { GlassCard } from '@/components/GlassCard';
import { BadgeCard } from '@/components/BadgeCard';
import { AgentIdStatus } from '@/components/AgentIdStatus';
import { useReputation } from '@/hooks/useReputation';
import { useAchievements } from '@/hooks/useAchievements';
import { formatPoints } from '@/lib/utils';

export default function ProfilePage() {
  const reputation = useReputation();
  const achievements = useAchievements();
  const earnedBadges = achievements.badges.filter((b) => b.earned);

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Profile</h1>
      <p className="mt-2 text-sm text-ink-400">
        Your on-chain reputation and soulbound badges. Badges are non-transferable and publicly
        verifiable.
      </p>
      <GlassCard className="mt-8 p-5">
        <p className="text-xs font-semibold uppercase tracking-widest text-ink-500">
          Agent ID status
        </p>
        <div className="mt-3">
          <AgentIdStatus />
        </div>
        <div className="mt-4 flex flex-wrap gap-6 text-sm">
          <p>
            <span className="text-ink-500">Reputation:</span>{' '}
            <span className="font-semibold text-ink-100">
              {!reputation.deployed
                ? '—'
                : !reputation.isConnected
                  ? 'connect wallet'
                  : reputation.isLoading
                    ? '…'
                    : `${formatPoints(reputation.points ?? 0)} pts`}
            </span>
          </p>
          <p>
            <span className="text-ink-500">Level:</span>{' '}
            <span className="font-semibold text-ink-100">
              {reputation.level === null ? '—' : reputation.level}
            </span>
          </p>
          <p>
            <span className="text-ink-500">Badges:</span>{' '}
            <span className="font-semibold text-ink-100">
              {earnedBadges.length} / {achievements.badges.length}
            </span>
          </p>
        </div>
      </GlassCard>
      <h2 className="mt-10 text-xl font-bold">Badges</h2>
      {!achievements.deployed ? (
        <p className="mt-5 text-sm text-ink-400">
          Achievement contract not deployed yet — badges appear after the testnet deploy.
        </p>
      ) : achievements.isLoading ? (
        <p className="mt-5 text-sm text-ink-400">Loading badges from on-chain events…</p>
      ) : achievements.error ? (
        <p className="mt-5 text-sm text-red-300">Could not load badges: {achievements.error}</p>
      ) : achievements.badges.length === 0 ? (
        <p className="mt-5 text-sm text-ink-400">
          No badges defined yet — the first badges are defined after the deploy.
        </p>
      ) : (
        <div className="mt-5 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {achievements.badges.map((badge) => (
            <BadgeCard
              key={badge.badgeId}
              name={badge.name}
              description={
                badge.earned
                  ? `Earned — soulbound token #${badge.tokenId ?? '?'}. Non-transferable.`
                  : 'Locked — complete the quest that awards this badge.'
              }
              earned={badge.earned}
            />
          ))}
        </div>
      )}
    </div>
  );
}
