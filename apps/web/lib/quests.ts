import { QuestType, ValidationKind, type Quest } from '@agenthub/shared';

// Launch quest catalogue (Phase 1 static preview).
// Phase 7 reads quests from QuestManager on-chain; these definitions are
// kept as the seed catalogue for the first on-chain quests AND as the
// fallback display while the contracts are not deployed yet. Points match
// the blueprint.
export const LAUNCH_QUESTS: Omit<Quest, 'id' | 'creator' | 'completions' | 'active'>[] = [
  {
    title: 'First Agent',
    description: 'Connect your wallet and verify your Agent ID to create your AGENTHUB profile.',
    questType: QuestType.OneTime,
    validationKind: ValidationKind.CheckIn,
    validator: '0x0000000000000000000000000000000000000000',
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
    validationKind: ValidationKind.CheckIn,
    validator: '0x0000000000000000000000000000000000000000',
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
    validationKind: ValidationKind.CheckIn,
    validator: '0x0000000000000000000000000000000000000000',
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
    validationKind: ValidationKind.CheckIn,
    validator: '0x0000000000000000000000000000000000000000',
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
    validationKind: ValidationKind.CheckIn,
    validator: '0x0000000000000000000000000000000000000000',
    rewardPoints: 75,
    badgeId: 4,
    startTime: 0,
    endTime: 0,
    maxCompletions: 0,
  },
];

// --- On-chain quest mapping + eligibility (Phase 7, pure functions) ---

/** Raw getQuest return shape from viem (tuple with named fields). */
export interface RawQuest {
  id: bigint;
  creator: `0x${string}`;
  title: string;
  description: string;
  questType: number;
  validationKind: number;
  validator: `0x${string}`;
  rewardPoints: bigint;
  badgeId: bigint;
  startTime: bigint;
  endTime: bigint;
  maxCompletions: bigint;
  completions: bigint;
  active: boolean;
}

const QUEST_TYPES = [
  QuestType.DailyCheckIn,
  QuestType.OneTime,
  QuestType.Weekly,
  QuestType.Community,
] as const;

const VALIDATION_KINDS = [
  ValidationKind.CheckIn,
  ValidationKind.OnChain,
  ValidationKind.Attested,
] as const;

/** Map a raw on-chain Quest struct to the shared Quest type. */
export function mapQuest(raw: RawQuest): Quest {
  const questType = QUEST_TYPES[raw.questType];
  const validationKind = VALIDATION_KINDS[raw.validationKind];
  if (!questType || !validationKind) {
    throw new Error(`unknown quest enums: type=${raw.questType} kind=${raw.validationKind}`);
  }
  return {
    id: Number(raw.id),
    creator: raw.creator,
    title: raw.title,
    description: raw.description,
    questType,
    validationKind,
    validator: raw.validator,
    rewardPoints: Number(raw.rewardPoints),
    badgeId: Number(raw.badgeId),
    startTime: Number(raw.startTime),
    endTime: Number(raw.endTime),
    maxCompletions: Number(raw.maxCompletions),
    completions: Number(raw.completions),
    active: raw.active,
  };
}

export interface QuestState {
  completed: boolean;
  /** Unix timestamp when the account may next complete (0 = now). */
  nextCompletionAt: number;
}

export interface Eligibility {
  /** True when the plain completeQuest path is available right now. */
  canComplete: boolean;
  /** True when the attestation path is the way in (Attested quest). */
  needsAttestation: boolean;
  /** Human-readable reason when canComplete is false. */
  reason: string | null;
}

/**
 * Pure eligibility check. Mirrors the contract's checks (gate, active,
 * window, cap, duplicate, cooldown) so the UI disables the button with
 * the right reason — the contract remains the final authority and may
 * still revert (e.g. a race on the cap).
 */
export function questEligibility(
  quest: Quest,
  state: QuestState,
  nowSeconds: number,
  isHolder: boolean | null,
): Eligibility {
  if (isHolder === false) {
    return { canComplete: false, needsAttestation: false, reason: 'Requires an Agent ID' };
  }
  if (!quest.active) {
    return { canComplete: false, needsAttestation: false, reason: 'Quest is deactivated' };
  }
  if (nowSeconds < quest.startTime) {
    return { canComplete: false, needsAttestation: false, reason: 'Quest has not started yet' };
  }
  if (nowSeconds > quest.endTime) {
    return { canComplete: false, needsAttestation: false, reason: 'Quest has ended' };
  }
  if (quest.maxCompletions > 0 && quest.completions >= quest.maxCompletions) {
    return { canComplete: false, needsAttestation: false, reason: 'Quest is full' };
  }
  if (
    (quest.questType === QuestType.OneTime || quest.questType === QuestType.Community) &&
    state.completed
  ) {
    return { canComplete: false, needsAttestation: false, reason: 'Already completed' };
  }
  if (state.nextCompletionAt > nowSeconds) {
    return {
      canComplete: false,
      needsAttestation: false,
      reason: `Cooldown until ${new Date(state.nextCompletionAt * 1000).toLocaleString()}`,
    };
  }
  if (quest.validationKind === ValidationKind.Attested) {
    return {
      canComplete: false,
      needsAttestation: true,
      reason: 'Needs a verifier attestation — submit yours below',
    };
  }
  return { canComplete: true, needsAttestation: false, reason: null };
}

/** Honest validation-kind label (QUEST_VALIDATION_DESIGN.md §3). */
export function validationKindLabel(kind: ValidationKind): string {
  switch (kind) {
    case ValidationKind.CheckIn:
      return 'Check-in — no external proof required';
    case ValidationKind.OnChain:
      return 'On-chain validation';
    case ValidationKind.Attested:
      return 'Verified by an AGENTHUB verifier';
  }
}
