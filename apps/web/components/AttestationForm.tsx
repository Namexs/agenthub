'use client';

import { useState } from 'react';
import { useChainGuard } from '@/hooks/useChainGuard';
import { useAttestation } from '@/hooks/useAttestation';
import { useCompleteQuest } from '@/hooks/useCompleteQuest';
import { MAX_ATTESTATION_SIGNATURES, MIN_ATTESTATION_THRESHOLD } from '@/lib/attestation';
import { formatAddress } from '@/lib/utils';
import { env } from '@/lib/env';
import { explorerTxUrl } from '@/lib/events';

// Attestation submission form (Phase 7, multi-signature in Phase 6 /
// R-010). The user pastes signatures + a deadline they received from
// verifiers OUT OF BAND — there is no "request attestation" backend;
// the verifiers are off-chain by design. A threshold-M quest needs M
// distinct verifier signatures over the SAME digest (same account,
// questId, nonce, deadline). The form VERIFIES client-side (signature,
// deadline, nonce, per-signer role) before the submit button enables.
// A submitted transaction is NOT a completed quest until the receipt
// confirms success.

export function AttestationForm({
  questId,
  questTitle,
  threshold,
}: {
  questId: number;
  questTitle: string;
  /** The quest's on-chain attestationThreshold (1–3). */
  threshold: number;
}) {
  const { isSupported } = useChainGuard();
  const { check, verification } = useAttestation(questId);
  const { completeWithAttestation, hash, isPending, isConfirming, isSuccess, isFailed, error } =
    useCompleteQuest();
  const required = Math.min(
    Math.max(threshold, MIN_ATTESTATION_THRESHOLD),
    MAX_ATTESTATION_SIGNATURES,
  );
  const [signatures, setSignatures] = useState<string[]>(() => Array(required).fill(''));
  const [deadlineInput, setDeadlineInput] = useState('');
  const [checked, setChecked] = useState(false);

  const deadlineSeconds = (() => {
    const n = Number(deadlineInput);
    return Number.isInteger(n) && n > 0 ? n : NaN;
  })();

  const filledSignatures = signatures.map((s) => s.trim()).filter((s) => s.length > 0);

  const setSignatureAt = (index: number, value: string) => {
    setSignatures((prev) => prev.map((s, i) => (i === index ? value : s)));
    setChecked(false);
  };

  const addSignatureInput = () => {
    if (signatures.length >= MAX_ATTESTATION_SIGNATURES) return;
    setSignatures((prev) => [...prev, '']);
  };

  const removeSignatureInput = (index: number) => {
    if (signatures.length <= required) return;
    setSignatures((prev) => prev.filter((_, i) => i !== index));
    setChecked(false);
  };

  const onVerify = () => {
    if (Number.isNaN(deadlineSeconds) || filledSignatures.length === 0) return;
    void check(filledSignatures, deadlineSeconds, required);
    setChecked(true);
  };

  const onSubmit = () => {
    if (!verification.valid || Number.isNaN(deadlineSeconds)) return;
    completeWithAttestation(questId, deadlineSeconds, filledSignatures as `0x${string}`[]);
  };

  return (
    <div className="mt-3 border-t border-navy-600/50 pt-3">
      <p className="text-xs font-medium text-ink-300">
        Attested quest — paste the signature your verifier gave you.
      </p>
      <p className="mt-1 text-xs text-ink-400">
        This quest requires {required} verifier signature{required === 1 ? '' : 's'} — every
        verifier signs the same deadline, and each signature must come from a different verifier.
      </p>
      {signatures.map((signature, i) => (
        <label key={i} className="mt-2 block text-xs text-ink-500">
          Signature {i + 1} (65-byte 0x hex)
          <span className="flex gap-2">
            <input
              value={signature}
              onChange={(e) => setSignatureAt(i, e.target.value)}
              placeholder="0x…"
              spellCheck={false}
              className="mt-1 w-full rounded-lg border border-navy-600 bg-navy-900 px-3 py-2 font-mono text-xs text-ink-100 placeholder:text-ink-600"
            />
            {signatures.length > required && (
              <button
                type="button"
                onClick={() => removeSignatureInput(i)}
                aria-label={`Remove signature ${i + 1}`}
                className="mt-1 shrink-0 rounded-lg border border-navy-600 px-2 text-xs text-ink-400 transition hover:text-red-300"
              >
                ✕
              </button>
            )}
          </span>
        </label>
      ))}
      {signatures.length < MAX_ATTESTATION_SIGNATURES && (
        <button
          type="button"
          onClick={addSignatureInput}
          className="mt-2 rounded-pill border border-navy-600 px-3 py-1 text-xs font-medium text-ink-300 transition hover:bg-navy-800"
        >
          + Add another signature (up to {MAX_ATTESTATION_SIGNATURES})
        </button>
      )}
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
          disabled={
            filledSignatures.length === 0 ||
            Number.isNaN(deadlineSeconds) ||
            verification.nonceLoading
          }
          className="rounded-lg border border-navy-600 bg-navy-900 px-4 py-2 text-xs font-semibold text-ink-200 transition-colors hover:border-ink-400 disabled:opacity-50"
        >
          Verify attestation
        </button>
        <button
          type="button"
          onClick={onSubmit}
          disabled={!verification.valid || !isSupported || isPending || isConfirming || isSuccess}
          className="rounded-lg bg-agent-400 px-4 py-2 text-xs font-semibold text-navy-950 transition-colors hover:bg-agent-300 disabled:opacity-50"
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
      {checked &&
        verification.perSigner
          .filter((p) => p.signer !== null)
          .map((p) => (
            <p key={p.index} className="mt-2 text-xs text-ink-400">
              Signature {p.index + 1} — signer:{' '}
              <span className="font-mono">{formatAddress(p.signer as `0x${string}`)}</span>{' '}
              {p.isVerifier === true ? (
                <span className="font-medium text-agent-300">(verified verifier ✓)</span>
              ) : p.isVerifier === false ? (
                <span className="font-medium text-red-300">(NOT a verifier ✗)</span>
              ) : (
                <span className="text-ink-500">(checking role…)</span>
              )}
            </p>
          ))}
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
        No verifier yet? Attestations are issued out-of-band — contact{' '}
        {required === 1 ? 'a verifier' : `${required} verifiers`} for “{questTitle}” and they will
        sign for your address.
      </p>
    </div>
  );
}
