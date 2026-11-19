// AGENTHUB shared domain types. Mirrors the on-chain structs in
// packages/contracts/src/interfaces (IQuestManager, IReputation, IAchievement).

export type Address = `0x${string}`;

export enum QuestType {
  DailyCheckIn = 'daily-checkin',
  OneTime = 'one-time',
  Weekly = 'weekly',
  Community = 'community',
}

/** How a quest's completion is proven (FINAL REMEDIATION, Phase 7). */
export enum ValidationKind {
  CheckIn = 'check-in',
  OnChain = 'on-chain',
  Attested = 'attested',
}

export interface Quest {
  id: number;
  creator: Address;
  title: string;
  description: string;
  questType: QuestType;
  /** What the completion proves. The UI must render this honestly:
   * CheckIn is never "verified" — see QUEST_VALIDATION_DESIGN.md §3. */
  validationKind: ValidationKind;
  /** OnChain quests only: the validator contract. Zero address otherwise. */
  validator: Address;
  rewardPoints: number;
  /** 0 = no badge awarded. */
  badgeId: number;
  startTime: number;
  endTime: number;
  maxCompletions: number;
  completions: number;
  active: boolean;
  /**
   * PHASE 6 (R-010): minimum number of DISTINCT VERIFIER_ROLE signatures
   * an attestation must carry for this quest (1–3, set at creation,
   * immutable). Only Attested quests enforce it.
   */
  attestationThreshold: number;
}

export interface Badge {
  badgeId: number;
  name: string;
  description: string;
  tokenURI: string;
}

export interface Profile {
  address: Address;
  isAgentHolder: boolean;
  points: number;
  level: number;
  badges: Badge[];
  questsCompleted: number;
}

export interface LeaderboardEntry {
  rank: number;
  address: Address;
  points: number;
  level: number;
  questsCompleted: number;
}

/** One row of the on-chain activity history (built from contract events). */
export type TxHistoryKind = 'quest' | 'points' | 'badge' | 'attestation';

export interface TxHistoryEntry {
  kind: TxHistoryKind;
  /** Quest id for quest/points/attestation entries. */
  questId?: number;
  points?: number;
  badgeId?: number;
  tokenId?: number;
  /** Attestation entries only: the verifier who signed. */
  signer?: Address;
  hash: `0x${string}`;
  blockNumber: number;
  /** Log index within the block (tiebreaker for ordering). */
  logIndex: number;
}

export interface ContractAddresses {
  agentId: Address;
  agentGate: Address | null;
  questManager: Address | null;
  reputation: Address | null;
  achievement: Address | null;
}
