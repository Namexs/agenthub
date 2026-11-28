import { z } from 'zod';

// Environment validation (client-safe: only NEXT_PUBLIC_* vars).
// Phase 1: contract addresses are optional — the app renders gracefully
// ("not deployed yet") until Phase 2 deploys to BSC testnet. No secret is
// ever read here; DEPLOYER_PRIVATE_KEY / BSCSCAN_API_KEY live only in
// forge scripts and CI secrets, never in the browser bundle.
//
// M5 (security phase): chain <-> Agent ID consistency is enforced here.
// A mainnet build pointing at a mock Agent ID (or a testnet build pointing
// at the official mainnet contract) is a misconfiguration that must fail
// loudly at startup, not silently render the wrong network's data.

/** Chains the app may run on. 56 = BSC mainnet, 97 = BSC testnet, 31337 = local Anvil/fork. */
export const ALLOWED_CHAIN_IDS = [56, 97, 31337] as const;

/** Official Binance Agent ID contract on BSC mainnet (chain 56). */
export const OFFICIAL_AGENT_ID_ADDRESS = '0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

const addressSchema = z
  .string()
  .regex(/^0x[a-fA-F0-9]{40}$/, 'must be a 0x EVM address')
  .refine((a) => a.toLowerCase() !== ZERO_ADDRESS, 'zero address is not allowed')
  .optional();

const envSchema = z
  .object({
    NEXT_PUBLIC_CHAIN_ID: z.coerce
      .number()
      .int()
      .refine(
        (id): id is (typeof ALLOWED_CHAIN_IDS)[number] =>
          (ALLOWED_CHAIN_IDS as readonly number[]).includes(id),
        `must be one of ${ALLOWED_CHAIN_IDS.join(', ')}`,
      )
      .default(97),
    NEXT_PUBLIC_AGENT_ID_ADDRESS: addressSchema,
    NEXT_PUBLIC_AGENT_GATE_ADDRESS: addressSchema,
    NEXT_PUBLIC_QUEST_MANAGER_ADDRESS: addressSchema,
    NEXT_PUBLIC_REPUTATION_ADDRESS: addressSchema,
    NEXT_PUBLIC_ACHIEVEMENT_ADDRESS: addressSchema,
    NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID: z.string().optional(),
    // Keyed BSC testnet RPC (NodeReal MegaNode, free tier) that serves
    // eth_getLogs over the 50,000-block chunks useContractLogs uses.
    // The public dataseed rejects ALL getLogs and publicnode is
    // Cloudflare-blocked / silently drops old logs (ALICE's Nov 23
    // events missing from the leaderboard, verified 2026-11-28).
    // Alchemy free does NOT fit: getLogs capped at 10 blocks/query.
    // Unset = fall back to dataseed + publicnode. The key is a
    // read-only RPC key, never a signing key; NEXT_PUBLIC_* is inlined
    // into the browser bundle by design.
    NEXT_PUBLIC_BSC_TESTNET_RPC_URL: z.string().url().optional(),
    // Block the contracts were deployed at. Event-based features
    // (leaderboard, history, badges) query logs from this block — never
    // from genesis, which public RPCs refuse over large ranges. Unset =
    // event features show "not configured" instead of guessing.
    NEXT_PUBLIC_DEPLOY_BLOCK: z.coerce.number().int().nonnegative().optional(),
  })
  .superRefine((data, ctx) => {
    const agentId = data.NEXT_PUBLIC_AGENT_ID_ADDRESS;
    if (!agentId) return; // unset = not deployed yet; nothing to cross-check
    const isOfficial = agentId.toLowerCase() === OFFICIAL_AGENT_ID_ADDRESS.toLowerCase();
    if (data.NEXT_PUBLIC_CHAIN_ID === 56 && !isOfficial) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['NEXT_PUBLIC_AGENT_ID_ADDRESS'],
        message: `on BSC mainnet (56) the Agent ID MUST be the official contract ${OFFICIAL_AGENT_ID_ADDRESS}`,
      });
    }
    if (data.NEXT_PUBLIC_CHAIN_ID === 97 && isOfficial) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['NEXT_PUBLIC_AGENT_ID_ADDRESS'],
        message:
          'on BSC testnet (97) the Agent ID MUST NOT be the official mainnet contract. Use the deployed MockAgentId',
      });
    }
    // Chain 31337 (local Anvil/fork): any non-zero address is allowed.
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
  NEXT_PUBLIC_BSC_TESTNET_RPC_URL:
    process.env.NEXT_PUBLIC_BSC_TESTNET_RPC_URL || undefined,
  NEXT_PUBLIC_DEPLOY_BLOCK: process.env.NEXT_PUBLIC_DEPLOY_BLOCK || undefined,
});

if (!parsed.success) {
  // Fail loudly in development; in production builds Next inlines env at
  // build time, so a bad value here means a misconfigured deploy, not a
  // runtime secret leak.
  console.error('Invalid environment configuration:', parsed.error.flatten().fieldErrors);
  throw new Error('Invalid environment configuration. See docs/DEPLOYMENT.md.');
}

export const env = parsed.data;

/** True once the full contract suite is deployed on the active chain. */
export const contractsDeployed =
  Boolean(env.NEXT_PUBLIC_AGENT_GATE_ADDRESS) &&
  Boolean(env.NEXT_PUBLIC_QUEST_MANAGER_ADDRESS) &&
  Boolean(env.NEXT_PUBLIC_REPUTATION_ADDRESS) &&
  Boolean(env.NEXT_PUBLIC_ACHIEVEMENT_ADDRESS);
