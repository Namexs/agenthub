'use client';

import { useCallback, useState } from 'react';
import { useAccount, useReadContract } from 'wagmi';
import { QUEST_MANAGER_ABI, contractAddresses } from '@/lib/contracts';
import { env } from '@/lib/env';
import { checkAttestation, type AttestationCheck } from '@/lib/attestation';
import type { Address } from 'viem';

// Attestation verification (Phase 7). The user pastes a signature +
// deadline they received from a verifier (out-of-band — there is no
// "request" backend). check() runs the client-side verification:
// signature shape, deadline bounds, signer recovery, AND the on-chain
// VERIFIER_ROLE check for the recovered signer. Only a fully valid
// attestation enables the submit button — and the contract re-verifies
// everything on-chain anyway.

export interface AttestationVerification extends AttestationCheck {
  /** True once the on-chain role check confirms the signer is a verifier. */
  isVerifier: boolean | null;
  isCheckingRole: boolean;
  /** The nonce the attestation must be signed over. */
  nonce: number | null;
  nonceLoading: boolean;
}

export function useAttestation(questId: number) {
  const { address } = useAccount();
  const questManager = contractAddresses.questManager;
  const [checkResult, setCheckResult] = useState<AttestationCheck | null>(null);

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

  const signer = checkResult?.signer ?? null;
  const { data: hasRole, isLoading: isCheckingRole } = useReadContract({
    address: questManager,
    abi: QUEST_MANAGER_ABI,
    functionName: 'hasRole',
    args: signer && verifierRole ? [verifierRole as `0x${string}`, signer] : undefined,
    query: { enabled: Boolean(questManager && signer && verifierRole) },
  });

  const check = useCallback(
    async (signature: string, deadline: number): Promise<AttestationCheck> => {
      const nonce = nonceData === undefined ? null : Number(nonceData);
      if (!address || !questManager || nonce === null) {
        const result: AttestationCheck = {
          valid: false,
          signer: null,
          errors: ['Connect your wallet and wait for the nonce to load first'],
        };
        setCheckResult(result);
        return result;
      }
      const result = await checkAttestation(
        {
          account: address,
          questId,
          nonce,
          deadline,
          signature: signature as `0x${string}`,
        },
        env.NEXT_PUBLIC_CHAIN_ID,
        questManager,
        Math.floor(Date.now() / 1000),
      );
      setCheckResult(result);
      return result;
    },
    [address, questManager, questId, nonceData],
  );

  const verification: AttestationVerification = {
    valid: Boolean(checkResult?.valid && hasRole === true),
    signer,
    errors: [
      ...(checkResult?.errors ?? []),
      ...(checkResult?.valid && hasRole === false
        ? ['Recovered signer does not hold VERIFIER_ROLE']
        : []),
    ],
    isVerifier: hasRole === undefined ? null : hasRole,
    isCheckingRole,
    nonce: nonceData === undefined ? null : Number(nonceData),
    nonceLoading,
  };

  return { check, verification, reset: () => setCheckResult(null) };
}
