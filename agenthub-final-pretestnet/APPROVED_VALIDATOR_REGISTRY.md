# AGENTHUB — Approved Validator Registry (Phase 5)

**Date:** 2026-11-19. **Scope:** `src/QuestManager.sol`,
`src/interfaces/IQuestManager.sol`, `src/validators/`,
`test/ValidatorRegistry.t.sol`, `test/Validator.t.sol`,
`test/ValidatorAllowlist.t.sol`, `docs/QUEST_VALIDATION_DESIGN.md`.

## 1. What changed

The pre-testnet cleanup turned the "creator picks any validator"
caveat into an admin allowlist (`mapping(address => bool)`). Phase 5
upgrades it into a **registry**: every approved validator has an
on-chain identity.

```solidity
struct ValidatorInfo {
    string name;           // e.g. "TokenBalanceValidator"
    string version;        // e.g. "1.0.0"
    string documentation;  // docs URI or description of what it checks
    uint256 approvedAt;    // block.timestamp of (re-)approval
    bool approved;
}
```

- `approveValidator(validator, name, version, documentation)` —
  admin (timelock) only; reverts on zero/code-less addresses AND on
  empty metadata (`InvalidValidatorMetadata`). Re-approval overwrites
  metadata + `approvedAt` (a fresh review, not a rubber stamp).
- `revokeValidator(validator)` — admin (timelock) only; sets
  `approved = false` and **keeps the metadata** as an audit trail.
- `emergencyRevokeValidator(validator)` — `PAUSER_ROLE` only, no
  timelock delay; same effect. Re-approval still requires the admin.
- `validatorInfo(validator)` — public getter returning the struct.
- `approvedValidators(validator)` — kept as a backwards-compatible
  view over the registry (same ABI as before).

## 2. The staticcall hardening (the real Phase 5 fix)

The remediation report documented an honest caveat: `view` is a
compiler annotation, not on-chain enforcement — a validator could
write state or reenter. Phase 5 closes that gap. `_completeQuest` no
longer calls `validate()` directly; it calls `_validateOnChain`:

1. **STATICCALL** to `IQuestValidator.validate(account, questId)`.
   Any state change inside the validator (storage write, reentry into
   a state-changing function) reverts the whole call at the EVM level.
2. **Revert → `ValidatorCallFailed(validator)`.** The completion fails
   closed with the contract's own uniform error instead of propagating
   the validator's arbitrary revert data.
3. **Returndata must be exactly 32 bytes and the word must be 0 or 1**,
   else `InvalidValidatorReturndata(validator)` — no ABI-decoding
   panic, no misread garbage.

Proven by test: `StateChangingValidator` (writes `counter += 1` inside
`validate()`) is blocked — completion reverts, `counter` stays 0.
`InvalidBoolValidator` (returns the word 2) reverts with the dedicated
error. The reentrant validator still cannot double-award: its reentry
dies at the `nonReentrant` guard before any state change, is caught by
its own try/catch, and the outer completion awards exactly once.

**What the staticcall does NOT fix:** a validator can still return the
WRONG ANSWER (e.g. `AlwaysTrueValidator` rubber-stamps every
completion). That is a trust decision, not a code property — it is
gated by admin approval (the registry), not by the call mechanism. An
admin who approves a rubber-stamp validator has made an explicit,
on-chain, auditable mistake.

## 3. Revocation policy (explicit, implemented, tested)

Revocation — admin or emergency — is **immediate and total**:

- New quests cannot use the validator (`ValidatorNotApproved` at
  creation).
- Completions of EXISTING quests using it revert immediately
  (`ValidatorNotApproved` at completion). There is **no grace period**
  and no migration path: a quest whose validator is revoked is frozen
  until the validator is re-approved.
- If a quest must keep running, the creator (or admin) deactivates it
  and creates a new quest with a different, approved validator.
  Completions already awarded are never rolled back.

Rationale: a grace period would let a compromised validator keep
awarding points/badges after the compromise is known. Freezing is the
safe default; the cost is one deactivated quest, not a drained
reputation system.

## 4. Approval process (operational)

Before approving a validator instance, the admin MUST:

1. Read the validator's source and confirm what condition it checks.
2. For `TokenBalanceValidator`: verify the token address and threshold
   on-chain (read `token()` / `threshold()` — they are immutable and
   public).
3. Confirm the validator is not a proxy (or, if it is, review the
   implementation + upgrade authority).
4. Record name, version, and documentation in the approval transaction.
5. Prefer approving on testnet first and completing a test quest.

## 5. Registry contents

No validator instance is deployed yet — the registry is populated by
timelock proposals at/after deployment. The reference implementation
ready for review is:

| Implementation          | What it checks                           | Notes                                                                                                |
| ----------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `TokenBalanceValidator` | completer holds ≥ threshold of an ERC-20 | Deploy one instance per (token, threshold); immutable params; fail-closed on reverting/garbage token |

## 6. Tests

- `ValidatorRegistryTest` (11 new): metadata stored, empty name /
  version / docs rejected, revocation keeps metadata, re-approval
  updates metadata, emergency revoke blocks completions + new quests,
  non-pauser cannot emergency-revoke, emergency revoke idempotent,
  state-changing validator blocked, invalid-bool validator reverts.
- `ValidatorTest` (updated): reverting validator now expects
  `ValidatorCallFailed`; garbage validator now expects
  `InvalidValidatorReturndata`. The behavior change is intentional
  (uniform contract errors instead of propagated reverts / panics);
  fail-closed properties are unchanged (0 points, no completion, no
  partial state).
- `ValidatorAllowlistTest` (13, updated call sites): approved /
  unapproved / revoked / zero / EOA at creation + completion.
- Full suite after Phase 5: **250/250** (Phase 2 baseline 239 + 11 new).
  Log: `logs/phase5-full-suite.log`, `logs/phase5-validator-tests.log`.
