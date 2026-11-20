import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ACHIEVEMENT_ABI } from './Achievement';
import { AGENT_GATE_ABI } from './AgentGate';
import { QUEST_MANAGER_ABI } from './QuestManager';
import { REPUTATION_ABI } from './Reputation';
import { QUEST_MANAGER_READ_ABI } from '../contracts';

// PHASE 6 (R-010) + PHASE 8 (PH7-M07/M08): ABI parity — the committed
// frontend ABIs must match the Foundry build. The full deep-equal check
// runs only when a forge build exists (packages/contracts/out/ is
// gitignored build output, so a local checkout without a build skips it,
// exactly like the anvil integration test skips without a deployment).
// In CI the web job runs `forge build` before vitest (see
// .github/workflows/ci.yml), so the deep-equal checks RUN there —
// PH7-M07 was that they never did. PH7-M08: the deep-equal now covers
// ALL FOUR contracts, not just QuestManager. The structural checks on
// the COMMITTED QuestManager ABI always run: they pin the threshold
// (M-of-N) call shape the frontend codes against.

const here = dirname(fileURLToPath(import.meta.url));

const CONTRACTS = [
  { name: 'AgentGate', abi: AGENT_GATE_ABI },
  { name: 'QuestManager', abi: QUEST_MANAGER_ABI },
  { name: 'Reputation', abi: REPUTATION_ABI },
  { name: 'Achievement', abi: ACHIEVEMENT_ABI },
] as const;

function artifactPath(name: string): string {
  return join(
    here,
    '..',
    '..',
    '..',
    '..',
    'packages',
    'contracts',
    'out',
    `${name}.sol`,
    `${name}.json`,
  );
}

function findFunction(name: string) {
  const entry = (QUEST_MANAGER_ABI as unknown as { type: string; name?: string }[]).find(
    (e) => e.type === 'function' && e.name === name,
  );
  if (!entry) throw new Error(`function ${name} not in committed QuestManager ABI`);
  return entry as unknown as {
    inputs: { name: string; type: string; components?: { name: string; type: string }[] }[];
    outputs?: { components?: { name: string; type: string }[] }[];
  };
}

describe('committed QuestManager ABI (threshold shape)', () => {
  it('createQuest takes 11 params, attestationThreshold (uint8) last', () => {
    const fn = findFunction('createQuest');
    expect(fn.inputs).toHaveLength(11);
    expect(fn.inputs[10]).toMatchObject({ name: 'attestationThreshold', type: 'uint8' });
  });

  it('completeQuestWithAttestation takes a bytes[] signatures array', () => {
    const fn = findFunction('completeQuestWithAttestation');
    expect(fn.inputs.map((i) => i.type)).toEqual(['uint256', 'uint256', 'bytes[]']);
    expect(fn.inputs[2]?.name).toBe('signatures');
  });

  it('getQuest returns attestationThreshold in the Quest struct', () => {
    const fn = findFunction('getQuest');
    const components = fn.outputs?.[0]?.components ?? [];
    expect(components.map((c) => `${c.name}:${c.type}`)).toContain(
      'attestationThreshold:uint8',
    );
  });

  it('declares the four threshold errors', () => {
    const errors = (QUEST_MANAGER_ABI as unknown as { type: string; name?: string }[])
      .filter((e) => e.type === 'error')
      .map((e) => e.name);
    for (const name of [
      'DuplicateAttestationSigner',
      'InsufficientAttestations',
      'TooManyAttestationSignatures',
      'AttestationThresholdOutOfRange',
    ]) {
      expect(errors).toContain(name);
    }
  });
});

// One deep-equal per contract, each skipped independently when its own
// artifact is missing (a partial build still checks what it built).
for (const { name, abi } of CONTRACTS) {
  const path = artifactPath(name);
  describe.skipIf(!existsSync(path))(
    `committed ${name} ABI matches the Foundry build`,
    () => {
      it('deep-equals the artifact ABI (regenerate with export-abis.mjs on drift)', () => {
        const artifact = JSON.parse(readFileSync(path, 'utf8')) as {
          abi: unknown;
        };
        expect(abi).toEqual(artifact.abi);
      });
    },
  );
}

// PHASE 8: the minimal read ABI used by useQuests (see lib/contracts.ts)
// must stay a verbatim subset of the committed full QuestManager ABI —
// the full 99-entry ABI breaks wagmi type inference (TS2589), so the
// hook reads through this 4-entry subset instead. Any drift fails here.
describe('QUEST_MANAGER_READ_ABI is a verbatim subset of QUEST_MANAGER_ABI', () => {
  it('has exactly the four read functions useQuests needs', () => {
    expect(QUEST_MANAGER_READ_ABI.map((e) => e.name)).toEqual([
      'questCount',
      'getQuest',
      'hasCompleted',
      'nextCompletionAt',
    ]);
  });

  it.each(['questCount', 'getQuest', 'hasCompleted', 'nextCompletionAt'])(
    '%s deep-equals its entry in the full committed ABI',
    (name) => {
      const full = (QUEST_MANAGER_ABI as unknown as { type: string; name?: string }[]).find(
        (e) => e.type === 'function' && e.name === name,
      );
      const minimal = QUEST_MANAGER_READ_ABI.find((e) => e.name === name);
      expect(minimal).toBeDefined();
      expect(full).toBeDefined();
      expect(minimal).toEqual(full);
    },
  );
});
