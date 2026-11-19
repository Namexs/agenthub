# AGENTHUB — Attestation Final Report (Phase E)

**Date:** 2026-11-19. **Phase:** E — Attestation finalization.
**Scope:** the complete EIP-712 attestation lifecycle (12 points),
the frontend submission flow vs the actual contract ABI, and the
decision on verifier tooling (dashboard / signing service).
**Verdict: GATE E — PASSED.** All 12 lifecycle points verified
on-chain and in the frontend. One gap was found and fixed in this
phase: the verifier SOP referenced "the project's signing tooling",
which did not exist — a local signing tool was built, tested
end-to-end on anvil, and documented. No backend signing service and
no verifier dashboard are introduced (decision in §4, with reasons).

## 1. The 12-point EIP-712 lifecycle review

Type: `Attestation(address account, uint256 questId, uint256 nonce,
uint256 deadline)`. Domain: `EIP712("AGENTHUB QuestManager", "1")`
(chainId + verifying contract bound by the OZ domain separator).
Contract: `QuestManager._verifyAttestation` + `completeQuestWithAttestation`.

| #   | Point                            | Verdict | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                   |
| --- | -------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Verifier authorization           | PASS    | `_verifyAttestation` requires `hasRole(VERIFIER_ROLE, signer)` (`UnauthorizedVerifier` otherwise). Frontend additionally reads `hasRole` for the recovered signer before enabling submit (`useAttestation.ts`). Tests: `test_UnauthorizedSignerRejected`, `test_OnlyAdminCanGrantVerifierRole`.                                                                                                                            |
| 2   | Signer attribution               | PASS    | `AttestationUsed(account, questId, nonce, signer)` — signer is an indexed topic (Phase 6), so per-signer history is one topic filter. Test: `test_AttestationUsedEventAttributesSigner`. SOP §8 requires weekly review.                                                                                                                                                                                                    |
| 3   | Signature validity               | PASS    | `ECDSA.tryRecover` rejects malleable signatures (s > n/2), short/empty signatures, and zero-address recovery (`InvalidAttestationSignature` carries OZ's error arg for diagnosis). Tests: `test_MalleableSignatureRejected`, `test_EmptySignatureRejected`, `test_ShortSignatureRejected`, `test_ZeroSignatureRejected`. Frontend: 16 tests in `lib/attestation.test.ts` (shape, tamper, wrong account/quest/nonce/chain). |
| 4   | User + quest binding             | PASS    | Struct binds `account` + `questId`; the contract verifies against `msg.sender` as the account. Tests: `test_WrongAccountRejected`, `test_WrongQuestRejected`, `test_DelegatedCompletionImpossible`, `test_VerifierCannotSubmitForUser`.                                                                                                                                                                                    |
| 5   | Chain + contract binding         | PASS    | OZ domain separator binds chainId + verifying contract; a redeployed QuestManager invalidates old attestations. Tests: `test_CrossChainReplayRejected`, `test_CrossContractReplayRejected`; frontend test: recovery under a different chain id yields a different signer.                                                                                                                                                  |
| 6   | Nonce uniqueness                 | PASS    | Global per-account nonce (`nonces[account]`), incremented on every successful verification; each signature usable exactly once. Tests: `test_WrongNonceRejected`, `testFuzz_WrongNonceAlwaysRejected`, `test_NoncesAreIsolatedPerAccount`. Operational consequence (global, not per-quest): see §5 / SOP §6 step 6 (updated this phase).                                                                                   |
| 7   | Deadline                         | PASS    | `deadline < block.timestamp` reverts; `deadline > now + 7 days` reverts (`MAX_ATTESTATION_LIFETIME`). Boundary tests both sides (`test_DeadlineAtCurrentBlockAccepted`, `test_DeadlineAtMaxLifetimeAccepted`, `test_DeadlineTooFarReverts`, `test_ExpiredAttestationReverts`); frontend mirrors the same bounds (incl. exact-boundary tests).                                                                              |
| 8   | Replay prevention                | PASS    | Nonce consumption (point 6) + full binding (points 4–5). Test: `test_ReplaySameAttestationReverts`.                                                                                                                                                                                                                                                                                                                        |
| 9   | Invalid signature rejection      | PASS    | See point 3 — malformed, malleable, empty, short, and zero-recovery signatures all revert; the frontend pre-check rejects them before any transaction is proposed.                                                                                                                                                                                                                                                         |
| 10  | Revoked verifier rejection       | PASS    | Role is checked at verification time, so revocation invalidates outstanding attestations immediately — no grace period. Test: `test_VerifierRotationInvalidatesOldAttestations`. Note the 2-day timelock delay on the revocation itself: pause is the fast path (SOP §4).                                                                                                                                                  |
| 11  | Front-running resistance         | PASS    | The attestation binds `account = msg.sender`; a front-runner submitting someone else's attestation recovers a digest for the wrong account and the role/nonce check fails. Test: `test_FrontRunnerCannotSubmitOthersAttestation`. A leaked signature can only complete the bound quest for the bound account, once.                                                                                                        |
| 12  | Failed tx does not consume nonce | PASS    | Nonce consumption happens inside the same transaction as the completion; if completion reverts (quest full, quest ended, downstream revert), the whole tx reverts and the nonce is unchanged — the same attestation can be retried. Test: `test_FailedCompletionDoesNotBurnNonce`.                                                                                                                                         |

All 12 points are covered by Foundry tests (in `Attestation.t.sol`,
`VerifierSecurity.t.sol`, `AttackSimulation.t.sol`) and, where the
frontend mirrors a check, by the 16 frontend attestation tests —
all green in the Phase C clean-copy run (Foundry 255/255, web
136 + 4 skip).

## 2. Frontend flow vs actual ABI

Flow (`AttestationForm.tsx` + `useAttestation.ts` +
`useCompleteQuest.ts` + `lib/attestation.ts`):

1. User pastes a signature + deadline received out-of-band from a
   verifier. There is deliberately no "request attestation" backend.
2. `check()` runs the client-side verification: 65-byte hex shape,
   deadline bounds (expired / >7 days), signer recovery via viem
   `recoverTypedDataAddress` with the exact domain + types, zero-
   address rejection, and an on-chain `hasRole(VERIFIER_ROLE,
signer)` read. Only a fully valid attestation enables submit.
3. `completeWithAttestation(questId, deadline, signature)` submits
   via wagmi `useWriteContract`; the UI shows pending → confirming
   → confirmed from the receipt, never "done" at submit time.
4. The contract re-verifies everything on-chain — the client check
   is a UX guard, not the security boundary (stated in the code).

ABI verification (this phase): re-running
`packages/contracts/script/export-abis.mjs` against the current
forge build produced **zero git diff** — the committed frontend
ABIs (`apps/web/lib/abis/*.ts`) are byte-identical to the current
contract ABIs, including `completeQuestWithAttestation(uint256,
uint256, bytes)`. The domain name/version, typehash fields, and
7-day lifetime in `lib/attestation.ts` match the contract
constants exactly.

One UX note (not a defect): the nonce is read at verify time; if
the user completes another attested quest between verify and
submit, the nonce moves and the submission reverts on-chain
(fail-closed; the wallet simulation surfaces it before gas is
spent). The form re-verifies on every input change.

## 3. Gap found and fixed: the missing signing tool

**Finding (documentation/operational, not a contract bug):** the
verifier SOP (§6 step 4) instructed verifiers to "use the
project's signing tooling", but no signing tool existed in the
repo — the only `signTypedData` calls were inside test harnesses.
The first verifier would have had no concrete, reviewed way to
sign.

**Fix (this phase):** `apps/web/scripts/sign-attestation.mjs` —
a minimal LOCAL signing tool:

- Reads the key ONLY from `VERIFIER_PRIVATE_KEY` (env var; never
  a CLI argument, never printed, never sent anywhere).
- Reads chain id + the account's current nonce from the RPC, and
  REFUSES to sign (exit 2) unless the key holds `VERIFIER_ROLE`
  on-chain — a wrong key/contract/RPC fails fast with a clear
  message instead of producing a useless signature.
- Validates the deadline (future, ≤ 7 days) before signing.
- Signs the exact EIP-712 domain/types the contract verifies, then
  self-checks by recovering the signer.
- Prints only the paste-ready values (chainId, account, questId,
  nonce, deadline, signer, signature).
- Its header comment documents the trust assumptions explicitly:
  local-only, no server; a compromised machine means a compromised
  verifier key (mitigated by the SOP's dedicated-key/no-funds/
  pause+revoke rules); the RPC is trusted for reads (a lying RPC
  can only produce an invalid signature, never a valid one for a
  different account/quest).

**End-to-end test on anvil** (log:
`logs/phase-e-signing-test.log`):

1. Signed for bob / quest 3 with the test-stack verifier key
   (`0x…a11ce5`): role confirmed on-chain, nonce 0, signature
   produced.
2. Submitted via `cast send completeQuestWithAttestation` as bob:
   tx status `0x1`.
3. Verified on-chain: `hasCompleted(bob, 3) = true`,
   `nonces(bob) = 1`.
4. Refusal path: a non-verifier key exits 2 with a clear error.
5. Usage path: a missing key exits 1 with guidance.
6. No private key material appears in the log (the key travelled
   via env only; the printed signature is single-use, anvil-only,
   and already consumed).

**SOP updates** (`docs/VERIFIER_ROLE_SOP.md` §6): step 4 now names
the tool, its local-only nature, and the hardware/HSM requirement
for production service verifiers; step 6 now warns that the nonce
is global per account — a second attestation for ANY quest for the
same account requires re-reading the nonce (Phase D observation
O2). Both files pass prettier.

## 4. Decision: no verifier dashboard, no backend signing service

**For testnet staging, neither is needed — and a backend signing
service would be a net negative:**

- Scale: the SOP starts with ONE verifier (max three without
  written justification). Manual out-of-band issuance + the local
  signing tool covers this completely.
- Trust: a backend signing service means a centralized verifier
  key on a server — it would widen T-ATT-01 (verifier honesty is
  already the project's largest residual trust assumption) into a
  server-compromise = unlimited-reputation-minting risk, with no
  testnet benefit. The directive forbids introducing a centralized
  signing key without documented trust assumptions and controls;
  the honest assessment is that testnet does not justify it at all.
- Dashboard: there is nothing to dashboard yet — one verifier,
  manual issuance, and on-chain attribution (`AttestationUsed`
  events) already gives per-signer accountability via BscScan /
  `cast`. A dashboard becomes worth building only if verifier
  count or attestation volume grows (post-testnet decision, with
  its own trust review).

If a service verifier is ever needed, the requirements are: HSM/
hardware-backed key, no plaintext key on any server, per-request
human or policy approval, and an audit log of every signature —
to be designed and reviewed as its own work item, not bolted on
for testnet.

## 5. Residual risks (carried)

- **T-ATT-01 — verifier honesty.** An attestation proves an
  authorized verifier signed, not that the verifier told the
  truth. Mitigations in place: few verifiers, named + dedicated +
  hardware-backed keys, per-signer on-chain attribution, pause as
  the instant stop, 2-day timelock revocation, SOP monitoring
  (§8). Unchanged by this phase.
- **Revocation latency.** Role revocation takes 2 days through
  the timelock; the fast control is `pause()` (instant, stops all
  completions). Worst case the platform is paused ~4 days across a
  revoke + unpause cycle (SOP §4). By design.
- **Global nonce ordering.** One pending attestation per account
  at a time; verifiers must re-read the nonce before every
  signature (SOP updated this phase).
- **No on-chain undo.** Points/badges issued on a dishonest
  attestation cannot be revoked (Phase D observation O4). Response
  is governance, per SOP §4 step 4.

## 6. Evidence index

- `logs/phase-e-signing-test.log` — end-to-end signing test
  (sign → submit → verify + refusal/usage paths).
- `apps/web/scripts/sign-attestation.mjs` — the signing tool
  (new file, this phase).
- `docs/VERIFIER_ROLE_SOP.md` — §6 steps 4 + 6 updated.
- ABI sync: `export-abis.mjs` re-run produced zero diff
  (verified this phase; no log file — the absence of a diff is
  the evidence, recorded here).
- Contract tests: `Attestation.t.sol`, `VerifierSecurity.t.sol`
  (Phase D battery: 255/255 incl. fuzz 10k).
- Frontend tests: `lib/attestation.test.ts` (16 tests, Phase C
  clean-copy run green).

**Commits:** Phase E commit (this report + signing tool + SOP +
test log).
