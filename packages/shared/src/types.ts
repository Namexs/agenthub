// AGENTHUB shared domain types. Mirrors the on-chain structs in
// packages/contracts/src/interfaces (IQuestManager, IReputation, IAchievement).

export type Address = `0x${string}`;

export enum QuestType {
  DailyCheckIn = 'daily-checkin',
  OneTime = 'one-time',
  Weekly = 'weekly',
  Community = 'community',
}

export interface Quest {
  id: number;
  creator: Address;
  title: string;
  description: string;
  questType: QuestType;
  rewardPoints: number;
  /** 0 = no badge awarded. */
  badgeId: number;
  startTime: number;
  endTime: number;
  maxCompletions: number;
  completions: number;
  active: boolean;
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

export interface ContractAddresses {
  agentId: Address;
  agentGate: Address | null;
  questManager: Address | null;
  reputation: Address | null;
  achievement: Address | null;
}
