# Quest Validation Design

**AGENTHUB — Security Review Remediation (TEMUAN 1)**
**Status:** Implemented and tested (193/193 Foundry tests).
**Baseline:** `c568ee0` (120 tests). **Remediation commits:** `655cbb2` (TEMUAN 1 + 3),
`8c5122f` (TEMUAN 2), `7d3d386` (TEMUAN 4).

## 1. The problem

Before this remediation, `QuestManager.completeQuest()` treated the act of
calling it as proof that the quest's task was done. It checked only:

- the caller holds an Agent ID,
- the quest is active and inside its time window,
- the cap / duplicate / cooldown rules.

Nothing verified that the user had performed any external activity. Any quest
whose real-world task lived off-chain (follow an account, attend an event,
complete a course) was completable by anyone who could call the function —
reputation points and badges were mintable on demand. The UI could show
"complete this task", but the contract could not tell a genuine completion
from a bare call.

## 2. The fix: every quest declares how completion is proven

Every quest now carries a `ValidationKind` (`IQuestManager.sol:29-33`),
chosen at creation and immutable afterwards:

```solidity
enum ValidationKind {
    CheckIn,   // Explicit self-check-in: the call IS the activity.
    OnChain,   // A validator contract must confirm an on-chain condition.
    Attested   // An authorized verifier must attest off-chain completion.
}
```

`createQuest` takes the kind (plus a `validator` address, used only by
`OnChain`) — `QuestManager.sol:98-151`. The kind rules are enforced at
creation:

| Kind | Validator address | Completion path |
|---|---|---|
| `CheckIn` | must be `address(0)` | `completeQuest` |
| `OnChain` | must be a contract (code length > 0) | `completeQuest` (validator checked live) |
| `Attested` | must be `address(0)` | `completeQuestWithAttestation` only |

`completeQuest` reverts with `AttestationRequired` on an Attested quest
(`QuestManager.sol:153-160`), and `completeQuestWithAttestation` reverts with
`QuestNotAttested` on a non-Attested quest (`QuestManager.sol:168-178`).
There is no way to complete an Attested quest without an attestation, and no
way to smuggle an attestation into a CheckIn/OnChain quest.

### 2.1 CheckIn — honest self-reporting

A CheckIn quest is a daily/weekly check-in or any activity whose only
observable on-chain fact is "this holder showed up". The call is the
activity, and the UI must label it exactly that way — never as proof of an
external task. Caps, duplicates, and cooldowns still bound farming (see §5).

### 2.2 OnChain — validator contracts

An OnChain quest points at a validator implementing `IQuestValidator`:

```solidity
interface IQuestValidator {
    /// @notice True only when `account` satisfies the quest's on-chain condition.
    function validate(address account, uint256 questId) external view returns (bool);
}
```

At completion time — in the checks phase, after the cheap checks and before
any state change — QuestManager calls `validator.validate(msg.sender,
questId)` and reverts with `OnChainValidationFailed` when it returns false
(`QuestManager.sol:233-238`). The condition is re-checked live on **every**
completion: a user who held the required token yesterday but sold it today
cannot complete today (proven by `Validator.t.sol`).

**Reference validator:** `TokenBalanceValidator` (`src/validators/`) checks
`balanceOf(account) >= threshold` for a configured ERC-20, using a low-level
staticcall with a manual returndata-length check — the same fail-closed
pattern as AgentGate's SEC-001 fix. A reverting or malformed token makes
validation fail, never pass.

**Trust caveat (documented, not hidden):** the quest creator chooses the
validator. A validator that always returns `true` makes the quest equivalent
to a CheckIn — this is proven by test, not hidden. The code-length check in
`createQuest` proves the validator is a contract, NOT that it is trustworthy.
Trustworthy validators are a deployment/creator-governance concern: the
project should maintain a curated list of reviewed validators and creators
should be accountable for their choices. See `DEPLOYMENT_PLAN.md` §4.

**Reentrancy note:** `view` on the interface is not enforceable on-chain —
an attacker can deploy a validator whose `validate` is not view and tries to
re-enter. The defense is structural, not the interface keyword:
`completeQuest` is `nonReentrant`, and the validator call happens in the
checks phase, before any state is written. A reentrant validator therefore
reverts (proven by `test_ReentrantValidatorCannotDoubleAward` — exactly one
award). QuestManager also never trusts a validator's return value beyond the
single boolean.

