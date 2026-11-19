# AGENTHUB — Threshold (M-of-N) Attestation Remediation Plan

**Phase 5, NEXT PHASE VALIDATION. Date:** 2026-11-19.
**Status of the feature: NOT IMPLEMENTED** (verified against the code —
see §1). This is a plan, not an implementation: no contract was changed
in this phase.
**Related records:** R-010 (FINAL_SECURITY_FINDINGS.md:333, Low, OPEN,
pre-mainnet); VERIFIER_SECURITY_SOP.md §6 (design sketch, "NOT
implemented"); mainnet gate item 4 (FINAL_DEPLOYMENT_CHECKLIST.md §7:
threshold attestation before any attested quest with rewardPoints >
1,000 or a real-world-value badge goes live); ATTESTATION_FINAL_REPORT.md
(12/12 single-verifier lifecycle points PASS).

## 1. Current state — verified single-verifier

Evidence (all read from the code at HEAD `d584a8e`, no contract changed):

- `QuestManager.completeQuestWithAttestation(uint256 questId, uint256
deadline, bytes calldata signature)` takes **one** signature
  (`src/QuestManager.sol:195`).
- `_verifyAttestation` (`src/QuestManager.sol:212-236`) recovers **one**
  signer via `ECDSA.tryRecover`, checks `hasRole(VERIFIER_ROLE,
signer)`, consumes the account nonce once, and emits one
  `AttestationUsed` event.
- The `Quest` struct (`src/interfaces/IQuestManager.sol:35-53`) has no
  threshold field: `id, creator, title, description, questType,
validationKind, validator, rewardPoints, badgeId, startTime,
endTime, maxCompletions, completions, active`.
- A repo-wide grep for `threshold | quorum | m-of-n | multi-sig |
multi-verifier | signatures` over `packages/contracts/src/` and the
  deploy script returns only Reputation level thresholds and
  TokenBalanceValidator (token, threshold) pairs — nothing attestation
  related. No threshold code exists anywhere in the contracts.
- The frontend ABI (`apps/web/lib/abis/QuestManager.ts`) matches: one
  `bytes` signature parameter.

**Blast radius today (accepted for testnet, documented in R-010):** one
compromised verifier key can attest falsely for any account/quest until
revoked (revocation itself takes up to ~2 days via timelock; pause is
the fast path). Exposure is bounded by the 7-day attestation lifetime,
the per-quest reward cap (10,000 points), and the pause control. This
is proportionate while the verifier set is one person (SOP §6) — it is
NOT acceptable for mainnet high-value quests, which is why the mainnet
gate requires threshold first.

## 2. Design (extends the SOP §6 sketch; decisions made explicit)

### 2.1 Scheme

- The attestation struct is UNCHANGED:
  `Attestation(address account, uint256 questId, uint256 nonce,
uint256 deadline)`. All M signers sign the **same digest** (same
  account, quest, nonce, deadline). No new EIP-712 type, no domain
  change.
- `completeQuestWithAttestation` accepts `bytes[] calldata
signatures` and requires at least M **distinct** `VERIFIER_ROLE`
  signers over that digest.
- Distinctness is enforced by comparing recovered addresses pairwise
  (O(M²) is fine for M ≤ 3). A duplicate signer **reverts**
  (`DuplicateAttestationSigner`) — fail-closed and diagnosable,
  rather than silently counting once.
- The nonce is consumed exactly once per completion, regardless of M
  (same as today). A failed completion reverts the whole tx, so the
  nonce is not burned (property preserved from the 12-point review).
- Extra signatures beyond M are allowed but ignored for counting
  (each must still recover to a valid VERIFIER_ROLE signer — a junk
  signature anywhere in the array reverts, so callers cannot smuggle
  garbage). Array length is capped (`MAX_ATTESTATION_SIGNATURES =
5`) to bound gas and calldata.
- Events: emit `AttestationUsed(account, questId, nonce, signer)`
  once per distinct signer (keeps the existing per-signer accounting
  and SOP weekly review working unchanged).

### 2.2 Threshold policy

- New per-quest field `attestationThreshold` (uint8), set at quest
  creation, **immutable afterwards**. Immutability removes a whole
  class of mid-flight policy-change attacks (no lowering the bar on a
  live high-value quest, no raising it to brick in-flight
  completions).
- Bounds enforced in `createQuest`: 1 ≤ threshold ≤ 3
  (`AttestationThresholdOutOfRange` otherwise). Default 1 preserves
  today's behavior for low-value quests.
