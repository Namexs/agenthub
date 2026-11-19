# AGENTHUB — VERIFIER_ROLE Operations SOP

**Scope:** granting, rotating, and revoking `VERIFIER_ROLE` on
QuestManager, and the day-to-day duties of attestation verifiers.
**Applies to:** BSC testnet staging and (later) BSC mainnet.
**Related docs:** `QUEST_VALIDATION_DESIGN.md` §2.3 (attestation design),
`NEW_THREAT_MODEL.md` (T-ATT-01), `DEPLOYMENT_PLAN.md` (role wiring),
`SECURITY_DEPLOYMENT_GATE.md` (privilege model).

## 1. What a verifier is — and is not

An attestation proves **"an authorized verifier signed that this account
completed this quest"**. It does **not** prove the verifier told the truth.
A compromised or dishonest verifier can mint reputation points (and badges)
for anyone until its role is revoked. This is the project's largest
residual trust assumption (T-ATT-01) and the reason this SOP exists.

Rules that follow from that:

- **Few verifiers.** Start with one. Never more than three without a
  written justification recorded in the repo.
- **Named verifiers.** Every verifier address maps to exactly one named
  person or service, recorded in §7. No anonymous verifiers, no shared
  verifier keys.
- **Dedicated keys.** A verifier key signs attestations and nothing else.
  It must never hold funds, never be a deployer key, never be reused as a
  multisig signer key.
- **Hardware-backed keys.** Verifier keys live on a hardware wallet (or
  HSM for a service verifier). No plaintext keys on disk, no keys in
  password managers, no keys in CI, no keys in this repo.

## 2. Who can do what

| Action                              | Who                                | Delay    | Mechanism                                                          |
| ----------------------------------- | ---------------------------------- | -------- | ------------------------------------------------------------------ |
| Grant `VERIFIER_ROLE`               | Timelock (admin multisig proposes) | 2 days   | Timelock proposal → `QuestManager.grantRole(VERIFIER_ROLE, addr)`  |
| Revoke `VERIFIER_ROLE`              | Timelock (admin multisig proposes) | 2 days   | Timelock proposal → `QuestManager.revokeRole(VERIFIER_ROLE, addr)` |
| Pause QuestManager (emergency stop) | `PAUSER_ROLE` holder               | **None** | `QuestManager.pause()` — the fast path                             |
| Unpause QuestManager                | Timelock                           | 2 days   | Timelock proposal → `QuestManager.unpause()`                       |
| Sign attestations                   | Current `VERIFIER_ROLE` holders    | —        | Off-chain EIP-712 signing (§5)                                     |

The 2-day timelock delay applies to every role change. There is no fast
revocation: **pause is the emergency control**, revocation is the permanent
one. Both are needed in an incident (§4).

## 3. Granting a new verifier

Preconditions: the candidate's key is generated (§1 rules), the candidate
has read this SOP, and the address is confirmed out-of-band (the candidate
signs a challenge message with the key, or confirms the address in a
second channel — never trust an address pasted in one chat message).

1. Record the verifier in §7 (name, address, purpose, start date).
2. Admin multisig creates a timelock proposal:
   `grantRole(VERIFIER_ROLE, <address>)` on QuestManager.
3. Wait out the 2-day timelock delay; execute the proposal.
4. Verify on-chain: `QuestManager.hasRole(VERIFIER_ROLE, <address>)`
   returns true (read via BscScan or `cast call`).
5. The new verifier signs a test attestation for a test quest and a team
   member submits it — confirm the completion lands before announcing
   the verifier as active.

## 4. Emergency revocation (suspected compromise or dishonesty)

Time matters more than process here. A compromised verifier can mint
reputation continuously until stopped.

1. **Pause immediately.** Any `PAUSER_ROLE` holder calls
   `QuestManager.pause()`. This stops ALL quest completions (all kinds),
   including attested ones. No timelock delay. Announce the pause in the
   team channel with the time and reason.
2. **Preserve evidence.** Note the suspect verifier address, the time
   compromise was suspected, and any anomalous completions (query
   `AttestationUsed` events for the signer — every attestation is
   attributable on-chain).
3. **Propose revocation.** Admin multisig creates a timelock proposal:
   `revokeRole(VERIFIER_ROLE, <address>)`.
4. **Assess the damage while the timelock runs.** List every completion
   attested by the suspect signer since the suspected compromise time.
   There is no on-chain "undo" for points/badges — the response is
   governance (public note, and if needed, a new Reputation/Achievement
   deployment decision by the team; do not improvise this during the
   incident).
