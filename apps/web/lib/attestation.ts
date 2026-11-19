import { recoverTypedDataAddress, type Address } from 'viem';

// Client-side EIP-712 attestation helpers (Phase 7, pure functions).
//
// The attestation flow is: a verifier signs off-chain (see
// VERIFIER_ROLE_SOP.md), the user pastes the signature + deadline here,
// the frontend VERIFIES it client-side (recover signer, check deadline
// and nonce), and only then submits completeQuestWithAttestation.
// Verification is a UX guard, not the security boundary — the contract
// re-verifies everything on-chain (signer role, nonce, deadline, domain).
//
// There is deliberately NO "request attestation" backend: the verifier is
// off-chain by design, and requesting one is a manual, out-of-band step
// (the user contacts a verifier through the normal channel).

export const ATTESTATION_DOMAIN_NAME = 'AGENTHUB QuestManager';
export const ATTESTATION_DOMAIN_VERSION = '1';

/** Maximum attestation lifetime enforced by the contract (7 days). */
export const MAX_ATTESTATION_LIFETIME_SECONDS = 7 * 24 * 60 * 60;

export const ATTESTATION_TYPES = {
  Attestation: [
    { name: 'account', type: 'address' },
    { name: 'questId', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
} as const;

export interface AttestationInput {
  account: Address;
  questId: number;
  nonce: number;
  deadline: number;
  signature: `0x${string}`;
}

/** Recover the signer of an attestation (throws on malformed input). */
export async function recoverAttestationSigner(
  input: AttestationInput,
  chainId: number,
  questManagerAddress: Address,
): Promise<Address> {
  return recoverTypedDataAddress({
    domain: {
      name: ATTESTATION_DOMAIN_NAME,
      version: ATTESTATION_DOMAIN_VERSION,
      chainId,
      verifyingContract: questManagerAddress,
    },
    types: ATTESTATION_TYPES,
    primaryType: 'Attestation',
    message: {
      account: input.account,
      questId: BigInt(input.questId),
      nonce: BigInt(input.nonce),
      deadline: BigInt(input.deadline),
    },
    signature: input.signature,
  });
}

export interface AttestationCheck {
  valid: boolean;
  /** Recovered signer (null when recovery failed). */
  signer: Address | null;
  /** Human-readable problems, in check order. Empty when valid. */
  errors: string[];
}

/**
 * Validate an attestation client-side: signature shape, deadline bounds,
 * and signer recovery. The caller must ALSO check the recovered signer
 * holds VERIFIER_ROLE on-chain (hasRole) — that read is not pure, so it
 * lives in useAttestation, not here.
 */
export async function checkAttestation(
  input: AttestationInput,
  chainId: number,
  questManagerAddress: Address,
  nowSeconds: number,
): Promise<AttestationCheck> {
  const errors: string[] = [];
  if (!/^0x[0-9a-fA-F]{130}$/.test(input.signature)) {
    errors.push('Signature must be a 65-byte 0x hex string');
  }
  if (!Number.isInteger(input.deadline) || input.deadline <= 0) {
    errors.push('Deadline must be a Unix timestamp');
  } else if (input.deadline < nowSeconds) {
    errors.push('Attestation has expired');
  } else if (input.deadline > nowSeconds + MAX_ATTESTATION_LIFETIME_SECONDS) {
    errors.push('Deadline is more than 7 days out — the contract will reject it');
  }
  if (errors.length > 0) return { valid: false, signer: null, errors };

  let signer: Address | null = null;
  try {
    signer = await recoverAttestationSigner(input, chainId, questManagerAddress);
  } catch {
    errors.push('Signature could not be recovered — it may be malformed');
    return { valid: false, signer: null, errors };
  }
  if (signer === '0x0000000000000000000000000000000000000000') {
    errors.push('Signature recovers to the zero address');
    return { valid: false, signer: null, errors };
  }
  return { valid: true, signer, errors: [] };
}