- Recommended policy: threshold 1 for rewardPoints ≤ 1,000 and no
  real-world-value badge; threshold 2 (of a 3-verifier set) for
  rewardPoints > 1,000 or any badge with real-world value.
- **Known footgun (document, do not pretend away):** OpenZeppelin
  `AccessControl` cannot enumerate role holders, so the contract
  CANNOT check that threshold ≤ live verifier count. If verifiers are
  revoked until fewer than M remain, a threshold-M quest becomes
  uncompletable. Mitigations: (a) SOP requires ≥ threshold verifiers
  granted before creating a threshold quest, and forbids revoking
  below the highest live threshold without first deactivating
  affected quests; (b) the admin (timelock) can always deactivate a
  bricked quest and recreate it at threshold 1.

### 2.3 What threshold does NOT fix

- It stops a SINGLE compromised verifier; it does not stop M
  colluding verifiers, and it does not make any verifier honest — it
  only raises the bar. Pause + SOP monitoring remain the backstop.
- It does not fix verifier availability: a threshold quest needs M
  verifiers to sign the same nonce+deadline within the coordination
  window (see §5 risks).

## 3. Contract changes required

| File                                                                                                                      | Change                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/interfaces/IQuestManager.sol`                                                                                        | `Quest` struct gains `uint8 attestationThreshold`; `completeQuestWithAttestation` signature becomes `(uint256 questId, uint256 deadline, bytes[] calldata signatures)`; new errors `DuplicateAttestationSigner(address)`, `InsufficientAttestations(uint256 provided, uint256 required)`, `AttestationThresholdOutOfRange(uint256)`; `MAX_ATTESTATION_SIGNATURES` constant. |
| `src/QuestManager.sol`                                                                                                    | `createQuest` validates + stores the threshold; `_verifyAttestation` becomes `_verifyAttestations(account, questId, deadline, signatures, threshold)` (loop: recover → role-check → distinctness → count; revert unless count ≥ threshold); nonce consumption + events as in §2.1.                                                                                          |
| `src/AgentGate.sol`, `src/Reputation.sol`, `src/Achievement.sol`                                                          | No changes.                                                                                                                                                                                                                                                                                                                                                                 |
| `script/DeployAgentHub.s.sol`                                                                                             | No changes (no new constructor args, no new roles).                                                                                                                                                                                                                                                                                                                         |
| Tests (`test/Attestation.t.sol`, `test/VerifierSecurity.t.sol`, `test/AttackSimulation.t.sol`, `test/QuestManager.t.sol`) | See §6. Existing single-signature tests must be updated to the new `bytes[]` call shape (mechanical), plus new threshold tests.                                                                                                                                                                                                                                             |

**ABI break (deliberate):** replacing the single-`bytes` function with
a `bytes[]` function breaks existing clients and the committed frontend
ABI. The alternative — keeping both entry points — was considered and
rejected: two completion paths for the same quest invite bypass
confusion (a threshold-2 quest completable through the legacy single-sig
path would silently void the threshold). One entry point, one rule.

## 4. Frontend + tooling changes

- `apps/web/lib/abis/QuestManager.ts`: re-exported from the new forge
  build (`export-abis.mjs`, zero-diff check re-run).
- `apps/web/lib/attestation.ts`: `check()` verifies an ARRAY of
  signatures (shape, recovery, distinctness, per-signer `hasRole`
  reads) against the quest's threshold; returns per-signer results.
- `AttestationForm.tsx` / `useAttestation.ts` /
  `useCompleteQuest.ts`: collect M signatures (paste M, or paste one
  and request the rest out-of-band), display "requires N verifier
  signatures" from the quest's public threshold, submit the array.
- `apps/web/scripts/sign-attestation.mjs`: NO change needed — each
  verifier signs the same digest independently with the existing
  tool; the user (or coordinator) collects the signatures.
- Docs: VERIFIER_SECURITY_SOP.md §6 (sketch → implemented spec +
  coordination flow), FINAL_DEPLOYMENT_CHECKLIST.md §7 item 4
  (close), frontend copy for the multi-signature flow.

## 5. Migration path (contracts are immutable — no proxy, no upgrade)

1. Implement + test on a branch; full regression battery green
   (Phase 7 equivalent).
2. Deploy the new QuestManager to **testnet first** (fresh deployment
   via the existing script — the deploy itself is unchanged; the new
   QuestManager bytecode carries the threshold logic). Old testnet
   attestations are invalid after redeploy (domain separator binds
   the verifying contract) — expected, testnet only.
3. Testnet smoke: create threshold-1 and threshold-2 quests; complete
   both paths; verify duplicate/insufficient reverts on-chain.
4. Update the frontend env to the new QuestManager address.
5. Mainnet: threshold ships with the FIRST mainnet deployment (there
   is no mainnet deployment yet, so no migration of live quests is
   needed). If mainnet ever deploys without threshold, adding it later
   means a full QuestManager redeploy + quest recreation — one more
   reason to land threshold BEFORE the first mainnet deploy.
6. Close R-010 only after the testnet smoke passes AND the mainnet
   gate item 4 is re-verified.

## 6. Test plan + estimate

**New Foundry tests (~18-22):**

- Happy path: threshold 2 with 2 distinct valid verifiers completes;
  threshold 3 with 3 completes; threshold 1 with 1 completes
  (regression of today's behavior).
- Rejects: 1 signature for a threshold-2 quest
  (`InsufficientAttestations`); same signer twice
  (`DuplicateAttestationSigner`); 2 valid + 1 unauthorized signer
  (reverts — junk anywhere fails the call); threshold 0 and
  threshold 4 at creation (`AttestationThresholdOutOfRange`).
- Invariants: nonce consumed exactly once per completion regardless
  of M; failed completion (quest full/ended) does not burn the nonce
  with M signatures; each signer gets an `AttestationUsed` event;
  revoked 2nd verifier invalidates the pair (role checked at
  verification time).
- Fuzz: random signature arrays (duplicates, wrong signers, wrong
  nonces) never complete a threshold quest without M distinct valid
  signers.
- Gas: record per-signature marginal cost (expect ~3k gas per extra
  ecrecover + calldata; assert the completion stays within a sane
  bound).

**Frontend tests (~8-10):** multi-signature `check()` (valid pair,
duplicate pair, one unauthorized, one malformed, threshold display),
form flow with 2 signatures, ABI parity re-check.

**E2E:** extend the wallet E2E attestation flow to a threshold-2
quest (two verifier keys signing the same digest on anvil).

**Estimate:** implementation ~half a focused session; tests + full
regression battery ~half a session; internal diff review + Slither ~
1 hour. No external audit is triggered by this change alone, but the
diff should be included in the commissioned pre-mainnet review
(R-012) — do not ship threshold to mainnet ahead of that review.

## 7. Risks (open, to carry into the implementation phase)

1. **Coordination UX:** collecting M signatures out-of-band is slower
   and can fail (one verifier offline). The nonce moves on ANY
   attested completion by the account, so a half-collected set goes
   stale if the user completes another attested quest first — the
   form must re-verify immediately before submit (it already does)
   and show a clear "signatures stale, re-collect" state.
2. **Threshold footgun:** verifier set shrinking below a live quest's
   threshold bricks the quest (§2.2). SOP mitigation only; no
   on-chain guard is possible with AccessControl.
3. **ABI break:** any external integrator or saved frontend build
   calling the old single-`bytes` function breaks at the next deploy.
   Mitigate with a changelog note + the fact that no mainnet
   deployment exists yet.
4. **Gas:** each extra signature costs ~3k gas + calldata; a 3-of-3
   completion is still small (< 15k gas over baseline) — not a
   blocker, but measure it in tests.
5. **False confidence:** threshold raises the bar; it does not make
   attestations true. The SOP (few named verifiers, hardware keys,
   rotation, monitoring, pause) remains the real control.

## 8. Decision required (user / team)

1. Adopt the recommended policy (threshold 2 for rewardPoints >
   1,000 or real-world-value badges; 1 otherwise), or set different
   values?
2. Implement before the testnet deployment (cleaner: one testnet
   deploy carries it) or after testnet smoke (smaller testnet scope,
   threshold lands with the mainnet deploy)? Recommendation: BEFORE
   the testnet deploy — the testnet smoke is the cheapest place to
   prove it, and it avoids a second QuestManager redeploy.
3. Who are verifiers 2 and 3? Threshold is meaningless with a
   1-person verifier set — the set must grow before any threshold
   quest is created.

## 9. Acceptance criteria (to close R-010)

- [ ] Threshold implementation merged with all new tests green and
      the full regression battery green (Foundry + Vitest + E2E +
      Slither).
- [ ] Testnet smoke: threshold-1 and threshold-2 quests created and
      completed on the live testnet; duplicate/insufficient reverts
      observed on-chain.
- [ ] SOP §6 updated from sketch to implemented spec; checklist §7
      item 4 re-verified and closed.
- [ ] Diff included in the commissioned external review (R-012).
- [ ] At least 3 verifiers granted before the first threshold-2
      quest is created on mainnet.
