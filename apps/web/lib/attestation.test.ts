import { describe, it, expect } from 'vitest';
import { privateKeyToAccount } from 'viem/accounts';
import {
  ATTESTATION_DOMAIN_NAME,
  ATTESTATION_DOMAIN_VERSION,
  ATTESTATION_TYPES,
  MAX_ATTESTATION_LIFETIME_SECONDS,
  MAX_ATTESTATION_SIGNATURES,
  checkAttestation,
  checkAttestations,
  recoverAttestationSigner,
  type AttestationInput,
} from './attestation';

// PHASE 8: unit tests for the client-side EIP-712 attestation helpers.
// Signatures are REAL: signed with viem over the same domain/types the
// contract verifies, so recovery is exercised end-to-end (minus the
// chain). The on-chain VERIFIER_ROLE check is NOT part of these pure
// functions — it lives in useAttestation and is covered by the hook
// tests (hooks/hooks.test.tsx).
//
// Test keys are the public Anvil dev keys (never real funds).

const VERIFIER_KEY = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d' as const; // 0x7099…
const VERIFIER = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8' as const;
// PHASE 6 (R-010): second verifier key (anvil account #2, bob) and a
// synthetic third key — its address is derived, never hardcoded.
const VERIFIER2_KEY = '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a' as const;
const VERIFIER2 = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC' as const;
const VERIFIER3_KEY = '0x3333333333333333333333333333333333333333333333333333333333333333' as const;
const VERIFIER3 = privateKeyToAccount(VERIFIER3_KEY).address;
const ALICE = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' as const;
const QUEST_MANAGER = '0x5FbDB2315678afecb367f032d93F642f64180aa3' as const;
const CHAIN_ID = 31337;
const NOW = 1_700_000_000;

async function signAttestation(
  input: Omit<AttestationInput, 'signature'>,
  key: `0x${string}` = VERIFIER_KEY,
): Promise<`0x${string}`> {
  const account = privateKeyToAccount(key);
  return account.signTypedData({
    domain: {
      name: ATTESTATION_DOMAIN_NAME,
      version: ATTESTATION_DOMAIN_VERSION,
      chainId: CHAIN_ID,
      verifyingContract: QUEST_MANAGER,
    },
    types: ATTESTATION_TYPES,
    primaryType: 'Attestation',
    message: {
      account: input.account,
      questId: BigInt(input.questId),
      nonce: BigInt(input.nonce),
      deadline: BigInt(input.deadline),
    },
  });
}

function baseInput(overrides: Partial<AttestationInput> = {}): AttestationInput {
  return {
    account: ALICE,
    questId: 3,
    nonce: 1,
    deadline: NOW + 3600,
    signature: '0x00',
    ...overrides,
  };
}

