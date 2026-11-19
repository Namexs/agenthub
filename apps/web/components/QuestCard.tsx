import { QuestType } from '@agenthub/shared';
import { GlassCard } from './GlassCard';

const TYPE_LABEL: Record<QuestType, string> = {
  [QuestType.DailyCheckIn]: 'Daily',
  [QuestType.OneTime]: 'One-time',
  [QuestType.Weekly]: 'Weekly',
  [QuestType.Community]: 'Community',
};

export function QuestCard({
  title,
  description,
  questType,
  rewardPoints,
  badgeId,
}: {
  title: string;
  description: string;
  questType: QuestType;
  rewardPoints: number;
  badgeId: number;
}) {
  return (
    <GlassCard className="flex flex-col gap-3 p-5">
      <div className="flex items-center justify-between">
        <span className="rounded-pill border border-electric-500/50 bg-electric-600/10 px-3 py-1 text-xs font-medium text-electric-300">
          {TYPE_LABEL[questType]}
        </span>
        <span className="text-sm font-semibold text-agent-300">+{rewardPoints} pts</span>
      </div>
      <h3 className="text-lg font-semibold text-ink-100">{title}</h3>
      <p className="flex-1 text-sm leading-relaxed text-ink-400">{description}</p>
      <div className="flex items-center justify-between text-xs text-ink-500">
        <span>{badgeId > 0 ? `Badge #${badgeId} on completion` : 'No badge'}</span>
        <span className="text-ink-400">On-chain in Phase 2</span>
      </div>
    </GlassCard>
  );
}