5. **Execute the revocation** after the 2-day delay. Verify on-chain:
   `hasRole(VERIFIER_ROLE, <address>)` returns false.
6. **Unpause via a second timelock proposal** (`unpause()`). Note the
   timeline: pause is instant, but unpause needs its own 2-day proposal,
   and it must execute only AFTER the revocation — worst case the
   platform is paused for ~4 days. Do not shortcut this: unpausing before
   the revocation executes would re-enable the compromised verifier.

## 5. Routine rotation (planned, no incident)

Rotate on a schedule (every 90 days) and on every personnel change.
Rotation is safe by construction: nonces are per-account, not per-verifier,
so a fresh attestation from the new signer uses the same current nonce.

1. Generate the new verifier key (§1 rules) and confirm the address
   out-of-band (§3).
2. **Grant the new verifier first** (timelock proposal, 2-day delay,
   verify on-chain). Both verifiers are active during the overlap.
3. **Stop issuing from the old signer.** Announce the cutover: from this
   point, all new attestations come from the new signer.
4. **Drain in-flight attestations.** Attestations already signed by the
   old signer remain valid until used, expired (max 7 days), or revoked.
   Allow up to 7 days for holders to submit them — or ask holders to
   request a fresh attestation from the new signer (same nonce; the old
   attestation becomes unusable only after revocation, so a user who
   submits the old one first still completes normally).
5. **Revoke the old verifier** (timelock proposal, 2-day delay, verify
   on-chain). The moment revocation executes, every outstanding
   attestation from the old signer stops working — revocation is checked
   at verification time, so there is no grace period after this point.
6. Update §7 (old verifier: end date + reason; new verifier: active).
7. Securely destroy the old key material (hardware wallet reset / HSM
   key deletion) once revocation is confirmed.

## 6. Issuing an attestation (verifier duty)

1. **Verify the task first.** The verifier must actually check the
   off-chain activity (event attendance list, course record, post URL —
   whatever the quest requires). Signing without checking is the failure
   this whole design exists to prevent.
2. **Read the current nonce:** `QuestManager.nonces(account)`.
3. **Pick a deadline:** no more than 7 days out
   (`MAX_ATTESTATION_LIFETIME`); prefer hours, not days, for routine
   attestations — a shorter deadline bounds the damage if the signature
   leaks.
4. **Sign the EIP-712 struct** `Attestation(account, questId, nonce,
deadline)` in the domain `("AGENTHUB QuestManager", "1", chainId,
QuestManager address)`. Use the project's signing tool
   `apps/web/scripts/sign-attestation.mjs` (local-only: the key is read
   from `VERIFIER_PRIVATE_KEY`, never leaves your machine, and the tool
   refuses to sign unless the key holds `VERIFIER_ROLE` on-chain — see
   its header comment for the full trust assumptions). Never use a raw
   `eth_sign` of a hash — the domain binding is what prevents
   cross-chain and cross-contract replay. A production service verifier
   must sign with a hardware wallet or HSM instead of a plaintext env
   key (§1).
5. **Deliver the signature to the user** over the normal channel. The
   user submits it via `completeQuestWithAttestation`.
6. **Never sign:** an attestation for an account you cannot identify, a
   quest you cannot confirm, a deadline beyond 7 days, or a second
   attestation for the same account — for ANY quest, not just the same
   one — without re-reading the nonce first. The nonce is global per
   account: if the user completed another attested quest since your
   last signing, the nonce has moved and your second signature would
   be stale. One pending attestation per account at a time; re-read
   `nonces(account)` before every signature.

### 6.1 Threshold attestations (M-of-N) — Phase 6 (R-010), implemented

A quest declares an `attestationThreshold` (1–3) at creation,
**immutable afterwards**. A threshold-M quest completes only when the
submitted signature array carries at least M **distinct**
`VERIFIER_ROLE` signers over the **same** digest (same account,
questId, nonce, deadline). All M verifiers sign the same attestation
struct — no new EIP-712 type, no domain change; each verifier signs
independently with the existing tool
(`apps/web/scripts/sign-attestation.mjs`), and the user (or a
coordinator) collects the signatures and submits them together via the
AttestationForm, which shows "requires N verifier signatures" from the
quest's public threshold.

**Threshold policy.** Threshold 2 for any attested quest with
rewardPoints > 1,000 or a badge with real-world value; threshold 1 for
everything else. Threshold 3 is available but needs a 3-verifier set
and slower coordination — use it only for the highest-value quests.

**Coordination flow (threshold 2).**