describe('checkAttestation', () => {
  it('accepts a real verifier signature and recovers the verifier', async () => {
    const input = baseInput();
    input.signature = await signAttestation(input);
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result).toEqual({ valid: true, signer: VERIFIER, errors: [] });
  });

  it('rejects a malformed signature (too short)', async () => {
    const result = await checkAttestation(
      baseInput({ signature: '0x1234' }),
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.signer).toBeNull();
    expect(result.errors).toContain('Signature must be a 65-byte 0x hex string');
  });

  it('rejects a malformed signature (non-hex characters)', async () => {
    const result = await checkAttestation(
      baseInput({ signature: `0x${'zz'.repeat(65)}` as `0x${string}` }),
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.errors).toContain('Signature must be a 65-byte 0x hex string');
  });

  it('rejects an expired attestation', async () => {
    const input = baseInput({ deadline: NOW - 1 });
    input.signature = await signAttestation(input);
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.valid).toBe(false);
    expect(result.errors).toContain('Attestation has expired');
  });

  it('accepts a deadline exactly at now (contract rejects only deadline < now)', async () => {
    const input = baseInput({ deadline: NOW });
    input.signature = await signAttestation(input);
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.valid).toBe(true);
  });

  it('rejects a deadline more than 7 days out', async () => {
    const input = baseInput({ deadline: NOW + MAX_ATTESTATION_LIFETIME_SECONDS + 1 });
    input.signature = await signAttestation(input);
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.valid).toBe(false);
    expect(result.errors).toContain(
      'Deadline is more than 7 days out — the contract will reject it',
    );
  });

  it('accepts a deadline exactly 7 days out (boundary)', async () => {
    const input = baseInput({ deadline: NOW + MAX_ATTESTATION_LIFETIME_SECONDS });
    input.signature = await signAttestation(input);
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.valid).toBe(true);
  });

  it('rejects a non-integer / zero deadline', async () => {
    const zero = await checkAttestation(baseInput({ deadline: 0 }), CHAIN_ID, QUEST_MANAGER, NOW);
    expect(zero.valid).toBe(false);
    expect(zero.errors).toContain('Deadline must be a Unix timestamp');
    const fractional = await checkAttestation(
      baseInput({ deadline: NOW + 0.5 }),
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(fractional.valid).toBe(false);
  });

  it('a tampered signature does NOT recover the verifier', async () => {
    const input = baseInput();
    const sig = await signAttestation(input);
    // Flip the last byte (v): recovery yields a different address (or
    // throws) — either way the verifier is not the recovered signer.
    const last = sig.slice(-2);
    const flipped = last === '1b' ? '1c' : '1b';
    input.signature = `${sig.slice(0, -2)}${flipped}` as `0x${string}`;
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.signer).not.toBe(VERIFIER);
  });

  it('a signature for another account does not verify for this account', async () => {
    const other = baseInput({ account: '0x0000000000000000000000000000000000000001' });
    const sigForOther = await signAttestation(other);
    // Present the other account's signature with Alice's account.
    const input = baseInput({ signature: sigForOther });
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.signer).not.toBe(VERIFIER);
  });

  it('a signature for another quest does not verify for this quest', async () => {
    const other = baseInput({ questId: 99 });
    const sigForOther = await signAttestation(other);
    const input = baseInput({ signature: sigForOther });
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.signer).not.toBe(VERIFIER);
  });

  it('a signature for another nonce does not verify for this nonce', async () => {
    const other = baseInput({ nonce: 2 });
    const sigForOther = await signAttestation(other);
    const input = baseInput({ signature: sigForOther });
    const result = await checkAttestation(input, CHAIN_ID, QUEST_MANAGER, NOW);
    expect(result.signer).not.toBe(VERIFIER);
  });

  it('recovery under a different chain id yields a different signer (domain binding)', async () => {
    // The client-side check alone cannot tell which chain the signature
    // was made for — recovery just returns a different address. The
    // CONTRACT binds the domain, so a cross-chain signature fails
    // on-chain (wrong signer, no VERIFIER_ROLE). This test pins that
    // the client-side signer differs, i.e. the domain is actually part
    // of the signed data.
    const input = baseInput();
    input.signature = await signAttestation(input);
    const result = await checkAttestation(input, 56, QUEST_MANAGER, NOW);
    expect(result.signer).not.toBe(VERIFIER);
  });

  it('reports both shape and expiry problems together', async () => {
    const result = await checkAttestation(
      baseInput({ signature: '0x1234', deadline: NOW - 100 }),
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.errors).toHaveLength(2);
  });
});

