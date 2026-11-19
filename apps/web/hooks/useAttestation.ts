'use client';

import { useCallback, useState } from 'react';
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { QUEST_MANAGER_ABI, contractAddresses } from '@/lib/contracts';
import { env } from '@/lib/env';
import {
  checkAttestations,
  MIN_ATTESTATION_THRESHOLD,
  type AttestationCheck,
  type MultiAttestationCheck,
  type PerSignerCheck,
} from '@/lib/attestation';
import type { Address } from 'viem';

// Attestation verification (Phase 7, multi-signature in Phase 6 / R-010).
// The user pastes signatures + a deadline they received from verifiers
// (out-of-band — there is no "request" backend). check() runs the
// client-side verification: per-signature shape, deadline bounds, signer
// recovery, duplicate rejection, distinct-signer count vs the quest's
// threshold, AND the on-chain VERIFIER_ROLE check for every recovered
// signer (batched hasRole reads). Only a fully valid attestation set
// enables the submit button — and the contract re-verifies everything
// on-chain anyway.

export interface AttestationSignerVerification extends PerSignerCheck {
  /** True once the on-chain role check confirms this signer is a verifier. */
  isVerifier: boolean | null;
}

export interface AttestationVerification {
  /** True only when the signature set is valid AND every signer holds VERIFIER_ROLE. */
  valid: boolean;
  /**
   * First recovered signer (backward-compatible with the single-signature
   * shape). Prefer `signers` for multi-signature flows.
   */
  signer: Address | null;
  /** Distinct recovered signers, in signature order. */
  signers: Address[];
  /** Per-signature verification results, in input order. */
  perSigner: AttestationSignerVerification[];
  /** Human-readable problems, in check order. Empty when valid. */
  errors: string[];
  /** True once the on-chain role check confirms ALL signers are verifiers. */
  isVerifier: boolean | null;
  isCheckingRole: boolean;
  /** The nonce the attestation must be signed over. */
  nonce: number | null;
  nonceLoading: boolean;
  /** The threshold the last check ran against. */
  threshold: number;
}

export function useAttestation(questId: number) {
  const { address } = useAccount();
  const questManager = contractAddresses.questManager;
  const [checkResult, setCheckResult] = useState<MultiAttestationCheck | null>(null);
  const [threshold, setThreshold] = useState<number>(MIN_ATTESTATION_THRESHOLD);

  const { data: nonceData, isLoading: nonceLoading } = useReadContract({
    address: questManager,
    abi: QUEST_MANAGER_ABI,
    functionName: 'nonces',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(questManager && address) },
  });

  const { data: verifierRole } = useReadContract({
    address: questManager,
    abi: QUEST_MANAGER_ABI,
    functionName: 'VERIFIER_ROLE',
    query: { enabled: Boolean(questManager) },
  });

  const signers = checkResult?.signers ?? [];
  const { data: roleResults, isLoading: isCheckingRole } = useReadContracts({
    contracts: signers.map((signer) => ({
      address: questManager as Address,
      abi: QUEST_MANAGER_ABI,
      functionName: 'hasRole',
      args: [verifierRole as `0x${string}`, signer],
    })),
    query: { enabled: Boolean(questManager && verifierRole && signers.length > 0) },
  });

  const check = useCallback(
    async (
      signatures: string[],
      deadline: number,
      thresholdValue: number,
    ): Promise<MultiAttestationCheck> => {
      const nonce = nonceData === undefined ? null : Number(nonceData);
      if (!address || !questManager || nonce === null) {
        const result: MultiAttestationCheck = {
          valid: false,
          signers: [],
          perSigner: signatures.map((_, index) => ({
            index,
            signer: null,
            valid: false,
            errors: [],
          })),
          errors: ['Connect your wallet and wait for the nonce to load first'],
        };
        setCheckResult(result);
        setThreshold(thresholdValue);
        return result;
      }
      const result = await checkAttestations(
        {
          account: address,
          questId,
          nonce,
          deadline,
          signatures: signatures as `0x${string}`[],
        },
        thresholdValue,
        env.NEXT_PUBLIC_CHAIN_ID,
        questManager,
        Math.floor(Date.now() / 1000),
      );
      setCheckResult(result);
      setThreshold(thresholdValue);
      return result;
    },
    [address, questManager, questId, nonceData],
  );

  // Role results arrive in the same order as `signers` (one hasRole read
  // per distinct signer). A signer without a successful role result is
  // still "checking" — never treated as verified.
  const roleBySigner = new Map<string, boolean | null>();
  const roleData = roleResults as unknown as { result?: boolean; status: string }[] | undefined;
  signers.forEach((signer, i) => {
    const entry = roleData?.[i];
    roleBySigner.set(
      signer.toLowerCase(),
      entry?.status === 'success' ? Boolean(entry.result) : null,
    );
  });
  const roleKnown =
    signers.length > 0 && signers.every((s) => roleBySigner.get(s.toLowerCase()) !== null);
  const allVerifiers =
    roleKnown && signers.every((s) => roleBySigner.get(s.toLowerCase()) === true);
  const isVerifier = signers.length === 0 ? null : roleKnown ? allVerifiers : null;

  const perSigner: AttestationSignerVerification[] = (checkResult?.perSigner ?? []).map((p) => ({
    ...p,
    isVerifier: p.signer === null ? null : (roleBySigner.get(p.signer.toLowerCase()) ?? null),
  }));

  const verification: AttestationVerification = {
    valid: Boolean(checkResult?.valid && isVerifier === true),
    signer: signers[0] ?? null,
    signers,
    perSigner,
    errors: [
      ...(checkResult?.errors ?? []),
      ...(checkResult?.valid && isVerifier === false
        ? ['Recovered signer does not hold VERIFIER_ROLE']
        : []),
    ],
    isVerifier,
    isCheckingRole,
    nonce: nonceData === undefined ? null : Number(nonceData),
    nonceLoading,
    threshold,
  };

  return { check, verification, reset: () => setCheckResult(null) };
}

// Re-exported for callers that still type against the single-signature
// check result (the pure checkAttestation keeps its own shape).
export type { AttestationCheck };
