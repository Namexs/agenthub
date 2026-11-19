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

/**
 * PHASE 6 (R-010): maximum signatures in one attestation array, enforced
 * by the contract (`MAX_ATTESTATION_SIGNATURES`). Mirrors the on-chain
 * constant — keep in sync with QuestManager.sol.
 */
export const MAX_ATTESTATION_SIGNATURES = 5;

/**
 * PHASE 6 (R-010): attestationThreshold range enforced by createQuest
 * (1–3). A quest's threshold is set at creation and immutable.
 */
export const MIN_ATTESTATION_THRESHOLD = 1;
export const MAX_ATTESTATION_THRESHOLD = 3;

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

// --- Multi-signature (threshold) attestation checks (PHASE 6, R-010) ---
//
// A threshold-M quest needs M DISTINCT verifier signatures over the SAME
// digest (same account, questId, nonce, deadline). All signers sign the
// same attestation struct — no new EIP-712 type. The contract enforces
// distinctness + threshold on-chain; this client-side check mirrors it
// so the form can show per-signer status before submit. The on-chain
// VERIFIER_ROLE check per signer is NOT pure, so it lives in
// useAttestation (batched hasRole reads), not here.

export interface MultiAttestationInput {
  account: Address;
  questId: number;
  nonce: number;
  deadline: number;
  signatures: `0x${string}`[];
}

export interface PerSignerCheck {
  /** Index of this signature in the input array. */
  index: number;
  /** Recovered signer (null when recovery failed). */
  signer: Address | null;
  /** True when this signature alone is well-formed and recovers. */
  valid: boolean;
  /** Human-readable problems for this signature. Empty when valid. */
  errors: string[];
}

export interface MultiAttestationCheck {
  /**
   * True when at least `threshold` DISTINCT signers recovered from
   * well-formed signatures AND no signature in the array is malformed
   * or duplicated. Mirrors the contract: a junk signature anywhere in
   * the array reverts the call, so the client must not submit it.
   */
  valid: boolean;
  /** Distinct recovered signers from the valid signatures, in order. */
  signers: Address[];
  /** Per-signature results, in input order. */
  perSigner: PerSignerCheck[];
  /** Aggregate problems, in check order. Empty when valid. */
  errors: string[];
}

/**
 * Validate a multi-signature attestation client-side: array size,
 * threshold range, per-signature shape/deadline/recovery (via
 * checkAttestation), duplicate-signer rejection, and the distinct
 * signer count against the threshold. The caller must ALSO check that
 * every recovered signer holds VERIFIER_ROLE on-chain (hasRole) — that
 * read is not pure, so it lives in useAttestation, not here.
 */
export async function checkAttestations(
  input: MultiAttestationInput,
  threshold: number,
  chainId: number,
  questManagerAddress: Address,
  nowSeconds: number,
): Promise<MultiAttestationCheck> {
  const errors: string[] = [];
  if (
    !Number.isInteger(threshold) ||
    threshold < MIN_ATTESTATION_THRESHOLD ||
    threshold > MAX_ATTESTATION_THRESHOLD
  ) {
    errors.push(
      `Attestation threshold must be between ${MIN_ATTESTATION_THRESHOLD} and ${MAX_ATTESTATION_THRESHOLD}`,
    );
  }
  if (input.signatures.length === 0) {
    errors.push('At least one signature is required');
  }
  if (input.signatures.length > MAX_ATTESTATION_SIGNATURES) {
    errors.push(
      `At most ${MAX_ATTESTATION_SIGNATURES} signatures are allowed (got ${input.signatures.length})`,
    );
  }
  if (errors.length > 0) {
    return {
      valid: false,
      signers: [],
      perSigner: input.signatures.map((_, index) => ({
        index,
        signer: null,
        valid: false,
        errors: [],
      })),
      errors,
    };
  }

  const perSigner: PerSignerCheck[] = [];
  const seen = new Set<string>();
  const signers: Address[] = [];
  for (let i = 0; i < input.signatures.length; i++) {
    const signature = input.signatures[i] as `0x${string}`;
    const single = await checkAttestation(
      {
        account: input.account,
        questId: input.questId,
        nonce: input.nonce,
        deadline: input.deadline,
        signature,
      },
      chainId,
      questManagerAddress,
      nowSeconds,
    );
    const entry: PerSignerCheck = {
      index: i,
      signer: single.signer,
      valid: single.valid,
      errors: [...single.errors],
    };
    if (single.valid && single.signer !== null) {
      const key = single.signer.toLowerCase();
      if (seen.has(key)) {
        // Duplicate signer: the contract reverts
        // (DuplicateAttestationSigner) — never counts twice.
        entry.valid = false;
        entry.errors.push(`Duplicate signer ${single.signer} — each verifier may sign only once`);
      } else {
        seen.add(key);
        signers.push(single.signer);
      }
    }
    perSigner.push(entry);
  }

  const invalid = perSigner.filter((p) => !p.valid);
  for (const p of invalid) {
    // Single-signature callers get the exact checkAttestation messages
    // (backward-compatible); multi-signature callers get the index so
    // the bad signature is attributable.
    for (const e of p.errors) {
      errors.push(input.signatures.length > 1 ? `Signature ${p.index + 1}: ${e}` : e);
    }
  }
  if (signers.length < threshold) {
    errors.push(
      `Only ${signers.length} distinct valid signer${signers.length === 1 ? '' : 's'} — this quest requires ${threshold}`,
    );
  }
  return { valid: errors.length === 0, signers, perSigner, errors };
}
