import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// PRE-TESTNET CLEANUP (item 3, closes M4): first unit tests for the env
// validation in lib/env.ts — including the M5 chain <-> Agent ID
// consistency rules that previously were only verified by a manual
// harness + negative builds.
//
// lib/env.ts parses process.env AT IMPORT TIME and throws on invalid
// config, so each case resets the module registry, sets process.env,
// then dynamically imports the module fresh.

const OFFICIAL = '0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F';
const MOCK = '0x1111111111111111111111111111111111111111';
const ZERO = '0x0000000000000000000000000000000000000000';
const GATE = '0x2222222222222222222222222222222222222222';
const QM = '0x3333333333333333333333333333333333333333';
const REP = '0x4444444444444444444444444444444444444444';
const ACH = '0x5555555555555555555555555555555555555555';

const ENV_KEYS = [
  'NEXT_PUBLIC_CHAIN_ID',
  'NEXT_PUBLIC_AGENT_ID_ADDRESS',
  'NEXT_PUBLIC_AGENT_GATE_ADDRESS',
  'NEXT_PUBLIC_QUEST_MANAGER_ADDRESS',
  'NEXT_PUBLIC_REPUTATION_ADDRESS',
  'NEXT_PUBLIC_ACHIEVEMENT_ADDRESS',
  'NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID',
] as const;

async function loadEnv(vars: Partial<Record<(typeof ENV_KEYS)[number], string>>) {
  vi.resetModules();
  for (const k of ENV_KEYS) delete process.env[k];
  for (const [k, v] of Object.entries(vars)) {
    process.env[k as (typeof ENV_KEYS)[number]] = v;
  }
  return import('./env');
}

