import { GlassCard } from './GlassCard';

export function BadgeCard({
  name,
  description,
  earned,
}: {
  name: string;
  description: string;
  earned: boolean;
}) {
  return (
    <GlassCard
      className={`flex flex-col items-center gap-2 p-5 text-center ${
        earned ? 'border-agent-400/60' : 'opacity-60'
      }`}
    >
      <div
        className={`flex h-12 w-12 items-center justify-center rounded-full border text-lg font-bold ${
          earned
            ? 'border-agent-400/60 bg-agent-500/20 text-agent-300'
            : 'border-navy-600 bg-navy-700 text-ink-400'
        }`}
      >
        {name.slice(0, 1)}
      </div>
      <p className="text-sm font-semibold text-ink-100">{name}</p>
      <p className="text-xs leading-relaxed text-ink-400">{description}</p>
      <p className="text-xs font-medium text-ink-500">{earned ? 'Earned' : 'Locked'}</p>
    </GlassCard>
  );
}
