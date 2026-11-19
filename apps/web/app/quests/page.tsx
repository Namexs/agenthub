'use client';

import { QuestCard } from '@/components/QuestCard';
import { useQuests } from '@/hooks/useQuests';

export default function QuestsPage() {
  const { quests, deployed } = useQuests();
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Quests</h1>
      <p className="mt-2 text-sm text-ink-400">
        {deployed
          ? 'Live quests from QuestManager.'
          : 'Launch catalogue preview — these quests go on-chain with the Phase 2 testnet deploy.'}
      </p>
      <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {quests.map((quest) => (
          <QuestCard
            key={quest.title}
            title={quest.title}
            description={quest.description}
            questType={quest.questType}
            rewardPoints={quest.rewardPoints}
            badgeId={quest.badgeId}
          />
        ))}
      </div>
    </div>
  );
}
