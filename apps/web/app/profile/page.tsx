import { GlassCard } from '@/components/GlassCard';
import { BadgeCard } from '@/components/BadgeCard';
import { AgentIdStatus } from '@/components/AgentIdStatus';

export const metadata = { title: 'Profile — AGENTHUB' };

const BADGES = [
  {
    name: 'First Agent',
    description: 'Created your AGENTHUB profile as an Agent ID holder.',
    earned: false,
  },
  { name: 'Quest Explorer', description: 'Completed your first quest.', earned: false },
  {
    name: 'Community Builder',
    description: 'Completed a community campaign quest.',
    earned: false,
  },
  { name: 'Reputation Builder', description: 'Reached 100 reputation points.', earned: false },
];

export default function ProfilePage() {
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
            <span className="font-semibold text-ink-100">— pts</span>
          </p>
          <p>
            <span className="text-ink-500">Level:</span>{' '}
            <span className="font-semibold text-ink-100">—</span>
          </p>
          <p>
            <span className="text-ink-500">Badges:</span>{' '}
            <span className="font-semibold text-ink-100">0 / {BADGES.length}</span>
          </p>
        </div>
      </GlassCard>
      <h2 className="mt-10 text-xl font-bold">Badges</h2>
      <div className="mt-5 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
        {BADGES.map((badge) => (
          <BadgeCard
            key={badge.name}
            name={badge.name}
            description={badge.description}
            earned={badge.earned}
          />
        ))}
      </div>
    </div>
  );
}
