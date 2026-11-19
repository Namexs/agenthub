import { describe, it, expect } from 'vitest';
import { QuestType, ValidationKind, type Quest } from '@agenthub/shared';
import {
  mapQuest,
  questEligibility,
  validationKindLabel,
  type QuestState,
  type RawQuest,
} from './quests';

// PHASE 8: unit tests for the pure quest mapping + eligibility logic.
// These functions carry the quest-flow decisions (the hooks are thin
// wrappers over wagmi reads), so every branch is pinned here.
//
// Note on endTime: the contract's createQuest requires
// startTime < endTime and endTime > block.timestamp, so an on-chain
// quest can never have endTime 0 — the `now > endTime` check in
// questEligibility matches the contract exactly for every real quest.
// (The static LAUNCH_QUESTS catalogue uses 0, but it is display-only
// and never passes through questEligibility.)

const ZERO = '0x0000000000000000000000000000000000000000' as `0x${string}`;
const CREATOR = '0x1111111111111111111111111111111111111111' as `0x${string}`;
const VALIDATOR = '0x2222222222222222222222222222222222222222' as `0x${string}`;

function rawQuest(overrides: Partial<RawQuest> = {}): RawQuest {
  return {
    id: 1n,
    creator: CREATOR,
    title: 'First Agent',
    description: 'Verify your Agent ID.',
    questType: 1, // OneTime
    validationKind: 0, // CheckIn
    validator: ZERO,
    rewardPoints: 50n,
    badgeId: 1n,
    startTime: 1000n,
    endTime: 2000n,
    maxCompletions: 0n,
    completions: 0n,
    active: true,
    attestationThreshold: 1,
    ...overrides,
  };
}

function quest(overrides: Partial<Quest> = {}): Quest {
  return {
    id: 1,
    creator: CREATOR,
    title: 'First Agent',
    description: 'Verify your Agent ID.',
    questType: QuestType.OneTime,
    validationKind: ValidationKind.CheckIn,
    validator: ZERO,
    rewardPoints: 50,
    badgeId: 1,
    startTime: 1000,
    endTime: 2000,
    maxCompletions: 0,
    completions: 0,
    active: true,
    attestationThreshold: 1,
    ...overrides,
  };
}

const OPEN_STATE: QuestState = { completed: false, nextCompletionAt: 0 };
const NOW = 1500;

describe('mapQuest', () => {
  it('maps every field of a raw getQuest struct', () => {
    const mapped = mapQuest(
      rawQuest({
        id: 7n,
        questType: 3,
        validationKind: 2,
        validator: VALIDATOR,
        rewardPoints: 120n,
        badgeId: 4n,
        startTime: 500n,
        endTime: 9000n,
        maxCompletions: 10n,
        completions: 3n,
      }),
    );
    expect(mapped).toEqual({
      id: 7,
      creator: CREATOR,
      title: 'First Agent',
      description: 'Verify your Agent ID.',
      questType: QuestType.Community,
      validationKind: ValidationKind.Attested,
      validator: VALIDATOR,
      rewardPoints: 120,
      badgeId: 4,
      startTime: 500,
      endTime: 9000,
      maxCompletions: 10,
      completions: 3,
      active: true,
      attestationThreshold: 1,
    });
  });

  it('maps the attestationThreshold of a threshold quest (Phase 6)', () => {
    expect(mapQuest(rawQuest({ attestationThreshold: 2 })).attestationThreshold).toBe(2);
    expect(mapQuest(rawQuest({ attestationThreshold: 3 })).attestationThreshold).toBe(3);
  });

  it('maps all quest-type and validation-kind enum numbers', () => {
    expect(mapQuest(rawQuest({ questType: 0 })).questType).toBe(QuestType.DailyCheckIn);
    expect(mapQuest(rawQuest({ questType: 1 })).questType).toBe(QuestType.OneTime);
    expect(mapQuest(rawQuest({ questType: 2 })).questType).toBe(QuestType.Weekly);
    expect(mapQuest(rawQuest({ questType: 3 })).questType).toBe(QuestType.Community);
    expect(mapQuest(rawQuest({ validationKind: 0 })).validationKind).toBe(ValidationKind.CheckIn);
    expect(mapQuest(rawQuest({ validationKind: 1 })).validationKind).toBe(ValidationKind.OnChain);
    expect(mapQuest(rawQuest({ validationKind: 2 })).validationKind).toBe(ValidationKind.Attested);
  });

  it('throws on an unknown quest type', () => {
    expect(() => mapQuest(rawQuest({ questType: 9 }))).toThrow('unknown quest enums');
  });

  it('throws on an unknown validation kind', () => {
    expect(() => mapQuest(rawQuest({ validationKind: 9 }))).toThrow('unknown quest enums');
  });
});

