# AGENTHUB — External Audit Package (Preparation)

> **⚠️ STATUS: NO EXTERNAL AUDIT HAS BEEN PERFORMED.**
> This package is **preparation only**. No independent external auditor has
> reviewed this code. The internal reviews referenced here (Phase 7
> independent-style review and Phase 8 remediation) were performed by agents
> in the same environment as the implementation — they are **not** a
> substitute for an external audit (risk item **R-012: external security
> review not yet commissioned**). Do not cite this package as evidence that
> AGENTHUB has been externally audited. Nothing in this package authorizes a
> mainnet deployment: the current decision is **CONDITIONAL GO testnet,
> NO-GO mainnet** (Phase 8 report §1).

## 1. What this package is

A self-contained bundle for an independent auditor, prepared in Phase 9
(Workstream 5, 20 November 2026). It pins the exact code under review,
summarises the architecture and threat model from the repo's own documents,
consolidates every prior finding with its disposition, and gives exact
instructions to reproduce the build and the bytecode hashes.

## 2. Code under review

| Item                               | Value                                                                                                                       |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Repository                         | https://github.com/Namexs/agenthub                                                                                          |
| **Audit commit (HEAD)**            | `7dff852d0a303411e060772747fcbafa5c9dd820` (`7dff852`)                                                                      |
| Content commit (CI-validated)      | `7dff852d0a303411e060772747fcbafa5c9dd820` (`7dff852`) — same as HEAD; CI run recorded in the Phase 9 report §8 after push  |
| Phase 8 final                      | `e1b316bbb76614a7e2d0daa4a3f897d920f1bae9` (`e1b316b`)                                                                      |
| Phase 6 baseline (pre-remediation) | `5723ff377de3d2cd79854b877124a802fb2c23eb` (`5723ff3`)                                                                      |
| Scope                              | `packages/contracts/src/` (4 contracts + interfaces, validators, mocks), `packages/contracts/script/`, `apps/web/lib/abis/` |
| Language / toolchain               | Solidity 0.8.39, Foundry forge 1.9.0, `via_ir = true`, `evm_version = "cancun"`, optimizer on, 200 runs                     |

**HEAD vs Phase 8 final:** `7dff852` (Phase 9, Workstream 2) adds two
fail-closed deploy-script guards on top of the Phase 8 final `e1b316b`
(distinct admin/creator Safes, PH9-D01; `CONFIRM_TESTNET_DEPLOY` guard
for `DeployMock`, PH9-D02) plus 5 new tests — 3 files changed, 92
insertions. No contract, frontend, or ABI file changed:
`git diff e1b316b 7dff852 -- packages/contracts/src/ apps/` is empty,
so the bytecode hashes in `BYTECODE.md` (built from `e1b316b`) remain
valid for `7dff852`. The package was refreshed to `7dff852` by the
Phase 9 coordinator (deployment copies re-verified byte-identical to
HEAD, manifest regenerated).

### Checkout and verification

```bash
git clone https://github.com/Namexs/agenthub.git
cd agenthub
git checkout 7dff852d0a303411e060772747fcbafa5c9dd820
git rev-parse HEAD   # must print 7dff852d0a303411e060772747fcbafa5c9dd820
git status --porcelain   # must be empty (clean tree)
git submodule update --init --recursive   # OpenZeppelin 5.0.2 + forge-std
```

Verify the audit commit matches this package: the bytecode hashes in
`BYTECODE.md` were produced from a fresh build of this exact commit
(20 November 2026) and reproduce the Phase 8 published SHA-256 hashes
4/4. Rebuild per `BUILD_REPRODUCTION.md` and compare.

## 3. Package contents

| Path                              | Contents                                                                                                                                                                                                                                                |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `README.md`                       | This file: status, audit commit, how to use the package                                                                                                                                                                                                 |
| `ARCHITECTURE_OVERVIEW.md`        | System overview, contracts, data flow, trust assumptions (sourced from `docs/ARCHITECTURE.md`, `README.md`)                                                                                                                                             |
| `THREAT_MODEL.md`                 | Assets, trust boundaries, threat actors, attack trees T1–T8, accepted risks (sourced from `docs/SECURITY_THREAT_MODEL.md`)                                                                                                                              |
| `FINDINGS.md`                     | Combined table: all 59 Phase 7 findings + Phase 8 disposition each, plus 3 new Phase 8 findings                                                                                                                                                         |
| `TEST_RESULTS.md`                 | Phase 8 regression battery numbers + pointers to raw logs                                                                                                                                                                                               |
| `BUILD_REPRODUCTION.md`           | Compiler version, optimizer settings, exact build-reproduction steps                                                                                                                                                                                    |
| `BYTECODE.md`                     | Fresh-build bytecode hashes (keccak256 + SHA-256), sizes, opcode scan                                                                                                                                                                                   |
| `KNOWN_LIMITATIONS.md`            | Open findings, known limitations, and what this package does NOT claim                                                                                                                                                                                  |
| `MANIFEST.md` + `MANIFEST.sha256` | SHA-256 manifest of every file in this package + secret-scan confirmation (`sha256sum -c MANIFEST.sha256` verifies all 26 content files)                                                                                                                |
| `abis/`                           | The four committed frontend ABIs (`AgentGate`, `QuestManager`, `Reputation`, `Achievement`) + `abi-parity.test.ts`, copied verbatim from `apps/web/lib/abis/` at the audit commit                                                                       |
| `bytecode/`                       | `bytecode-audit.py` (metadata-aware opcode scanner + hash tool) and its run log `bytecode-audit.log`                                                                                                                                                    |
| `deployment/`                     | Deployment scripts copied verbatim from `packages/contracts/script/` (`DeployAgentHub.s.sol`, `DeployLocalTestStack.s.sol`, `SafeValidation.sol`, `ValidateSafe.s.sol`, `ProbeSafeProxy.s.sol`, `DeployMock.s.sol`, `export-abis.mjs`) + `foundry.toml` |
| `reports/`                        | Full prior reports, copied verbatim: Phase 7 independent review, Phase 8 remediation report, Phase 8 solc evaluation                                                                                                                                    |

