'use client';

import { QuestCard } from '@/components/QuestCard';
import { QuestCardLive } from '@/components/QuestCardLive';
import { useQuests } from '@/hooks/useQuests';
import { LAUNCH_QUESTS } from '@/lib/quests';

export default function QuestsPage() {
  const { quests, deployed, isLoading, error } = useQuests();

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Quests</h1>
      <p className="mt-2 text-sm text-ink-400">
        {deployed
          ? 'Live quests from QuestManager — every completion is an on-chain transaction.'
          : 'Launch catalogue preview — these quests go on-chain with the testnet deploy.'}
      </p>

      {deployed ? (
        isLoading ? (
          <p className="mt-8 text-sm text-ink-400">Loading quests from QuestManager…</p>
        ) : error ? (
          <p className="mt-8 text-sm text-red-300">Could not load quests from the chain: {error}</p>
        ) : quests.length === 0 ? (
          <p className="mt-8 text-sm text-ink-400">
            No quests on-chain yet — the first quests are created after the deploy.
          </p>
        ) : (
          <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {quests.map((quest) => (
              <QuestCardLive key={quest.id} quest={quest} />
            ))}
          </div>
        )
      ) : (
        <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {LAUNCH_QUESTS.map((quest) => (
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
      )}
    </div>
  );
}
