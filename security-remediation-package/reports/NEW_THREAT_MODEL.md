# New Threat Model (post-remediation)

**AGENTHUB — replaces the threat assumptions changed by the remediation.**
**Date:** 2026-11-19. **Baseline:** `docs/SECURITY_THREAT_MODEL.md`
(pre-remediation). **Remediation:** see `REMEDIATION_REPORT.md`.

This document lists the threats that are new, changed, or closed by the
remediation. Threats unchanged from the original model (Agent ID holder
spoofing via a compromised Agent ID contract, timelock admin abuse, frontend
phishing, etc.) are NOT repeated here — read the original model for those.

## Closed threats

| ID | Threat | Closed by |
|---|---|---|
| T-QUEST-01 | Completing a quest without doing the task (bare `completeQuest` call awarded points + badges) | ValidationKind: Attested quests require an EIP-712 attestation; OnChain quests require a live validator check; CheckIn quests are explicitly labeled self-check-in. |
| T-GATE-01 | AgentGate deployed against the wrong ERC-721 on mainnet, trusting its holders as Agent ID holders | Mainnet pins `OFFICIAL_AGENT_ID` (`AgentGate.sol:55-56`); chain allowlist {56, 97, 31337}; deployment script enforces the same at the script level. |
| T-DEPLOY-01 | Manual deployment wiring errors (wrong roles, deployer keeps admin) | `DeployAgentHub.s.sol` deploys + wires + verifies in one run; `_verifyWiring` reverts on any mismatch; deployer renounces everywhere. |
| T-DEPLOY-02 | Accidental mainnet deployment (wrong `--rpc-url`) | `CONFIRM_MAINNET_DEPLOY=true` opt-in required on chain 56; without it the script reverts before any broadcast. |

## New threats introduced by the remediation

### T-ATT-01 — Dishonest or compromised verifier (Attested quests)
**Severity: High (residual, accepted with controls).**
An attestation proves "an authorized verifier signed this completion" — not
that the verifier told the truth. A compromised verifier key can mint
reputation/badges for arbitrary accounts until revoked.
**Controls:** few verifiers; role checked at verification time (revocation is
instant); every attestation is on-chain and attributable to a signer address;
7-day max attestation lifetime limits stockpiling; PAUSER_ROLE can freeze
completions; monitoring for completion spikes. **Residual:** the trust in
verifiers is unavoidable for off-chain tasks — it is the point of the design,
and it must be governed operationally (key hygiene, named verifiers, fast
revocation). Owner decision required before any Attested quest goes live.

### T-ATT-02 — Attestation replay across contexts
**Severity: Medium. Status: MITIGATED by design + tests.**
A signature captured for one quest/account/chain/deployment could be replayed
elsewhere. **Controls:** EIP-712 domain separator binds chainId + verifying
contract; struct hash binds account + questId + nonce + deadline; per-account
nonce consumed on use. **Tests:** cross-chain replay (chainId 56 domain),
cross-contract replay (second QuestManager), wrong account/quest/nonce,
double-use replay — all rejected (`Attestation.t.sol`).

### T-ATT-03 — Malleable or malformed signatures
**Severity: Medium. Status: MITIGATED.**
A flipped-`s` signature or a short/empty signature could recover a different
(or zero) address. **Controls:** `ECDSA.tryRecover` rejects malleable
signatures; zero/invalid signer rejected; `AttestationExpired` /
`AttestationDeadlineTooFar` bound the validity window. **Tests:** malleable
signature, empty/zero/short signatures (`Attestation.t.sol`).

### T-VAL-01 — Malicious or buggy validator (OnChain quests)
**Severity: Medium. Status: MITIGATED structurally, residual trust documented.**
A validator can return `true` always (quest ≡ CheckIn), revert (quest
uncompletable — a DoS on that quest only), return garbage, or attempt
reentrancy. **Controls:** the validator is called in the checks phase before
any state change; `completeQuest` is `nonReentrant` (reentrancy reverts);
a reverting validator makes completion fail atomically (no partial award);
the always-true case is a creator-trust issue, documented in
`QUEST_VALIDATION_DESIGN.md` §2.2 and `DEPLOYMENT_PLAN.md` §4. **Tests:**
reverting / garbage / reentrant / always-true validators (`Validator.t.sol`).
**Residual:** creators choose validators; the project should curate reviewed
validators and hold creators accountable.

### T-VAL-02 — Validator condition changes between check and use
**Severity: Low. Status: MITIGATED.**
The condition is checked live inside the completion transaction, so there is
no check-then-use gap within a single completion. Across completions, the
condition is re-checked every time (a user who sold the required token
cannot complete again). **Test:** live re-check via transfer away/back
(`Validator.t.sol`).

### T-NONCE-01 — Nonce griefing (failed completion burns the nonce)
**Severity: Low. Status: MITIGATED.**
If a nonce were consumed before completion effects, a failed completion
(e.g. quest filled) would waste the user's attestation. **Control:** the
nonce is consumed only after signature verification, and completion effects
run after that — a revert anywhere rolls the nonce consumption back.
**Test:** failed completion does not burn the nonce (`Attestation.t.sol`).

### T-DEPLOY-03 — Deployment script misconfiguration
**Severity: Medium. Status: MITIGATED.**
Wrong env vars (multisig/creator/pauser/verifier addresses) would wire roles
to the wrong accounts. **Controls:** zero-address checks for all required
params; `_verifyWiring` asserts every role after deployment and reverts on
mismatch; the deployer address is derived from the key (`vm.addr`), never
`msg.sender`. **Residual:** the script cannot verify that an address belongs
to the intended person — addresses must be double-checked out-of-band before
broadcasting. See `DEPLOYMENT_PLAN.md` §5.

### T-DEPLOY-04 — Timelock self-administration lockout
**Severity: Low. Status: MITIGATED.**
The timelock has no optional admin (DEFAULT_ADMIN_ROLE held only by the
timelock itself). If the multisig lost its proposer role, no new proposals
could be made. **Control:** the multisig holds PROPOSER_ROLE + EXECUTOR_ROLE
+ CANCELLER_ROLE (proposers get CANCELLER_ROLE automatically); role changes
go through timelocked proposals executed by the multisig itself, so the
multisig can always propose its own recovery as long as it holds PROPOSER_ROLE.
**Residual:** if the multisig key itself is lost, the timelock is unrecoverable
— standard multisig custody risk, not specific to this design.

## Changed threats

| ID | Change |
|---|---|
| T-FARM-01 (quest farming) | Unchanged bounds (caps, duplicates, cooldowns) now apply per kind; Attested farming additionally needs a fresh attestation per completion, OnChain farming needs the live condition. The "complete without doing the task" farming vector is closed for Attested/OnChain quests. |
| T-GATE-02 (wrong-chain gate) | Strengthened: the chain allowlist {56, 97, 31337} now rejects arbitrary chains at construction, in addition to the existing WrongChain check. |

## Unchanged residual risks (from the original model)

- The Agent ID contract itself is trusted (a compromised Agent ID contract
  breaks the gate) — out of scope for AGENTHUB.
- Reputation points and badges are only as meaningful as the quests that
  award them; a CheckIn quest awards points for showing up, by design.
- No external audit has been performed; the remediation was self-tested.
