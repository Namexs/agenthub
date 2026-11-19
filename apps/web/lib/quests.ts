import { QuestType, type Quest } from '@agenthub/shared';

// Launch quest catalogue (Phase 1 static preview).
// Phase 2 reads quests from QuestManager on-chain; these definitions become
// the seed data for the first on-chain quests. Points match the blueprint.
export const LAUNCH_QUESTS: Omit<Quest, 'id' | 'creator' | 'completions' | 'active'>[] = [
  {
    title: 'First Agent',
    description: 'Connect your wallet and verify your Agent ID to create your AGENTHUB profile.',
    questType: QuestType.OneTime,
    rewardPoints: 50,
    badgeId: 1,
    startTime: 0,
    endTime: 0,
    maxCompletions: 0,
  },
  {
    title: 'Daily Check-in',
    description: 'Check in once a day to keep your streak alive. Cooldown: 24 hours.',
    questType: QuestType.DailyCheckIn,
    rewardPoints: 10,
    badgeId: 0,
    startTime: 0,
    endTime: 0,
    maxCompletions: 0,
  },
  {
    title: 'Quest Explorer',
    description: 'Complete your first quest on AGENTHUB.',
    questType: QuestType.OneTime,
    rewardPoints: 25,
    badgeId: 2,
    startTime: 0,
    endTime: 0,
    maxCompletions: 0,
  },
  {
    title: 'Community Builder',
    description: 'Join and complete a community campaign quest.',
    questType: QuestType.Community,
    rewardPoints: 40,
    badgeId: 3,
    startTime: 0,
    endTime: 0,
    maxCompletions: 0,
  },
  {
    title: 'Reputation Builder',
    description: 'Reach 100 reputation points from validated quests.',
    questType: QuestType.OneTime,
    rewardPoints: 75,
    badgeId: 4,
    startTime: 0,
    endTime: 0,
    maxCompletions: 0,
  },
];
