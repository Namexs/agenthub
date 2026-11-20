# AGENTHUB — Verifier Security SOP (Phase 6)

**Date:** 2026-11-19. **Companion to:** `docs/VERIFIER_ROLE_SOP.md`
(operations: grant / rotate / revoke / checklists). This document is the
**security** layer: the Phase 6 audit of the attestation mechanism, key
management requirements, compromise handling, monitoring specifics, and
the multisig-attestation design for high-value quests.

## 1. Phase 6 audit — summary

The attestation implementation (`QuestManager._verifyAttestation` +
`completeQuestWithAttestation`) was re-audited line by line in Phase 6.
**Verdict: no vulnerability found.** Every attack in the table below was
checked against the code and, where not already covered, against a new
regression test (`test/VerifierSecurity.t.sol`).

| #   | Attack / failure                           | Verdict | Mechanism                                                                                                                                |
| --- | ------------------------------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Replay the same attestation                | Blocked | Per-account nonce, consumed on success; a replay signs a stale nonce and recovers a different signer                                     |
| 2   | Cross-chain replay                         | Blocked | EIP-712 domain separator binds chainId (OZ EIP712, fork-aware)                                                                           |
| 3   | Cross-contract replay                      | Blocked | Domain binds verifyingContract (this QuestManager)                                                                                       |
| 4   | Wrong account / quest                      | Blocked | Struct hash binds account + questId                                                                                                      |
| 5   | Front-run someone else's attestation       | Blocked | `_verifyAttestation(msg.sender, …)` — the account IS the submitter; a stolen signature recovers a garbage signer with no role (new test) |
| 6   | Verifier completes a quest FOR a user      | Blocked | Same binding — the verifier submitting as msg.sender fails the same way (new test)                                                       |
| 7   | Signature malleability (high-S)            | Blocked | `ECDSA.tryRecover` rejects malleable signatures                                                                                          |
| 8   | Malformed / empty / short signature        | Blocked | tryRecover error → `InvalidAttestationSignature`                                                                                         |
| 9   | Expired attestation                        | Blocked | `deadline < block.timestamp` → `AttestationExpired`                                                                                      |
| 10  | Over-long deadline                         | Blocked | `deadline > now + 7 days` → `AttestationDeadlineTooFar`                                                                                  |
| 11  | Revoked verifier's outstanding attestation | Blocked | `VERIFIER_ROLE` is checked at completion time, not at signing time                                                                       |
| 12  | Nonce griefing (burn someone's nonce)      | Blocked | A nonce can only be consumed by the account itself submitting a valid attestation                                                        |
| 13  | Nonce burned by a failed completion        | Blocked | A revert anywhere rolls back the nonce increment — the same attestation can be retried (tested)                                          |
| 14  | Attestation for a non-holder               | Blocked | `_completeQuest` calls `gate.requireAgentHolder(msg.sender)`                                                                             |
| 15  | Reentrancy through the attestation path    | Blocked | `nonReentrant` on both entry points + CEI ordering                                                                                       |

**One improvement made in Phase 6:** `AttestationUsed` now carries the
signing verifier as an indexed third topic (`account, questId, nonce,
signer`). Monitoring can now filter completions by signer with a single
topic filter instead of correlating signatures off-chain. The event
assertion in `AttestationTest` and the new `VerifierSecurityTest`
(attribution to a second verifier) pin this.

**What the audit did NOT find:** no issue with the nonce scheme, the
deadline bounds, the domain binding, or the role check. The remaining
risk is not cryptographic — it is trust: a verifier can attest anything
until revoked (T-ATT-01). The rest of this document manages that risk.

## 2. Key management

The ops SOP (§1) sets the rules: few verifiers, named verifiers,
dedicated keys, hardware-backed keys. The security requirements behind
those rules:

- **Generation ceremony.** A verifier key is generated on the hardware
  device itself (never on a general-purpose computer, never from a
  browser extension's seed). The address is confirmed out-of-band
  (challenge signature or a second channel) before the grant proposal.
- **Storage tiers.** (1) Hardware wallet / HSM — the only acceptable
  home for a verifier key. (2) Nothing else: no plaintext on disk, no
  password manager entry, no CI secret, no repo file, no chat message.
  A verifier key that has ever touched a clipboard or a screenshot is
  treated as compromised and rotated.
- **One key, one job.** A verifier key signs attestations and nothing
  else. It holds no funds (gas is paid by the user submitting the
  attestation, not the verifier), is never a deployer key, and is never
  a multisig signer key. Key reuse across roles is how one compromise
  becomes two.
- **Key inventory.** The registry in `VERIFIER_ROLE_SOP.md` §7 is the
  off-chain record; the on-chain truth is `hasRole(VERIFIER_ROLE, …)`.
  Reconcile the two monthly — a role holder not in the registry is an
  incident.
- **No service-account shortcuts.** If attestations are issued by a
  service (not a person), the signing key lives in an HSM/KMS with
  access logging, and the service's signing endpoint requires
  authentication + rate limits. A service verifier that signs on any
  unauthenticated request is a reputation printer.

## 3. Rotation

See `VERIFIER_ROLE_SOP.md` §5 (grant-first → drain ≤ 7 days → revoke).
Security notes:

- Rotate on schedule (every 90 days) AND on every personnel change,
  AND after any suspected exposure — the cost of a rotation is one
  timelock proposal; the cost of a stale key is unbounded.
- During the overlap window both verifiers are active. That is safe:
  nonces are per-account, not per-verifier, so a fresh attestation
  from the new signer uses the same current nonce.
- After revocation, destroy the old key material (hardware reset / HSM
  deletion) and record the destruction in the registry.

## 4. Compromise handling

See `VERIFIER_ROLE_SOP.md` §4 for the procedure (pause → preserve
evidence → propose revocation → assess damage → execute → unpause).
Security additions:

- **Damage assessment query.** List every `AttestationUsed` event with
  the suspect signer as topic 3 since the suspected compromise time.
  For each: account, quest, points awarded, badge issued. There is no
  on-chain "undo" — the response is governance (public note; a team
  decision on whether the affected points/badges stand, or whether a
  fresh Reputation/Achievement deployment is warranted). Do not improvise
  this during the incident.
- **Assume the worst window.** If the compromise time is unknown, assess
  from the verifier's grant date. A verifier that was compromised from
  day one has been able to mint reputation the whole time.
- **Do not unpause early.** Unpause needs its own 2-day proposal and
  must execute only AFTER the revocation. Worst case ~4 days paused.
  Unpausing before revocation re-enables the compromised verifier.
- **Post-incident.** Write the note (what happened, what changed), rotate
  ALL verifier keys (not just the compromised one — a breach of one
  signing environment may implicate others), and review the monitoring
  alerts that did or did not fire.

## 5. Monitoring (specifics)

On top of `VERIFIER_ROLE_SOP.md` §8:

- **`AttestationUsed` per signer (topic filter).** The `signer` topic
  (topic 3) makes per-verifier attribution a single log query. Alert
  on: any single signer attesting more than N completions per hour
  (set N from the testnet baseline — start at 10/hour and tune), and
  any attestation from a signer NOT in the registry (should be
  impossible — if it happens, the role was granted outside process).
- **`UnauthorizedVerifier` revert bursts.** A burst means a revoked
  signer is still signing, or users hold stale attestations. Either
  way, investigate within 24 hours.
- **Role events.** `RoleGranted` / `RoleRevoked` for `VERIFIER_ROLE`
  outside a planned change is an incident — page the team, don't just
  log it.
- **Pause events.** Any pause triggers the incident process.
- **Weekly review.** A human reviews the per-signer attestation counts
  and the registry reconciliation. Monitoring that nobody reads is not
  monitoring.

## 6. Multisig / threshold attestation (implemented, Phase 6 / R-010)

**Status: IMPLEMENTED (Phase 6, 2026-11-19).** Single-verifier
attestation is proportionate for testnet and for low-value quests (the
blast radius of one compromised verifier is bounded by the pause
control + the 7-day attestation lifetime + the per-quest reward cap of
10,000 points). For high-value attested quests (large point rewards,
rare badges, or quests whose completion gates real-world benefits),
threshold M-of-N attestation is now available — and the mainnet gate
(FINAL_DEPLOYMENT_CHECKLIST.md §7 item 4) requires it before any such
quest goes live.

- **Scheme (as implemented).** The attestation struct gained no new
  fields; `completeQuestWithAttestation` accepts
  `bytes[] calldata signatures` and requires at least M distinct
  `VERIFIER_ROLE` signers over the same digest (same
  account/quest/nonce/deadline). Distinctness is enforced by comparing
  recovered addresses pairwise (O(M²) is fine for M ≤ 3); a duplicate
  signer reverts (`DuplicateAttestationSigner`), fewer than M distinct
  verifiers reverts (`InsufficientAttestations`), and the array is
  capped at `MAX_ATTESTATION_SIGNATURES` (5). The nonce is consumed
  exactly once per completion regardless of M, and `AttestationUsed`
  is emitted once per distinct signer (per-signer monitoring in §5
  works unchanged).
- **Threshold policy — ENFORCED ON-CHAIN (Phase 8, PH7-H01 / PH7-M02).**
  Per-quest `attestationThreshold` (1–3), set at creation, immutable
  afterwards. Threshold 2 for rewardPoints > 1,000 or a badge classified
  high-value (`Achievement.isBadgeHighValue`, set by `BADGE_MANAGER_ROLE`
  via `setBadgeHighValue`); 1 otherwise. `createQuest` reverts
  (`InsufficientAttestations(threshold, 2)`) if an Attested quest
  violates the policy — the policy is no longer SOP-only. It applies to
  Attested quests only: other kinds store a threshold but never enforce
  it at completion. The threshold is part of the quest's public data,
  so the frontend shows "requires N verifier signatures".
- **Cost.** Each additional signature is one more `ecrecover` (~3k
  gas) plus the UX cost of collecting M signatures (the verifiers sign
  the same digest independently; the user or a coordinator collects
  them — see `VERIFIER_ROLE_SOP.md` §6.1 for the coordination flow).
- **What it does NOT fix.** M-of-N stops a SINGLE compromised verifier;
  it does not stop M colluding verifiers, and it does not make a
  verifier honest — it only raises the bar. The pause control and the
  SOP remain the backstop. It also does not fix verifier availability:
  a threshold quest needs M verifiers to sign the same nonce+deadline
  within the coordination window, and the nonce moves on ANY attested
  completion by the account, so a half-collected set goes stale.
- **Footgun — now guarded on-chain (Phase 8, PH7-M01).**
  QuestManager counts live verifiers (`verifierCount()`) and tracks the
  highest threshold among live Attested quests
  (`highestLiveThreshold()`). Revoking — or renouncing — `VERIFIER_ROLE`
  reverts (`RevocationWouldBrickQuest`) while it would leave fewer
  verifiers than that threshold, and `createQuest` reverts
  (`InsufficientVerifiers`) when an Attested quest's threshold exceeds
  the live verifier count. Recovery when a revoke is blocked:
  deactivate the affected quests first, or grant a replacement verifier
  first (`VERIFIER_ROLE_SOP.md` §6.1). An expired-but-still-active quest
  still counts toward the guardrail until deactivated.
- **Closing R-010.** Implementation alone does not close R-010: the
  full regression battery and the testnet smoke (threshold-1 and
  threshold-2 quests created and completed on the live testnet;
  duplicate/insufficient reverts observed on-chain) are still required
  — see the remediation plan §9 and FINAL_DEPLOYMENT_CHECKLIST.md §7
  item 4.

## 7. Residual risks (honest list)

1. **T-ATT-01 (unchanged):** a verifier can attest anything until
   revoked. Mitigated by: few named verifiers, hardware keys, rotation,
   monitoring, pause. Not eliminated — it cannot be, by design.
2. **No on-chain undo:** points/badges awarded by a compromised
   verifier cannot be clawed back on-chain. The response is governance.
3. **Pause is the only fast control** (and it stops ALL completions,
   not just attested ones). Worst case ~4 days paused in a full
   incident cycle.
4. **Off-chain verification quality** is outside the contract's reach:
   a verifier who signs without checking is a process failure, not a
   code failure. The SOP (§6 of the ops doc) is the control.