describe('env validation', () => {
  let errorSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    // env.ts logs the validation error before throwing; silence it so
    // the expected-failure cases don't spam the test output.
    errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    errorSpy.mockRestore();
    for (const k of ENV_KEYS) delete process.env[k];
  });

  it('defaults to BSC testnet (97) with nothing deployed', async () => {
    const { env, contractsDeployed } = await loadEnv({});
    expect(env.NEXT_PUBLIC_CHAIN_ID).toBe(97);
    expect(env.NEXT_PUBLIC_AGENT_ID_ADDRESS).toBeUndefined();
    expect(contractsDeployed).toBe(false);
  });

  it('accepts mainnet (56) with the official Agent ID', async () => {
    const { env } = await loadEnv({
      NEXT_PUBLIC_CHAIN_ID: '56',
      NEXT_PUBLIC_AGENT_ID_ADDRESS: OFFICIAL,
    });
    expect(env.NEXT_PUBLIC_CHAIN_ID).toBe(56);
    expect(env.NEXT_PUBLIC_AGENT_ID_ADDRESS).toBe(OFFICIAL);
  });

  it('accepts a lowercase official address on mainnet (case-insensitive)', async () => {
    const { env } = await loadEnv({
      NEXT_PUBLIC_CHAIN_ID: '56',
      NEXT_PUBLIC_AGENT_ID_ADDRESS: OFFICIAL.toLowerCase(),
    });
    expect(env.NEXT_PUBLIC_CHAIN_ID).toBe(56);
  });

  it('M5: rejects mainnet (56) with a non-official Agent ID', async () => {
    await expect(
      loadEnv({ NEXT_PUBLIC_CHAIN_ID: '56', NEXT_PUBLIC_AGENT_ID_ADDRESS: MOCK }),
    ).rejects.toThrow('Invalid environment configuration');
  });

  it('M5: rejects testnet (97) with the official mainnet Agent ID', async () => {
    await expect(
      loadEnv({ NEXT_PUBLIC_CHAIN_ID: '97', NEXT_PUBLIC_AGENT_ID_ADDRESS: OFFICIAL }),
    ).rejects.toThrow('Invalid environment configuration');
  });

  it('accepts testnet (97) with a mock Agent ID', async () => {
    const { env } = await loadEnv({
      NEXT_PUBLIC_CHAIN_ID: '97',
      NEXT_PUBLIC_AGENT_ID_ADDRESS: MOCK,
    });
    expect(env.NEXT_PUBLIC_CHAIN_ID).toBe(97);
  });

  it('accepts any non-zero address on local Anvil (31337)', async () => {
    const { env: envMock } = await loadEnv({
      NEXT_PUBLIC_CHAIN_ID: '31337',
      NEXT_PUBLIC_AGENT_ID_ADDRESS: MOCK,
    });
    expect(envMock.NEXT_PUBLIC_CHAIN_ID).toBe(31337);
    const { env: envOfficial } = await loadEnv({
      NEXT_PUBLIC_CHAIN_ID: '31337',
      NEXT_PUBLIC_AGENT_ID_ADDRESS: OFFICIAL,
    });
    expect(envOfficial.NEXT_PUBLIC_CHAIN_ID).toBe(31337);
  });

  it('rejects unsupported chain ids', async () => {
    await expect(loadEnv({ NEXT_PUBLIC_CHAIN_ID: '1' })).rejects.toThrow(
      'Invalid environment configuration',
    );
    await expect(loadEnv({ NEXT_PUBLIC_CHAIN_ID: '137' })).rejects.toThrow(
      'Invalid environment configuration',
    );
  });

  it('rejects a non-numeric or non-integer chain id', async () => {
    await expect(loadEnv({ NEXT_PUBLIC_CHAIN_ID: 'abc' })).rejects.toThrow(
      'Invalid environment configuration',
    );
    await expect(loadEnv({ NEXT_PUBLIC_CHAIN_ID: '56.5' })).rejects.toThrow(
      'Invalid environment configuration',
    );
  });

  it('rejects the zero address for any contract address', async () => {
    await expect(loadEnv({ NEXT_PUBLIC_AGENT_ID_ADDRESS: ZERO })).rejects.toThrow(
      'Invalid environment configuration',
    );
    await expect(loadEnv({ NEXT_PUBLIC_AGENT_GATE_ADDRESS: ZERO })).rejects.toThrow(
      'Invalid environment configuration',
    );
  });

  it('rejects malformed addresses', async () => {
    await expect(loadEnv({ NEXT_PUBLIC_AGENT_ID_ADDRESS: 'not-an-address' })).rejects.toThrow(
      'Invalid environment configuration',
    );
    await expect(loadEnv({ NEXT_PUBLIC_AGENT_ID_ADDRESS: '0x1234' })).rejects.toThrow(
      'Invalid environment configuration',
    );
    await expect(
      loadEnv({ NEXT_PUBLIC_AGENT_ID_ADDRESS: '60B9262456dE011F7d15a54CdD8c48bAaa8B022F' }),
    ).rejects.toThrow('Invalid environment configuration');
  });

  it('contractsDeployed is true only when all four contracts are set', async () => {
    const all = {
      NEXT_PUBLIC_AGENT_GATE_ADDRESS: GATE,
      NEXT_PUBLIC_QUEST_MANAGER_ADDRESS: QM,
      NEXT_PUBLIC_REPUTATION_ADDRESS: REP,
      NEXT_PUBLIC_ACHIEVEMENT_ADDRESS: ACH,
    };
    const { contractsDeployed: deployed } = await loadEnv(all);
    expect(deployed).toBe(true);

    const { contractsDeployed: partial } = await loadEnv({
      NEXT_PUBLIC_AGENT_GATE_ADDRESS: GATE,
      NEXT_PUBLIC_QUEST_MANAGER_ADDRESS: QM,
      NEXT_PUBLIC_REPUTATION_ADDRESS: REP,
    });
    expect(partial).toBe(false);
  });
});

describe('env exports', () => {
  it('exposes the allowed chain ids and the official address', async () => {
    const { ALLOWED_CHAIN_IDS, OFFICIAL_AGENT_ID_ADDRESS } = await loadEnv({});
    expect([...ALLOWED_CHAIN_IDS]).toEqual([56, 97, 31337]);
    expect(OFFICIAL_AGENT_ID_ADDRESS).toBe(OFFICIAL);
  });
});
