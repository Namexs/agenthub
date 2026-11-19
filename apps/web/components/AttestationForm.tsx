'use client';

import { useState } from 'react';
import { useChainGuard } from '@/hooks/useChainGuard';
import { useAttestation } from '@/hooks/useAttestation';
import { useCompleteQuest } from '@/hooks/useCompleteQuest';
import { formatAddress } from '@/lib/utils';
import { env } from '@/lib/env';
import { explorerTxUrl } from '@/lib/events';

// Attestation submission form (Phase 7). The user pastes a signature +
// deadline they received from a verifier OUT OF BAND — there is no
// "request attestation" backend; the verifier is off-chain by design.
// The form VERIFIES client-side (signature, deadline, nonce, signer
// role) before the submit button enables. A submitted transaction is
// NOT a completed quest until the receipt confirms success.

export function AttestationForm({ questId, questTitle }: { questId: number; questTitle: string }) {
  const { isSupported } = useChainGuard();
  const { check, verification } = useAttestation(questId);
  const { completeWithAttestation, hash, isPending, isConfirming, isSuccess, isFailed, error } =
    useCompleteQuest();
  const [signature, setSignature] = useState('');
  const [deadlineInput, setDeadlineInput] = useState('');
  const [checked, setChecked] = useState(false);

  const deadlineSeconds = (() => {
    const n = Number(deadlineInput);
    return Number.isInteger(n) && n > 0 ? n : NaN;
  })();

  const onVerify = () => {
    if (Number.isNaN(deadlineSeconds)) return;
    void check(signature.trim(), deadlineSeconds);
    setChecked(true);
  };

  const onSubmit = () => {
    if (!verification.valid || Number.isNaN(deadlineSeconds)) return;
    completeWithAttestation(questId, deadlineSeconds, signature.trim() as `0x${string}`);
  };

  return (
    <div className="mt-3 border-t border-navy-600/50 pt-3">
      <p className="text-xs font-medium text-ink-300">
        Attested quest — paste the signature your verifier gave you.
      </p>
      <label className="mt-2 block text-xs text-ink-500">
        Signature (65-byte 0x hex)
        <input
          value={signature}
          onChange={(e) => {
            setSignature(e.target.value);
            setChecked(false);
          }}
          placeholder="0x…"
          spellCheck={false}
          className="mt-1 w-full rounded-lg border border-navy-600 bg-navy-900 px-3 py-2 font-mono text-xs text-ink-100 placeholder:text-ink-600"
        />
      </label>
      <label className="mt-2 block text-xs text-ink-500">
        Deadline (Unix timestamp, seconds)
        <input
          value={deadlineInput}
          onChange={(e) => {
            setDeadlineInput(e.target.value);
            setChecked(false);
          }}
          placeholder="e.g. 1797000000"
          inputMode="numeric"
          className="mt-1 w-full rounded-lg border border-navy-600 bg-navy-900 px-3 py-2 font-mono text-xs text-ink-100 placeholder:text-ink-600"
        />
      </label>
      <div className="mt-3 flex gap-2">
        <button
          type="button"
          onClick={onVerify}
          disabled={!signature || Number.isNaN(deadlineSeconds) || verification.nonceLoading}
          className="rounded-pill border border-electric-500/50 bg-electric-600/10 px-4 py-2 text-xs font-semibold text-electric-300 transition hover:bg-electric-600/20 disabled:opacity-50"
        >
          Verify attestation
        </button>
        <button
          type="button"
          onClick={onSubmit}
          disabled={!verification.valid || !isSupported || isPending || isConfirming || isSuccess}
          className="rounded-pill bg-gradient-to-r from-agent-500 to-electric-600 px-4 py-2 text-xs font-semibold text-white transition hover:opacity-90 disabled:opacity-50"
        >
          {isPending
            ? 'Confirm in wallet…'
            : isConfirming
              ? 'Confirming…'
              : isSuccess
                ? 'Completed ✓'
                : 'Submit attestation'}
        </button>
      </div>
      {checked && verification.signer && (
        <p className="mt-2 text-xs text-ink-400">
          Signer: <span className="font-mono">{formatAddress(verification.signer)}</span>{' '}
          {verification.isVerifier === true ? (
            <span className="font-medium text-agent-300">(verified verifier ✓)</span>
          ) : verification.isVerifier === false ? (
            <span className="font-medium text-red-300">(NOT a verifier ✗)</span>
          ) : (
            <span className="text-ink-500">(checking role…)</span>
          )}
        </p>
      )}
      {checked && verification.errors.length > 0 && (
        <ul className="mt-2 list-inside list-disc text-xs text-red-300">
          {verification.errors.map((e) => (
            <li key={e}>{e}</li>
          ))}
        </ul>
      )}
      {hash && (
        <p className="mt-2 text-xs text-ink-400">
          Tx:{' '}
          {explorerTxUrl(env.NEXT_PUBLIC_CHAIN_ID, hash) ? (
            <a
              href={explorerTxUrl(env.NEXT_PUBLIC_CHAIN_ID, hash)}
              target="_blank"
              rel="noreferrer"
              className="font-mono text-electric-300 underline"
            >
              {formatAddress(hash)}
            </a>
          ) : (
            <span className="font-mono">{formatAddress(hash)}</span>
          )}{' '}
          {isSuccess ? '— confirmed on-chain ✓' : isConfirming ? '— waiting for confirmation…' : ''}
        </p>
      )}
      {isFailed && error && <p className="mt-2 text-xs text-red-300">{error}</p>}
      <p className="mt-2 text-xs text-ink-500">
        No verifier yet? Attestations are issued out-of-band — contact a verifier for “{questTitle}”
        and they will sign for your address.
      </p>
    </div>
  );
}