describe('questEligibility', () => {
  it('allows an open CheckIn quest for a holder', () => {
    expect(questEligibility(quest(), OPEN_STATE, NOW, true)).toEqual({
      canComplete: true,
      needsAttestation: false,
      reason: null,
    });
  });

  it('allows an open OnChain quest for a holder', () => {
    const q = quest({ validationKind: ValidationKind.OnChain, validator: VALIDATOR });
    expect(questEligibility(q, OPEN_STATE, NOW, true).canComplete).toBe(true);
  });

  it('blocks a non-holder with the Agent ID reason', () => {
    expect(questEligibility(quest(), OPEN_STATE, NOW, false)).toEqual({
      canComplete: false,
      needsAttestation: false,
      reason: 'Requires an Agent ID',
    });
  });

  it('does not block while holder status is still unknown (null)', () => {
    // isHolder null = check pending; the button stays enabled and the
    // contract is the final authority. Blocking here would flash a
    // false "Requires an Agent ID" on every page load.
    expect(questEligibility(quest(), OPEN_STATE, NOW, null).canComplete).toBe(true);
  });

  it('blocks a deactivated quest', () => {
    expect(questEligibility(quest({ active: false }), OPEN_STATE, NOW, true).reason).toBe(
      'Quest is deactivated',
    );
  });

  it('blocks before the start time', () => {
    expect(questEligibility(quest(), OPEN_STATE, 999, true).reason).toBe(
      'Quest has not started yet',
    );
  });

  it('allows completion exactly at the start time', () => {
    expect(questEligibility(quest(), OPEN_STATE, 1000, true).canComplete).toBe(true);
  });

  it('blocks after the end time', () => {
    expect(questEligibility(quest(), OPEN_STATE, 2001, true).reason).toBe('Quest has ended');
  });

  it('allows completion exactly at the end time', () => {
    expect(questEligibility(quest(), OPEN_STATE, 2000, true).canComplete).toBe(true);
  });

  it('blocks when the cap is reached', () => {
    const q = quest({ maxCompletions: 5, completions: 5 });
    expect(questEligibility(q, OPEN_STATE, NOW, true).reason).toBe('Quest is full');
  });

  it('allows completion one below the cap', () => {
    const q = quest({ maxCompletions: 5, completions: 4 });
    expect(questEligibility(q, OPEN_STATE, NOW, true).canComplete).toBe(true);
  });

  it('does not treat maxCompletions 0 as a cap', () => {
    const q = quest({ maxCompletions: 0, completions: 999 });
    expect(questEligibility(q, OPEN_STATE, NOW, true).canComplete).toBe(true);
  });

  it('blocks an already-completed OneTime quest', () => {
    const state: QuestState = { completed: true, nextCompletionAt: 0 };
    expect(questEligibility(quest(), state, NOW, true).reason).toBe('Already completed');
  });

  it('blocks an already-completed Community quest', () => {
    const q = quest({ questType: QuestType.Community });
    const state: QuestState = { completed: true, nextCompletionAt: 0 };
    expect(questEligibility(q, state, NOW, true).reason).toBe('Already completed');
  });

  it('allows a repeatable DailyCheckIn quest after a past completion', () => {
    const q = quest({ questType: QuestType.DailyCheckIn });
    const state: QuestState = { completed: true, nextCompletionAt: 0 };
    expect(questEligibility(q, state, NOW, true).canComplete).toBe(true);
  });

  it('allows a repeatable Weekly quest after a past completion', () => {
    const q = quest({ questType: QuestType.Weekly });
    const state: QuestState = { completed: true, nextCompletionAt: 0 };
    expect(questEligibility(q, state, NOW, true).canComplete).toBe(true);
  });

  it('blocks during cooldown and names the cooldown', () => {
    const state: QuestState = { completed: false, nextCompletionAt: NOW + 3600 };
    const result = questEligibility(quest(), state, NOW, true);
    expect(result.canComplete).toBe(false);
    expect(result.reason).toMatch(/^Cooldown until /);
  });

  it('allows completion once the cooldown has passed', () => {
    const state: QuestState = { completed: false, nextCompletionAt: NOW };
    expect(questEligibility(quest(), state, NOW, true).canComplete).toBe(true);
  });

  it('routes an Attested quest to the attestation path, not the plain button', () => {
    const q = quest({ validationKind: ValidationKind.Attested });
    expect(questEligibility(q, OPEN_STATE, NOW, true)).toEqual({
      canComplete: false,
      needsAttestation: true,
      reason: 'Needs a verifier attestation — submit yours below',
    });
  });

  it('checks holder status before quest status (non-holder + deactivated)', () => {
    const q = quest({ active: false });
    expect(questEligibility(q, OPEN_STATE, NOW, false).reason).toBe('Requires an Agent ID');
  });
});

describe('validationKindLabel', () => {
  it('never calls a CheckIn quest "verified"', () => {
    expect(validationKindLabel(ValidationKind.CheckIn)).toBe(
      'Check-in — no external proof required',
    );
    expect(validationKindLabel(ValidationKind.CheckIn)).not.toMatch(/verif/i);
  });

  it('labels OnChain and Attested honestly', () => {
    expect(validationKindLabel(ValidationKind.OnChain)).toBe('On-chain validation');
    expect(validationKindLabel(ValidationKind.Attested)).toBe('Verified by an AGENTHUB verifier');
  });
});
