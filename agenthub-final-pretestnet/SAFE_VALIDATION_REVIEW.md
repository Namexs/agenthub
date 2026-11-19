# AGENTHUB — Safe Validation Review (Phase 1)

**Date:** 2026-11-19. **Scope:** `packages/contracts/script/SafeValidation.sol`,
`ValidateSafe.s.sol`, `DeployAgentHub.s.sol` (Safe gating),
`test/SafeValidation.t.sol`, `test/DeployScript.t.sol`,
`test/mocks/MockSafeProxy.sol`, `test/mocks/CanonicalSafe.sol`,
`script/ProbeSafeProxy.s.sol`.

## 1. The problem with the old check

The pre-testnet cleanup validated `ADMIN_MULTISIG` by calling
`getThreshold()` + `getOwners()` and requiring threshold ≥ 2. Any
contract implementing two view functions passed. A fake "Safe" — or a
misconfigured address — would have silently centralized the project
(timelock proposer/executor + badge manager).

## 2. What the new check proves (on-chain)

`SafeValidation.validate()` (production path, chains 56/97) now checks,
in order:

| #   | Check                                                    | Rejects                                          |
| --- | -------------------------------------------------------- | ------------------------------------------------ |
| 1   | `block.chainid` ∈ {56, 97}                               | Wrong chain (`UnsupportedChain`)                 |
| 2   | `candidate.code.length > 0`                              | Zero address, EOA (`NotASafe: "no code"`)        |
| 3   | `getThreshold()` ∈ [2, ownerCount], owners ≥ 2           | 1-of-n, threshold > owners (`UnsafeThreshold`)   |
| 4   | `masterCopy()` ∈ {Safe v1.4.1, Safe v1.3.0 singletons}   | Non-Safe singleton (`UnknownSingleton`)          |
| 5   | `candidate.codehash` ∈ {v1.4.1, v1.3.0 proxy codehashes} | Any non-canonical proxy (`UnknownProxyCodehash`) |
| 6   | `VERSION()` ∈ {"1.4.1", "1.3.0"} (via delegatecall)      | Tampered singleton (`VersionMismatch`)           |

Checks 4+5 together close the spoofing hole: a fake contract can return
any address from `masterCopy()`, but it cannot fake the codehash without
BEING the canonical proxy — and the canonical proxy bytecode does nothing
but delegatecall the singleton in slot 0, so `getThreshold`/`getOwners`/
`VERSION` all come from the real singleton. A contract passing all six
checks IS a genuine Safe proxy (up to the trust assumptions in §5).

## 3. Canonical values — sources and verification

All values were verified TWO independent ways on 2026-11-19:

| Value                          | Address / hash                                                       | Sources                                                                                                                                                                                     |
| ------------------------------ | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Safe v1.4.1 singleton          | `0x41675C099F32341bf84BFc5382aF534df5C7461a`                         | safe-deployments `v1.4.1/safe.json` + safe-smart-account CHANGELOG + live `cast code` on BSC 56/97 (23,579 bytes) + `VERSION()` → `"1.4.1"`                                                 |
| Safe v1.3.0 singleton          | `0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552`                         | safe-deployments `v1.3.0/gnosis_safe.json` + CHANGELOG + live `cast code` on BSC 56/97 + `VERSION()` → `"1.3.0"`                                                                            |
| Safe v1.4.1 singleton codehash | `0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4` | Computed from live BSC testnet bytecode (`cast keccak`)                                                                                                                                     |
| Safe v1.3.0 singleton codehash | `0xbba688fbdb21ad2bb58bc320638b43d94e7d100f6f3ebaab0a4e4de6304b1c2e` | Computed from live BSC testnet bytecode; prefix matches safe-deployments `codeHash`                                                                                                         |
| SafeProxyFactory v1.4.1        | `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67`                         | safe-deployments + live code on BSC 56/97                                                                                                                                                   |
| GnosisSafeProxyFactory v1.3.0  | `0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2`                         | safe-deployments + live code on BSC 56/97                                                                                                                                                   |
| v1.4.1 proxy codehash          | `0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c` | Derived: created a genuine proxy via the canonical factory on a BSC testnet fork (`script/ProbeSafeProxy.s.sol`), then independently re-verified with `cast keccak` of the printed bytecode |
| v1.3.0 proxy codehash          | `0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000` | Same derivation as above                                                                                                                                                                    |

Notes:

- The v1.4.1 and v1.3.0 proxy bytecodes differ ONLY in the metadata-hash
  suffix; the executable code is identical. Both codehashes are accepted.
- A v1.3.0 proxy may point at a v1.4.1 singleton and vice versa (proxies
  are version-agnostic by design); no pairing is enforced.