describe('checkAttestations (multi-signature, Phase 6 / R-010)', () => {
  async function signPair() {
    const base = baseInput();
    const sig1 = await signAttestation(base, VERIFIER_KEY);
    const sig2 = await signAttestation(base, VERIFIER2_KEY);
    return { base, sig1, sig2 };
  }

  it('accepts a valid pair from two distinct signers for threshold 2', async () => {
    const { base, sig1, sig2 } = await signPair();
    const result = await checkAttestations(
      { ...base, signatures: [sig1, sig2] },
      2,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(true);
    expect(result.signers).toEqual([VERIFIER, VERIFIER2]);
    expect(result.errors).toEqual([]);
    expect(result.perSigner).toHaveLength(2);
    expect(result.perSigner.every((p) => p.valid)).toBe(true);
  });

  it('rejects a duplicate pair (same signer twice)', async () => {
    const base = baseInput();
    const sig = await signAttestation(base, VERIFIER_KEY);
    const result = await checkAttestations(
      { ...base, signatures: [sig, sig] },
      2,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.signers).toEqual([VERIFIER]);
    expect(result.perSigner[1]?.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('Duplicate signer'))).toBe(true);
  });

  it('rejects a pair with one malformed signature', async () => {
    const base = baseInput();
    const sig1 = await signAttestation(base, VERIFIER_KEY);
    const result = await checkAttestations(
      { ...base, signatures: [sig1, '0x1234'] },
      2,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.signers).toEqual([VERIFIER]);
    expect(result.perSigner[1]?.valid).toBe(false);
    expect(result.perSigner[1]?.signer).toBeNull();
    expect(result.errors.some((e) => e.includes('65-byte'))).toBe(true);
  });

  it('rejects fewer signatures than the threshold', async () => {
    const base = baseInput();
    const sig1 = await signAttestation(base, VERIFIER_KEY);
    const result = await checkAttestations(
      { ...base, signatures: [sig1] },
      2,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.errors).toContain('Only 1 distinct valid signer — this quest requires 2');
  });

  it('rejects more than MAX_ATTESTATION_SIGNATURES signatures', async () => {
    const base = baseInput();
    const sig = await signAttestation(base, VERIFIER_KEY);
    const signatures = Array(MAX_ATTESTATION_SIGNATURES + 1).fill(sig);
    const result = await checkAttestations(
      { ...base, signatures },
      1,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.errors).toContain(
      `At most ${MAX_ATTESTATION_SIGNATURES} signatures are allowed (got ${MAX_ATTESTATION_SIGNATURES + 1})`,
    );
  });

  it('accepts threshold 3 with three distinct signers', async () => {
    const base = baseInput();
    const sig1 = await signAttestation(base, VERIFIER_KEY);
    const sig2 = await signAttestation(base, VERIFIER2_KEY);
    const sig3 = await signAttestation(base, VERIFIER3_KEY);
    const result = await checkAttestations(
      { ...base, signatures: [sig1, sig2, sig3] },
      3,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(true);
    expect(result.signers).toEqual([VERIFIER, VERIFIER2, VERIFIER3]);
    expect(result.errors).toEqual([]);
  });

  it('accepts extra signatures beyond the threshold (all must still be valid)', async () => {
    const base = baseInput();
    const sig1 = await signAttestation(base, VERIFIER_KEY);
    const sig2 = await signAttestation(base, VERIFIER2_KEY);
    const sig3 = await signAttestation(base, VERIFIER3_KEY);
    const result = await checkAttestations(
      { ...base, signatures: [sig1, sig2, sig3] },
      2,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(true);
    expect(result.signers).toHaveLength(3);
  });

  it('rejects an out-of-range threshold without checking signatures', async () => {
    const base = baseInput();
    const sig1 = await signAttestation(base, VERIFIER_KEY);
    const result = await checkAttestations(
      { ...base, signatures: [sig1] },
      0,
      CHAIN_ID,
      QUEST_MANAGER,
      NOW,
    );
    expect(result.valid).toBe(false);
    expect(result.errors).toContain('Attestation threshold must be between 1 and 3');
  });
});

describe('recoverAttestationSigner', () => {
  it('recovers the signer of a valid attestation', async () => {
    const input = baseInput();
    input.signature = await signAttestation(input);
    const signer = await recoverAttestationSigner(input, CHAIN_ID, QUEST_MANAGER);
    expect(signer).toBe(VERIFIER);
  });

  it('recovers a different signer when a different key signed', async () => {
    // A clearly synthetic key (not an Anvil dev key) — any 32-byte
    // scalar is a valid secp256k1 private key.
    const OTHER_KEY = '0x2222222222222222222222222222222222222222222222222222222222222222' as const;
    const input = baseInput();
    input.signature = await signAttestation(input, OTHER_KEY);
    const signer = await recoverAttestationSigner(input, CHAIN_ID, QUEST_MANAGER);
    expect(signer).not.toBe(VERIFIER);
    expect(signer).toBe(privateKeyToAccount(OTHER_KEY).address);
  });
});
