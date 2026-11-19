import { z } from 'zod';

// Environment validation (client-safe: only NEXT_PUBLIC_* vars).
// Phase 1: contract addresses are optional — the app renders gracefully
// ("not deployed yet") until Phase 2 deploys to BSC testnet. No secret is
// ever read here; DEPLOYER_PRIVATE_KEY / BSCSCAN_API_KEY live only in
// forge scripts and CI secrets, never in the browser bundle.

const addressSchema = z
  .string()
  .regex(/^0x[a-fA-F0-9]{40}$/, 'must be a 0x EVM address')
  .optional();

const envSchema = z.object({
  NEXT_PUBLIC_CHAIN_ID: z.coerce.number().int().default(97),
  NEXT_PUBLIC_AGENT_ID_ADDRESS: addressSchema,
  NEXT_PUBLIC_AGENT_GATE_ADDRESS: addressSchema,
  NEXT_PUBLIC_QUEST_MANAGER_ADDRESS: addressSchema,
  NEXT_PUBLIC_REPUTATION_ADDRESS: addressSchema,
  NEXT_PUBLIC_ACHIEVEMENT_ADDRESS: addressSchema,
  NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID: z.string().optional(),
});

const parsed = envSchema.safeParse({
  NEXT_PUBLIC_CHAIN_ID: process.env.NEXT_PUBLIC_CHAIN_ID,
  NEXT_PUBLIC_AGENT_ID_ADDRESS: process.env.NEXT_PUBLIC_AGENT_ID_ADDRESS || undefined,
  NEXT_PUBLIC_AGENT_GATE_ADDRESS: process.env.NEXT_PUBLIC_AGENT_GATE_ADDRESS || undefined,
  NEXT_PUBLIC_QUEST_MANAGER_ADDRESS: process.env.NEXT_PUBLIC_QUEST_MANAGER_ADDRESS || undefined,
  NEXT_PUBLIC_REPUTATION_ADDRESS: process.env.NEXT_PUBLIC_REPUTATION_ADDRESS || undefined,
  NEXT_PUBLIC_ACHIEVEMENT_ADDRESS: process.env.NEXT_PUBLIC_ACHIEVEMENT_ADDRESS || undefined,
  NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID:
    process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || undefined,
});

if (!parsed.success) {
  // Fail loudly in development; in production builds Next inlines env at
  // build time, so a bad value here means a misconfigured deploy, not a
  // runtime secret leak.
  console.error('Invalid environment configuration:', parsed.error.flatten().fieldErrors);
  throw new Error('Invalid environment configuration — see docs/DEPLOYMENT.md');
}

export const env = parsed.data;

/** True once the full contract suite is deployed on the active chain. */
export const contractsDeployed =
  Boolean(env.NEXT_PUBLIC_AGENT_GATE_ADDRESS) &&
  Boolean(env.NEXT_PUBLIC_QUEST_MANAGER_ADDRESS) &&
  Boolean(env.NEXT_PUBLIC_REPUTATION_ADDRESS) &&
  Boolean(env.NEXT_PUBLIC_ACHIEVEMENT_ADDRESS);