- The singleton codehashes are recorded here as evidence but are NOT
  checked on-chain: the singleton is identified by its canonical CREATE2
  address, and its bytecode was verified live on both chains. (A CREATE2
  address can only ever hold the canonical bytecode.)
- `ProbeSafeProxy.s.sol` is kept in the repo as the derivation evidence
  for the proxy codehashes. It only runs on a fork (simulation, no
  broadcast).

## 4. Local chain (31337) — explicit path

Canonical Safes are not deployed on a local chain, so the production
path cannot run there. `validate(candidate, expectedSingleton,
expectedProxyCodehash)` runs the SAME mechanism against
operator-supplied expected values. It reverts on any chain other than
31337, and `DeployAgentHub` rejects explicit values on production
chains (`ExplicitSingletonNotAllowedOnProduction`) and requires them on
local (`LocalSafeConfigMissing`). There is no way for a production
deploy to take the weaker path.

## 5. Trust assumptions and limitations (stated honestly)

1. **The check proves genuineness, not identity.** It proves the address
   is a genuine Safe proxy with a sane threshold. It does NOT prove the
   Safe belongs to the AGENTHUB team or that its owners are the intended
   people. The operator MUST confirm the address + owners out-of-band
   and in the Safe web app before deploying — see the manual
   verification procedure in `docs/DEPLOYMENT_PLAN.md` §5.1. That
   procedure is REQUIRED, not optional.
2. **The canonical sets are frozen in code.** If Safe ships a v1.5.0
   singleton/proxy, a v1.5.0 Safe will be REJECTED until the constants
   are updated (deliberate fail-closed behavior). Do not "fix" a
   rejection by switching to the explicit path on production — it
   reverts by design; update the constants instead.
3. **The singleton's bytecode is trusted by address.** The check does
   not verify the singleton's codehash on-chain (see §3). The bytecode
   was verified live on BSC 56/97 at the time of writing; a future
   chain with a different deployment at the same CREATE2 address is
   not possible (CREATE2 binds address to init code + deployer).
4. **Threshold/owners are read at deploy time.** If the Safe's owners
   or threshold change AFTER deployment, AGENTHUB does not notice —
   the timelock roles are granted to the Safe address, whoever controls
   it. Multisig custody is an operational requirement (see
   `DEPLOYMENT_PLAN.md` §4.5).
5. **Test singletons are mocks.** The 23 KB real singleton bytecode is
   not embedded in tests; test proxies delegatecall mock singleton
   logic etched at the canonical addresses. The tests prove the
   VALIDATION logic (address + codehash + version checks); the
   singleton bytecode itself was verified live on-chain (§3).

## 6. Tests (39 tests, all passing)

`test/SafeValidation.t.sol` (17) + the Safe-gating tests in
`test/DeployScript.t.sol` (22 total in that file):

- Genuine Safe v1.4.1 / v1.3.0 (canonical bytecode, via etch) — accepted.
- Explicit local path (31337, mock proxy + singleton) — accepted.
- EOA, zero address, non-Safe contract — rejected.
- Threshold 1, threshold > owners — rejected.
- Fake interface (getThreshold/getOwners only, no masterCopy) — rejected.
- **Spoofed masterCopy** (returns a canonical singleton, answers
  VERSION, but is not a canonical proxy) — rejected by the codehash check.
- Proxy-shaped mock without canonical bytecode — rejected on the
  canonical path.
- Wrong VERSION ("9.9.9") — rejected.
- Wrong chain (1) — rejected.
- Explicit path: wrong singleton / wrong codehash / production chain —
  rejected; mismatched explicit values (only one of the two) — rejected.
- Deploy script: explicit values rejected on production chains; missing
  local Safe config rejected on 31337; mainnet/testnet deploys use
  canonical proxies.

Full suite after Phase 1: **231/231** (baseline 218 + 13 new).
Log: `logs/phase1-full-suite.log`, `logs/phase1-safe-tests.log`.

## 7. Test-infrastructure finding (documented, fixed)

The first version of `SafeValidationTest` used `vm.setEnv` to drive the
env-based `ValidateSafe.run()`. It flaked (12/16 failed): forge runs
tests in parallel threads and `setEnv` mutates process-global state, so
one test read another test's values. Fix: `ValidateSafe.runWith()`
(parameterized, no env) is now the test entry point; `run()` is a thin
env wrapper. The same race flaked `DeployScriptTest` once
(`test_RunDeploysLocalStack` read a leaked `AGENT_ID_ADDRESS`); fix:
`_setRunEnv` now sets EVERY env var `run()` reads, immediately adjacent
to the `run()` call, with slow setup moved before the sets. Both suites
are stable across repeated runs (3× 39/39).
