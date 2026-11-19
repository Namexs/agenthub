import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { QUEST_MANAGER_ABI } from './QuestManager';

// PHASE 6 (R-010): ABI parity — the committed frontend ABI must match
// the Foundry build. The full deep-equal check runs only when a forge
// build exists (packages/contracts/out/ is gitignored build output, so
// CI's web job — which does not run forge — skips it, exactly like the
// anvil integration test skips without a deployment). The structural
// checks on the COMMITTED ABI always run: they pin the threshold
// (M-of-N) call shape the frontend codes against.

const here = dirname(fileURLToPath(import.meta.url));
const artifactPath = join(
  here,
  '..',
  '..',
  '..',
  '..',
  'packages',
  'contracts',
  'out',
  'QuestManager.sol',
  'QuestManager.json',
);
const buildExists = existsSync(artifactPath);

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

describe.skipIf(!buildExists)('committed QuestManager ABI matches the Foundry build', () => {
  it('deep-equals the artifact ABI (regenerate with export-abis.mjs on drift)', () => {
    const artifact = JSON.parse(readFileSync(artifactPath, 'utf8')) as {
      abi: unknown;
    };
    expect(QUEST_MANAGER_ABI).toEqual(artifact.abi);
  });
});
