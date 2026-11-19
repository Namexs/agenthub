# AGENTHUB — PAUSER_ROLE Review (Phase 2)

**Date:** 2026-11-19. **Scope:** `packages/contracts/script/DeployAgentHub.s.sol`,
`test/PauserRole.t.sol`, `test/DeployScript.t.sol`, `docs/ROLE_MATRIX.md`,
`docs/SECURITY.md`, `docs/DEPLOYMENT_PLAN.md`,
`docs/SECURITY_DEPLOYMENT_GATE.md`.

## 1. The inconsistency

Before this phase, the PAUSER_ROLE holder differed by document:

| Source                        | Said                                    |
| ----------------------------- | --------------------------------------- |
| `DeployAgentHub.s.sol`        | `PAUSER` env var, required, any address |
| `SECURITY.md` §4              | Multisig                                |
| `SECURITY_DEPLOYMENT_GATE.md` | Admin multisig                          |
| `DEPLOYMENT_PLAN.md` §2       | "Pauser address" (unspecified)          |

The script was the odd one out: it REQUIRED an explicit pauser address
and would happily grant the fast-pause power to any EOA, while the docs
said "multisig". The deployer also could have (in principle) passed its
own address — caught only by `_verifyWiring`, not by the default.

## 2. The fix (single configuration everywhere)

**Production default: `PAUSER_ROLE` goes to the verified admin
multisig.** Implemented in the deploy script:

- `DeployParams.pauser == address(0)` now means "default to
  `adminMultisig`" (previously: revert `ZeroAddress("pauser")`).
- `PAUSER` env var is now OPTIONAL (`vm.envOr("PAUSER", address(0))`).
- An explicit `PAUSER` still overrides the default — documented as a
  non-default configuration in `docs/ROLE_MATRIX.md` (e.g., a dedicated
  ops hot wallet; NOT recommended for production since a pauser EOA is
  a single key that can halt the platform).
- `_verifyWiring` asserts the EFFECTIVE pauser holds the role, and
  still asserts the deployer holds no role at all.

All four documents now agree; `docs/ROLE_MATRIX.md` is the single
source of truth and the other docs point at it.

## 3. What did NOT change

- `pause()` still requires `PAUSER_ROLE`; `unpause()` still requires
  `DEFAULT_ADMIN_ROLE` (the timelock). The pauser can stop the platform
  but cannot resume it alone — by design.
- `Reputation.pause()` / `Achievement.pause()` remain admin-only
  (timelock). The fast emergency stop is QuestManager pause, which
  halts all completions and therefore all new points/badges.
- Role separation is unchanged: no address holds two operational roles
  by default (multisig holds the admin-side roles: PAUSER +
  BADGE_MANAGER + timelock proposer/executor).

## 4. Tests (9 new in PauserRoleTest + 2 in DeployScriptTest)

`test/PauserRole.t.sol` deploys the real stack with the default
configuration and asserts:

- Deployer holds NO role after handover (all 13 roles checked).
- Default pauser IS the multisig.
- Only the multisig can pause; creator/verifier/stranger/deployer cannot.
- Non-admins (incl. the pauser itself) cannot unpause.
- Admin handover is correct (timelock holds admin everywhere,
  self-administers, multisig proposes/executes but is not timelock admin,
  2-day delay, role separation holds).
- **Timelock delay is enforced:** an unpause scheduled via the timelock
  cannot execute before 2 days (`TimelockUnexpectedOperationState`) and
  executes after.
- **Revocation works:** timelock revokes `PAUSER_ROLE` → multisig can
  no longer pause; re-grant restores it.
- Pause stops completions; timelock unpause restores them end-to-end.

`test/DeployScript.t.sol`: zero pauser → multisig default (replaces the
old revert test, by design); explicit pauser still overrides; the
env-driven run() paths (incl. the pauser default) are covered by the
combined `test_RunEnvDrivenPaths`.

Full suite after Phase 2: **239/239** (Phase 1 baseline 231 + 9
PauserRole + 2 new deploy tests − 3 from consolidating the four run()
tests into one sequential test — see §5).
Log: `logs/phase2-full-suite.log`, `logs/phase2-pauser-tests.log`.

## 5. Test-infrastructure note (env races, continued)

Phase 1 found that `vm.setEnv` races across parallel forge threads.
Phase 2 hit it again in the run() tests (four tests, conflicting env
values). Fix: the four env-driven run() scenarios now live in ONE
sequential test (`test_RunEnvDrivenPaths`) with identical assertions —
no interleaving is possible inside a single test. Test count drops by 3
(4 → 1 function); coverage is unchanged. A second, unrelated bug was
also fixed in this phase: `vm.prank` applies to the NEXT call, and a
`qm.PAUSER_ROLE()` lookup placed between the prank and the target call
consumes it — role lookups are now hoisted before pranks.
