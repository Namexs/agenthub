// AGENTHUB shared constants — chain + contract address registry.
//
// MAINNET IS THE COMPETITION TARGET. Testnet (chainId 97) is staging only.
// The official Agent ID contract exists ONLY on BSC mainnet (chainId 56).
// On testnet/local, deploy MockAgentId (packages/contracts/src/mocks) and
// use ITS address instead. Never hardcode the mainnet address as a testnet
// address — the two environments are deliberately different.

export const CHAINS = {
  BSC_MAINNET: 56,
  BSC_TESTNET: 97,
  LOCAL_ANVIL: 31337,
} as const;

/** Official Binance Agent ID contract (SPACE ID Agent ID, ERC-721, soulbound). */
export const AGENT_ID_MAINNET_ADDRESS = '0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F' as const;

/** Placeholder until the MockAgentId is deployed on testnet (Phase 2). */
export const AGENT_ID_TESTNET_ADDRESS_PLACEHOLDER =
  '0x0000000000000000000000000000000000000000' as const;

/** BSCScan explorers. */
export const EXPLORERS = {
  56: 'https://bscscan.com',
  97: 'https://testnet.bscscan.com',
  31337: '',
} as const;

/** Reputation level thresholds (points). Level N requires threshold[N-1] points. */
export const REPUTATION_LEVEL_THRESHOLDS = [0, 100, 300, 700, 1500] as const;

/** Daily check-in cooldown (seconds). */
export const DAILY_CHECKIN_COOLDOWN_SECONDS = 24 * 60 * 60;