### 2.3 Attested — EIP-712 verifier attestations

For tasks that happen off-chain (an event, a course, a social action), a
human or service verifier attests that the task was done. The attestation is
an EIP-712 signature over:

```
Attestation(address account, uint256 questId, uint256 nonce, uint256 deadline)
```

Domain: `EIP712("AGENTHUB QuestManager", "1")` — bound to this contract's
address and this chain's id by the EIP-712 domain separator
(`QuestManager.sol:43-57`, `187-200`).

Verification (`_verifyAttestation`, `QuestManager.sol:181-208`):

1. **Deadline:** `deadline` must be in the future (`AttestationExpired`)
   and no more than `MAX_ATTESTATION_LIFETIME` (7 days) ahead
   (`AttestationDeadlineTooFar`). A stale or open-ended attestation cannot
   be stockpiled.
2. **Nonce:** `nonces[account]` is a global per-account counter, incremented
   on every successful verification. The attestation binds to the exact
   nonce, so each signature is usable exactly once.
3. **Recovery:** `ECDSA.tryRecover` — malleable signatures (flipped `s`) are
   rejected, and a zero/invalid signer is rejected. A short or empty
   signature reverts, never recovers a wrong address.
4. **Authorization:** the recovered signer must hold `VERIFIER_ROLE`
   (`UnauthorizedVerifier` otherwise). Role checks happen at verification
   time, so **revoking a verifier invalidates its outstanding attestations
   immediately** — no attestation outlives its signer's authority.
5. **Binding:** the struct hash binds account + questId + nonce + deadline;
   the domain separator binds chainId + verifying contract. The same
   signature cannot be replayed on another chain, another QuestManager
   deployment, another quest, or another account.
6. **Ordering:** the nonce is consumed only after the signature is verified,
   and completion effects run after that — a failed completion (e.g. the
   quest filled up first) does **not** burn the nonce, so the user can retry
   with the same attestation.

**Signer management / rotation:** `VERIFIER_ROLE` is granted and revoked by
the admin (the 2-day timelock after deployment). Rotation is: grant the new
verifier, then revoke the old one — outstanding attestations from the old
signer stop working the moment its role is revoked. There is no on-chain
"verifier registry" beyond the role; off-chain, the project keeps the list
of active verifiers and their key-hygiene requirements (hardware-backed keys,
no shared keys, immediate revocation on suspected compromise).

**What attestation does NOT prove:** the verifier is trusted. An attestation
proves "an authorized verifier signed that this account completed this
quest" — it does not prove the verifier told the truth. A compromised or
dishonest verifier can mint reputation for anyone until its role is revoked.
Mitigations: few verifiers, per-verifier accountability (every attestation is
on-chain and attributable to a signer address), fast revocation via the
PAUSER_ROLE + admin, and monitoring for anomalous completion spikes. This
residual trust is recorded in `NEW_THREAT_MODEL.md` (T-ATT-01).

## 3. What the frontend must show

The kind is part of the quest's public data (`Quest.validationKind`). The UI
must render it honestly:

- CheckIn → "Check-in — no external proof required".
- OnChain → the validator's human-readable condition (e.g. "Hold ≥ 100 TOKEN").
- Attested → "Verified by an AGENTHUB verifier" + the verifier's address.

A quest must never be displayed as "verified" when its kind is CheckIn.

## 4. Migration note

Quests created before this change have no kind. The remediation changes the
`createQuest` signature, so pre-existing quests do not exist on any
deployment — nothing is deployed yet, so there is no migration. Test suites
were updated to create quests with the explicit `CheckIn` kind (see
`REGRESSION_RESULTS.md` §3).

## 5. Farming bounds (unchanged, now per kind)

All kinds share the existing anti-farming rules: OneTime/Community quests
are completable once per account; Daily/Weekly quests enforce a cooldown;
`maxCompletions` caps total awards. Attested farming is additionally bounded
by the verifier (each completion needs a fresh attestation) and by the
cooldown. OnChain farming is bounded by the live condition. None of this
prevents a determined user from completing many *different* quests — that is
the product working as intended.