**Canonical sources live in the repo, not in this package.** The copies in
`abis/`, `deployment/`, and `reports/` are verbatim snapshots at the audit
commit for the auditor's convenience; the repo at the audit commit is the
source of truth. Raw test logs are referenced by path in `TEST_RESULTS.md`
(`agenthub-phase8-remediation/logs/`) and are not duplicated here.

## 4. How to use this package (auditor quickstart)

1. Check out the audit commit (§2) and confirm a clean tree.
2. Read `ARCHITECTURE_OVERVIEW.md` and `THREAT_MODEL.md` for context.
3. Read `FINDINGS.md` for what prior reviews already found — and what is
   still open (`KNOWN_LIMITATIONS.md`).
4. Reproduce the build (`BUILD_REPRODUCTION.md`) and compare bytecode
   hashes against `BYTECODE.md`.
5. Audit the contracts in `packages/contracts/src/` at the audit commit.
   Suggested focus areas (from prior reviews, not exhaustive):
   - Threshold (M-of-N) attestation in `QuestManager` (`bytes[]`
     signatures, distinctness, nonce, deadline) — Phase 6 feature,
     Phase 7 reviewed with 39 Foundry PoCs, Phase 8 added on-chain
     policy enforcement (PH7-H01/M01/M02/L07).
   - Role wiring and the deploy script's fail-closed guards
     (`SafeValidation`, broadcast guards, deployer renounce).
   - The open items in `KNOWN_LIMITATIONS.md` — especially the
     procedural review-window decision (PH7-M03) and the accepted
     no-total-emission-cap risk (PH7-L01).

## 5. What prior review established — and did not

- **Phase 7** (20 Nov 2026, HEAD `5723ff3`): 8-workstream internal
  independent-style review, 59 findings (0 Critical, 1 High, 10 Medium,
  31 Low, 17 Info). No externally exploitable vector found; threshold
  cryptography verified with 39 PoCs; ABI 0 drift (201 entries).
  Full report: `reports/PHASE7_INDEPENDENT_SECURITY_REVIEW.md`.
- **Phase 8** (20 Nov 2026, HEAD `e1b316b`): remediation of the
  Phase 7 P0/P1 findings; full regression battery green (see
  `TEST_RESULTS.md`). Full report:
  `reports/PHASE8_SECURITY_REMEDIATION_REPORT.md`.
- **Phase 9** (20 Nov 2026, HEAD `7dff852`): testnet readiness —
  reward-policy decision (Attested-only threshold policy confirmed as
  a formal design decision, PH7-L08/I07), deployment re-audit that
  found and fixed 2 gaps (PH9-D01 distinct Safes, PH9-D02 DeployMock
  guard), testnet preflight, live test plan with a 90/90 fork dry-run,
  and this package. Full report:
  `agenthub-phase9-readiness/PHASE9_TESTNET_READINESS_REPORT.md` in
  the repo (not copied here — the package predates its final commit;
  the report pins the same audit commit `7dff852`).
- **Neither phase is an external audit.** Both were done by agents in
  the same environment as the implementation. No live-chain testing has
  happened: all evidence is Foundry/Anvil local. No mainnet deployment
  exists; nothing has been submitted to the hackathon.

## 6. No secrets in this package

This package contains **no private keys, no secrets, and no `.env` files**.
Verified before handover by `gitleaks` (repo history scan: 0 leaks) and a
targeted grep over the package directory — see `MANIFEST.md` for the exact
commands and results. Deployment requires operator-supplied inputs
(deployer key, Safe addresses, BscScan API key); none of those are in this
package, and none were used to prepare it (no deploy, no broadcast, no
private key — per the Phase 9 workstream constraints).
