# AGENTHUB — Role Matrix

**Single source of truth for who can do what.** This matrix is the
reference that `DeployAgentHub.s.sol`, `SECURITY.md`,
`SECURITY_DEPLOYMENT_GATE.md`, and `DEPLOYMENT_PLAN.md` must all agree
with. Any change to role wiring MUST update this file first.

**Last updated:** 2026-11-20 (Phase 8: PH7-M03 creator must be a Safe,
PH7-M04 MockAgentId owned by the multisig; Phase 2: PAUSER_ROLE
defaults to the verified admin multisig).

## 1. Design principles

1. **The deployer keeps nothing.** After `DeployAgentHub.deploy()`
   finishes, the deployer holds zero roles on every contract (enforced
   by `_verifyWiring`, tested in `PauserRoleTest` +
   `DeployScriptTest`). It also owns nothing: MockAgentId ownership is
   transferred to the admin multisig (PH7-M04), so the deployer cannot
   mint test Agent IDs.
2. **Admin is the timelock, not a person.** `DEFAULT_ADMIN_ROLE` on all
   three AccessControl contracts belongs to the TimelockController
   (2-day delay). The admin multisig proposes + executes through it; it
   does NOT hold admin directly.
3. **Fast path is pause-only.** The ONLY admin action without a timelock
   delay is `QuestManager.pause()` via `PAUSER_ROLE`. Everything else
   sensitive (role grants/revokes, unpause, validator approval) goes
   through the 2-day timelock.
4. **Unpause is slow on purpose.** A compromised pauser can stop the
   platform but cannot resume it alone — unpause needs the timelock.
5. **Operational roles are explicit and separated.** No address holds two
   operational roles by default (except the admin multisig, which holds
   the admin-side roles: PAUSER + BADGE_MANAGER + timelock
   proposer/executor).

## 2. Role matrix (production default)

| Contract                    | Role                 | Holder (default)                        | Powers                                        | Delay    |
| --------------------------- | -------------------- | --------------------------------------- | --------------------------------------------- | -------- |
| All three                   | `DEFAULT_ADMIN_ROLE` | TimelockController                      | Grant/revoke any role; unpause                | 2 days   |
| QuestManager                | `PAUSER_ROLE`        | **Admin multisig**                      | `pause()` (emergency stop)                    | **None** |
| QuestManager                | `QUEST_CREATOR_ROLE` | Quest creator Safe (≥ 2-of-n, verified) | `createQuest`, `deactivateQuest` (own quests) | —        |
| QuestManager                | `VERIFIER_ROLE`      | Named verifier(s)                       | Sign EIP-712 attestations (off-chain)         | —        |
| Reputation                  | `SCORE_SOURCE_ROLE`  | QuestManager only                       | `addPoints`                                   | —        |
| Achievement                 | `ISSUER_ROLE`        | QuestManager only                       | `issue`                                       | —        |
| Achievement                 | `BADGE_MANAGER_ROLE` | Admin multisig                          | `defineBadge`                                 | —        |
| MockAgentId (testnet/local) | `owner()` (Ownable)  | Admin multisig                          | `mint` test Agent IDs                         | —        |
| QuestManager                | validator allowlist  | Admin (timelock)                        | `approveValidator`, `revokeValidator`         | 2 days   |
| QuestManager                | emergency revoke     | `PAUSER_ROLE` holder                    | `emergencyRevokeValidator` (Phase 5)          | **None** |
| Timelock                    | `DEFAULT_ADMIN_ROLE` | Timelock itself                         | Timelock config changes (via proposals)       | 2 days   |
| Timelock                    | `PROPOSER_ROLE`      | Admin multisig                          | Schedule proposals                            | —        |
| Timelock                    | `EXECUTOR_ROLE`      | Admin multisig                          | Execute ready proposals                       | —        |
| Timelock                    | `CANCELLER_ROLE`     | Admin multisig                          | Cancel proposals                              | —        |
| All                         | any role             | **Deployer: NONE**                      | —                                             | —        |

Notes:

- **PAUSER default (Phase 2):** when `PAUSER` is unset in the deploy
  script, `PAUSER_ROLE` goes to the verified admin multisig. An explicit
  `PAUSER` address overrides the default — a documented non-default
  configuration (e.g., a dedicated ops hot wallet). The override is
  allowed but NOT recommended for production: a pauser EOA is a single
  key that can halt the platform.
- **Reputation / Achievement pause:** both contracts are pausable, but
  their `pause()`/`unpause()` are `DEFAULT_ADMIN_ROLE`-only (timelock,
  2-day delay). The fast emergency stop is QuestManager pause, which
  halts all completions — and therefore all new points and badges, since
  both flow only through completions.
- **VERIFIER_ROLE** is granted to named individuals/services only (see
  `VERIFIER_ROLE_SOP.md`); the first verifier is optional at deploy
  time (`VERIFIER` env var) and more are added via timelock.
- **QUEST_CREATOR_ROLE** is a trusted role: a creator can create quests
  (with capped rewards) but cannot attach an unapproved validator
  (Phase 5 registry) or mint points/badges directly. The creator MUST
  be a Safe (threshold ≥ 2), enforced by the deploy script with the
  same validation as the admin multisig (PH7-M03); a single-key
  creator is rejected at deploy time.

## 3. What each actor can and cannot do

| Actor                | Can                                                                 | Cannot                                                                       |
| -------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Admin multisig       | Pause instantly; propose/execute timelock actions; define badges    | Unpause without the 2-day timelock; grant roles directly; mint points/badges |
| Timelock             | Grant/revoke roles; unpause; approve/revoke validators              | Act without a multisig proposal + 2-day delay                                |
| Quest creator (Safe) | Create/deactivate quests (capped rewards, approved validators only) | Complete quests for others; mint points/badges; pause                        |
| Verifier             | Attest off-chain completions (signature only)                       | Complete quests on-chain; grant roles; pause                                 |
| Deployer             | Deploy the contracts                                                | Anything after deployment (zero roles, zero ownership)                       |
| Any user             | Complete quests (if Agent ID holder); read all state                | Anything requiring a role                                                    |

## 4. Emergency sequences

**Compromised verifier:** pause (multisig, instant) → propose revocation
(timelock, 2 days) → execute revocation → propose unpause (timelock, 2
days) → execute unpause. Worst case ~4 days paused. See
`VERIFIER_ROLE_SOP.md` §4.

**Malicious validator:** `emergencyRevokeValidator` (pauser, instant)
blocks new quests AND completions using it; or pause everything
(multisig, instant). Re-approval needs the timelock. See
`APPROVED_VALIDATOR_REGISTRY.md`.

**Compromised creator:** revoke `QUEST_CREATOR_ROLE` via timelock (2
days); deactivate their quests (admin or creator); pause if completions
must stop immediately. (The creator is a Safe, PH7-M03, so compromise
means quorum compromise.)

**Compromised multisig owner key:** rotate the Safe's owners via the
Safe itself (threshold still reachable with remaining owners); if
quorum is lost, the timelock cannot be administered — this is the
deployment's single biggest operational risk (see `DEPLOYMENT_PLAN.md`
§4.5). There is no contract-level recovery for a lost Safe quorum.