1. The coordinator (or the user) reads `nonces(account)` **once** and
   picks one deadline, then shares the same
   (account, questId, nonce, deadline) with both verifiers.
2. Each verifier independently verifies the task (§6 step 1) and signs
   the same digest. A verifier who cannot confirm the task must NOT
   sign — one missing signature blocks the completion, by design.
3. The user pastes both signatures + the deadline into the form, which
   verifies each signer client-side (recovery + `VERIFIER_ROLE`) before
   submit is enabled. The contract re-verifies everything on-chain:
   a duplicate signer reverts (`DuplicateAttestationSigner`), fewer
   than M distinct verifiers reverts (`InsufficientAttestations`), and
   a junk signature anywhere in the array reverts the whole call.
4. **Stale sets:** the nonce is global per account, so if the user
   completes another attested quest while a set is half-collected, the
   nonce moves and the whole set goes stale — re-collect from step 1.
   Keep the coordination window short (hours, not days).

**Footguns (read before granting or revoking).**

- **Grant first:** grant at least the threshold number of verifiers
  **before** creating a threshold quest. A threshold-2 quest with only
  one verifier can never complete.
- **Do not revoke below the threshold:** OpenZeppelin `AccessControl`
  cannot enumerate role holders, so the contract **cannot** check that
  threshold ≤ live verifier count. If verifiers are revoked until
  fewer than M remain, every live threshold-M quest becomes
  uncompletable ("bricked"). Before any revocation, check the highest
  threshold among live Attested quests: either keep at least that many
  verifiers, or deactivate the affected quests first (the admin can
  always deactivate a bricked quest and recreate it at threshold 1).
- **Rotation on threshold quests:** grant the replacement verifier
  before revoking the old one (§5 order), and re-issue any in-flight
  attestation sets that included the old signer — its signature stops
  working the moment its role is revoked.

**Monitoring:** `AttestationUsed` is emitted once per distinct signer,
so the per-signer review in §8 works unchanged — a threshold-2
completion appears as two events, one per verifier.

## 7. Verifier registry

Keep this table current. It is the off-chain record of who may attest;
the on-chain truth is `hasRole(VERIFIER_ROLE, …)` — the two must agree.

| Verifier     | Address | Purpose | Active since | Active until | Notes                                                                                                   |
| ------------ | ------- | ------- | ------------ | ------------ | ------------------------------------------------------------------------------------------------------- |
| _(none yet)_ | —       | —       | —            | —            | First verifier is set at deployment via the `VERIFIER` env var (optional); add the row here when it is. |

## 8. Monitoring (what to watch)

- **Completion spikes** on Attested quests (count + points per hour vs
  baseline) — a spike from one verifier is the compromise signal.
- **`AttestationUsed` events** per signer — every attestation is
  attributable; the signer is an indexed topic (Phase 6), so a
  per-signer query is a single topic filter. Review weekly.
- **Failed `completeQuestWithAttestation` calls** (`UnauthorizedVerifier`
  reverts) — a burst may mean a revoked signer is still signing, or a
  user holds a stale attestation. `InsufficientAttestations` /
  `DuplicateAttestationSigner` reverts mean a threshold set was
  submitted incomplete or with a repeated signer — usually a
  coordination failure, not an attack; check the quest's threshold
  before escalating.
- **Role events** (`RoleGranted` / `RoleRevoked` for `VERIFIER_ROLE`) —
  any grant/revoke outside a planned change is an incident.
- **Pause events** — any pause triggers the incident process (§4).

## 9. Checklists

### Grant

- [ ] Key generated per §1, address confirmed out-of-band
- [ ] §7 registry row added
- [ ] Timelock proposal created + executed (2-day delay observed)
- [ ] `hasRole` verified on-chain
- [ ] Test attestation completed end-to-end

### Rotate

- [ ] New key generated per §1, address confirmed out-of-band
- [ ] New verifier granted + verified (§3 steps 2–5)
- [ ] Old signer stops issuing; cutover announced
- [ ] In-flight attestations drained (≤ 7 days) or re-issued
- [ ] Old verifier revoked + verified on-chain
- [ ] §7 updated; old key material destroyed

### Emergency revoke

- [ ] QuestManager paused immediately (time + reason logged)
- [ ] Evidence preserved (signer, timeline, anomalous completions)
- [ ] Revocation proposed via timelock
- [ ] Damage assessed (completions since suspected compromise)
- [ ] Revocation executed + verified on-chain
- [ ] Unpause proposed + executed only after revocation
- [ ] Post-incident note written (what happened, what changed)
