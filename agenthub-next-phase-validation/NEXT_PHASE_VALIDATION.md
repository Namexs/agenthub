# AGENTHUB — Next Phase Validation Report

**Date:** 2026-11-19. **Basis:**
`agenthub-next15-upgrade/NEXT15_UPGRADE_REPORT.md` (HEAD `39fcb94`).
**Validation HEAD:** `ded99ad` (8 commits, 38 files, +3,641/−1 — docs,
logs, and one `.gitleaks.toml` allowlist entry; **zero contract, app,
or test-code changes**).
**Work:** 8 sequential phases with gates. No deployment, no broadcast,
no private key used. No push was made by this work (the parent owns
the push decision).

## 1. Decision

**CONDITIONAL GO for live BNB Testnet validation. NO-GO for mainnet.**

The code and the deployment machinery are proven ready to undergo
live testnet validation: every suite is green from a clean install,
CI is green 10/10 on GitHub at the validated commit, the dependency
tree has 0 High/Critical findings, and the full deployment was
re-proven on a chain-97 fork with a genuine Safe. The ONLY remaining
conditions are the 8 deployment inputs (§5) — tBNB, deployer key,
Safe, creator, verifier, pauser, BscScan key, explicit broadcast
approval — all still with the user. Nothing in this validation
authorizes a broadcast; only the user's explicit approval for a
specific deployment does.

This is NOT a full GO, for one explicit reason no amount of local
work can resolve: **the deployment inputs are missing.** Every other
blocker from the previous reports is now closed (see §6).

Mainnet stays NO-GO: no external audit (R-012), threshold
attestation not implemented (R-010, required before mainnet
high-value quests), the live testnet smoke test has not run, and the
mainnet gate in `FINAL_DEPLOYMENT_CHECKLIST.md` §7 is unsatisfied.

## 2. Verdict per phase

| Phase                     | Gate                                                                          | Result                                               |
| ------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------- |
| 1 — Commits & branch      | `09dd3f4` + `d9c5d26` on `main` and pushed; manifest verified                 | **PASSED**                                           |
| 2 — GitHub Actions        | Latest run on `main` 10/10 PASS; E2E uses pinned Playwright                   | **PASSED**                                           |
| 3 — Dependency audit      | OSV + `pnpm audit` re-run; 0 CRITICAL / 0 HIGH                                | **PASSED**                                           |
| 4 — Testnet readiness     | Fork deploy re-proven; §4.3 checks green; inputs still missing, none invented | **PASSED**                                           |
| 5 — Threshold attestation | Implementation checked; remediation plan if absent                            | **PASSED (finding: NOT implemented — plan written)** |
| 6 — Wallet-app + Cancun   | Wagmi audit; Cancun proven on-chain or declared open risk                     | **PASSED (O4 open, Cancun proven)**                  |
| 7 — Full regression       | Entire battery green from clean install                                       | **PASSED after 2 doc/log fixes**                     |
| 8 — Report                | This report + manifest                                                        | **PASSED**                                           |

## 3. Evidence per phase

### Phase 1 — Commits & branch (PASSED)

- Branch `main`, HEAD `39fcb94becf5e5dd18d7f4561868139fd30dce27`;
  `git ls-remote origin main` returns the same SHA; `gh api
repos/Namexs/agenthub/branches/main` confirms `main` at
  `39fcb94`.
- `git merge-base --is-ancestor` confirms BOTH `09dd3f4` (Next.js 15
  upgrade) and `d9c5d26` (E2E CI job) are ancestors of `origin/main`.
- Manifest verified: `verify-manifest.sh` — 403 files checked,
  commit `ad9f025` matches, both submodules OK.
- Log: `logs/phase1-commits-branch.log`.

### Phase 2 — GitHub Actions (PASSED, independently re-verified)

- Run **#44535662688** on `main`, headSha `39fcb94`, event `push`,
  conclusion `success`, 3m43s — verified via `gh run view` + `gh
api`, not taken from any prior note. All **10/10 jobs success**:
  Format, Dependency audit, Shared, Contracts fuzz + invariant,
  E2E, Secret scanning, Package manifest, Web, Contracts, Slither.
- **Playwright pin proven:** the E2E job log (152,638 bytes,
  downloaded) shows `pnpm --filter @agenthub/web exec playwright
install --with-deps chromium` downloading `Chrome for Testing
159.0.8154.6 (playwright chromium v1255)` — and the local
  `playwright-core@1.65.1` `browsers.json` declares chromium
  revision **1255**. The pinned version is the version that ran.
  The `--with-deps` apt step (unprovable on this VM) ran fine on
  GitHub (`apt-get update` fetched 4,207 kB).
- The GitHub log itself records `E2E smoke: 23 passed, 0 failed`
  and `Wallet E2E: 25 passed, 0 failed`.
- Logs: `logs/phase2-ci-run-summary.log`,
  `logs/phase2-e2e-job-log.txt`,
  `logs/phase2-playwright-revision.log`.

### Phase 3 — Dependency audit (PASSED)

- OSV re-run on the current lockfile (`scripts/osv-audit.mjs`, 960
  packages): **7 findings — 6 MODERATE + 1 LOW, 0 HIGH / 0
  CRITICAL**, identical set to the upgrade report (MetaMask SDK ×2,
  stablelib, elliptic, minimatch, uuid ×2). JSON:
  `test-results/osv-audit-nextphase.json`.
- GitHub `pnpm audit` (Dependency audit job, run #44535662688):
  `6 advisories reported`, non-gating `{moderate: 5, low: 1}`,
  `AUDIT PASSED: no new high/critical findings`. The 6-vs-7 count
  difference is reconciled: pnpm counts advisories per module
  (MetaMask GHSA = 2 advisories), OSV counts findings per
  package@version (uuid 2 versions = 2 findings). Same underlying
  vulnerabilities, zero High/Critical in both counts.
- The audit allowlist mechanism re-tested locally, 4/4 cases pass
  (fixture → 0; +fake HIGH → 1; bogus entry → 1 stale; malformed
  shape → 2).
- Local `pnpm audit` still cannot run on this VM (no pnpm binary;
  registry audit endpoint returns 403 — documented since Phase 4).
  The GitHub job is the authoritative `pnpm audit` run.
- None of the 7 remaining findings affects the deployment: all are
  transitive dev/test-time or unused-path packages (MetaMask SDK is
  not exercised — the app uses `injected()` only; elliptic/minimatch
  /uuid are build-tool transitive deps).
- Logs: `logs/phase3-osv.log`, `logs/phase3-github-audit-job-log.txt`,
  `logs/phase3-allowlist-tests.log`.

### Phase 4 — Testnet readiness (PASSED)

- Live testnet reads (publicnode, block 143,650,452): chain 97, gas
  ~0.109 gwei, official Agent ID absent (`0x` — MockAgentId required
  as designed), Safe singletons v1.4.1/v1.3.0 + both factories live
  with correct `VERSION()` values.
- Full deployment re-proven on a chain-97 fork with a genuine Safe
  (v1.4.1 factory, 2 owners, threshold 2, created on the fork;
  throwaway keys, discarded): `ValidateSafe` positive OK + negative
  correctly rejects `0x1111…` (`NotASafe`); deploy `ONCHAIN
EXECUTION COMPLETE & SUCCESSFUL` — **18 txs, 6 CREATEs, all 18
  receipts status 1, actual gas 8,378,658 (byte-identical to Phase
  H)**, cost ≈ **0.00092 tBNB** at live gas price (the ≥ 0.05 tBNB
  recommendation has 50×+ margin).
- Post-deploy verification, checklist §4.3 items 8–14, ALL green:
  gate.agentId == MockAgentId; mint + `isAgentHolder` true/false;
  QM deps match; all roles correct (admin == timelock ×3,
  SCORE_SOURCE/ISSUER == QM, BADGE_MANAGER == Safe, creator,
  pauser == Safe default, verifier); deployer holds NO role (6
  checks); timelock minDelay 172800, proposer/executor/canceller ==
  Safe, self-administered, multisig NOT admin; all unpaused.
- **8 deployment inputs: verified still missing, none invented** —
  no `.env` files besides `.env.example`, no `DEPLOYMENT_RECORD.md`,
  checklist §1 shows 8× `NOT RECEIVED`, no Safe/creator/verifier
  address recorded anywhere in the repo.
- Frontend env chain-97: `lib/env.ts` rejects the official Agent ID
  on chain 97 (MockAgentId required) — still correct.
- BscScan mapping re-probed: bogus `BSCSCAN_API_KEY` → BscScan
  answers `Invalid API Key` (the key IS sent); unset variable →
  fail-fast `environment variable BSCSCAN_API_KEY not found`; `forge
build` exit 0 without the key.
- Logs: `logs/phase4-*.log` (7 files).

### Phase 5 — Threshold attestation (PASSED with finding: NOT IMPLEMENTED)

- Verified from the code: `completeQuestWithAttestation(questId,
deadline, bytes signature)` takes ONE signature; `_verifyAttestation`
  recovers ONE signer and checks `VERIFIER_ROLE`; the `Quest` struct
  has no threshold field; a repo-wide grep finds no threshold/quorum/
  multi-verifier code in the contracts. R-010 stays OPEN.
- **Remediation plan written** (no contract changed):
  `THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md` — scheme (`bytes[]`
  signatures, M distinct `VERIFIER_ROLE` signers over the same
  digest, per-quest immutable threshold default 1, bounds 1–3,
  duplicate reverts, array capped at 5), contract + frontend +
  tooling changes, migration path (immutable contracts ⇒ redeploy;
  land before the first mainnet deploy), test plan (~18–22 Foundry
  - ~8–10 frontend tests), risks (coordination UX, threshold
    footgun, ABI break), acceptance criteria, and 3 decisions for the
    user/team (policy values, timing, who verifiers 2–3 are).
- This does NOT block testnet validation: the SOP requires threshold
  only before mainnet high-value quests, and the testnet verifier
  set is one person.
- Log: `logs/phase5-threshold-check.log`.

### Phase 6 — Wallet-app + Cancun (PASSED with findings)

**Wallet-app (O4 stays OPEN — honestly scoped):**

- Wagmi config (`lib/wagmi.ts`): connectors `[injected()]` ONLY;
  chains env-driven (56/97/31337); transports are viem `http()`
  defaults for BSC chains; `ssr: true`. No WalletConnect (needs a
  project id — documented as a later addition).
- App wagmi surface: `useAccount`/`useConnect`/`useDisconnect`
  (connect), `useReadContract(s)` + `usePublicClient` (reads/logs),
  `useWriteContract` + `useWaitForTransactionReceipt`
  (completions), `useSwitchChain` (wrong-network guard). No
  `useSignTypedData` in the app — attestation signatures are pasted
  by the user (verifier signs out-of-band).
- The wallet E2E proves the REAL wagmi `injected()` path on anvil
  (25/25 on GitHub): connect, reads, write, chain switch — against
  a minimal EIP-1193 stub (`eth_requestAccounts`, `eth_chainId`,
  `wallet_switchEthereumChain`, `eth_sendTransaction`,
  `personal_sign`, `eth_signTypedData_v4`, rest proxied to anvil).
- **NOT proven without a real device:** real Binance Wallet /
  MetaMask extension popups (approval, confirmation, rejection),
  mobile wallets + deep links (**no WalletConnect means mobile users
  have no connect path outside an in-app browser**), multi-wallet
  EIP-6963 discovery, real-network RPC latency on viem defaults.
  The live testnet smoke test is where O4 gets closed — it is part
  of testnet validation, not a precondition for it.

**Cancun (O5 substantially resolved — proven on-chain):**

- `foundry.toml`: `evm_version = "cancun"`, solc 0.8.24,
  `via_ir = false`. No `transient` in app source or imported OZ
  modules; OZ 5.0.2 `ReentrancyGuard` is storage-based; no
  blobhash/blobbasefee builtins in app source.
- **Bytecode disassembly (`cast disassemble`, deployedBytecode):**
  QuestManager 0, AgentGate 0, Reputation **1 × MCOPY** (pc 0x946),
  Achievement **1 × MCOPY** (pc 0x1887); TSTORE/TLOAD/BLOBHASH/
  BLOBBASEFEE 0 everywhere. MCOPY (EIP-5656, Cancun-only) is emitted
  by solc 0.8.24's legacy codegen for memory copies — the
  `foundry.toml` comment claiming "no Cancun-only opcodes" is now
  outdated (see finding F3).
- **Cancun proven ACTIVE on both chains via live RPC:** BSC testnet
  block 143,651,300 carries `blobGasUsed 0x20000` (exactly one real
  blob), `excessBlobGas`, `parentBeaconBlockRoot`, `withdrawalsRoot`;
  BSC mainnet block 134,515,804 carries the same Cancun fields.
  MCOPY therefore executes on BSC. Final proof remains the live
  testnet smoke test (executing these exact contracts on testnet).
- Logs: `logs/phase6-wallet-compat.log`,
  `logs/phase6-cancun-rpc.log`, `logs/phase6-opcode-scan.log`.

### Phase 7 — Full regression (PASSED after 2 doc/log fixes)

Clean copy of `af75bcc` (the tested commit; `d584a8e..af75bcc` is
docs-only, 0 code changes — see the toolchain log), Node 20.20.2 +
pnpm 9.15.4 + forge 1.9.0 + slither 0.11.6, suites run sequentially:

| Suite                             | Result                                           |
| --------------------------------- | ------------------------------------------------ |
| Clean install `--frozen-lockfile` | exit 0                                           |
| Foundry tests                     | **255/255** (19 suites)                          |
| Fuzz (10,000 runs, seed 42)       | **255/255**                                      |
| Vitest web / shared               | **136 + 4 skip / 8/8**                           |
| Typecheck, lint, build, format    | exit 0 (after fixes F1)                          |
| E2E smoke / wallet E2E            | **23/23 / 25/25**, 0 console errors              |
| Anvil integration                 | **27/27 + 4/4**                                  |
| Slither (`--fail-medium`)         | exit 0, **12 results** (0 High/Medium, same set) |
| Gitleaks (full history)           | exit 0, **0 leaks** (after fix F2)               |

**Two failures found and fixed in this phase (both in validation
docs/logs, zero code involvement):**

- **F1 — Prettier:** 2 files added by this validation were
  unformatted (`osv-audit-nextphase.json`,
  `THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md`; a third,
  `phase7-gitleaks-finding.json`, surfaced on re-check). Fixed with
  `prettier --write`; re-check exit 0 (`All matched files use
Prettier code style!`).
- **F2 — Gitleaks false positive:** `generic-api-key` on a GitHub
  Actions cache key (`e2e-39fcb94…`, literally `e2e-` + the commit
  SHA) in the Phase 2 E2E job log. Fixed by adding the EXACT VALUE
  to `.gitleaks.toml` with a written justification. Lesson recorded:
  gitleaks allowlists match the bare secret, not the line — a first
  attempt with the `cache-key: ` prefix did NOT match (verified by
  re-scan). Re-scan: 86 commits, 0 leaks. Negative control
  re-run with the updated config: fake private key + `ghp_` token
  still detected (3 leaks) — detection is NOT weakened.
- No test was deleted, no assertion weakened, no CI check disabled.
  The tested commit (`af75bcc`) differs from the final HEAD only by
  docs/log/config commits; the `.gitleaks.toml` change was itself
  re-verified green (see above).
- Logs: `logs/phase7-*.log` (14 files).

## 4. Findings register (new in this validation)

| #   | Finding                                                                                                              | Severity                     | Status                                                                                            |
| --- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------- |
| F1  | Validation docs unformatted (Prettier)                                                                               | Low                          | FIXED + verified                                                                                  |
| F2  | Gitleaks false positive on CI cache key in evidence log                                                              | Low                          | FIXED (allowlist) + control verified                                                              |
| F3  | `foundry.toml` comment claims "no Cancun-only opcodes" — bytecode contains 1× MCOPY each in Reputation + Achievement | Info                         | DOCUMENTED; no action needed (Cancun live on BSC); comment should be corrected in a later cleanup |
| F4  | Threshold M-of-N attestation NOT implemented (R-010)                                                                 | Low (pre-mainnet)            | PLAN WRITTEN; not blocking testnet                                                                |
| F5  | Real wallet-app compatibility unproven (O4)                                                                          | Medium (testnet smoke scope) | OPEN — closes during live testnet validation                                                      |
| F6  | No WalletConnect — mobile users have no connect path outside in-app browsers                                         | Medium (product scope)       | OPEN — needs a WalletConnect project id + connector work; not blocking testnet                    |

## 5. Residual risks + deployment blockers

**Residual risks (carried, unchanged unless noted):** Safe identity
is out-of-band (R1); verifier honesty (R2 — threshold plan is the
mitigation path); testnet identity is mock-based (R3); timelock key
loss (R4); global attestation nonce (R5); no on-chain undo (R6).
**New:** F5/F6 (wallet-app + mobile gap) join the list until the
live smoke test; F3 is closed as a risk by the Cancun evidence.

**Deployment blockers (all with the user — unchanged):**

1. tBNB (≥ 0.05; deploy costs ~0.00092 tBNB at live gas price).
2. Dedicated deployer key (single-use, secure channel — never chat).
3. Admin multisig (Safe) address on BSC testnet, threshold ≥ 2.
4. Quest creator address.
5. First verifier address (optional).
6. Pauser address (optional — defaults to the multisig).
7. BscScan API key.
8. Explicit approval to broadcast this specific testnet deployment.

## 6. Blockers closed by this validation (vs the Next15 report)

| Blocker (Next15 report §6)                        | Status now                                                                                                     |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| 1. `e2e` job never run on GitHub                  | CLOSED — run #44535662688 green 10/10, incl. the `--with-deps` apt step and pinned Playwright 1.65.1 (Phase 2) |
| 2. 8 deployment inputs with user                  | OPEN — unchanged, the sole remaining condition                                                                 |
| 3. No external audit                              | OPEN — unchanged (pre-mainnet)                                                                                 |
| 4. Testnet smoke test not run on live chain       | OPEN — unchanged; this validation proves readiness to RUN it                                                   |
| 5. Threshold attestation not implemented          | OPEN — remediation plan delivered (Phase 5)                                                                    |
| 6. Real wallet-app check (O4) / Cancun smoke (O5) | O4 OPEN (closes during smoke); O5 SUBSTANTIALLY RESOLVED (Cancun proven live on both chains; MCOPY mapped)     |
| 7. MetaMask SDK MODERATE + React 19 peer warnings | OPEN — unchanged, cosmetic, deferred to wagmi upgrade                                                          |

## 7. Evidence index

All reports in `agenthub-next-phase-validation/`; all raw logs in
`agenthub-next-phase-validation/logs/` (33 files); OSV JSON in
`test-results/`:

- `NEXT_PHASE_VALIDATION.md` (this report)
- `THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md` (Phase 5)
- Phase 1: `phase1-commits-branch.log`
- Phase 2: `phase2-ci-run-summary.log`,
  `phase2-e2e-job-log.txt`,
  `phase2-playwright-pinned.log`,
  `phase2-playwright-version-evidence.log`,
  `phase2-playwright-revision.log`
- Phase 3: `phase3-osv.log`,
  `phase3-github-audit-job-log.txt`,
  `phase3-allowlist-tests.log`
- Phase 4: `phase4-live-testnet-reads.log`,
  `phase4-fork-run.log`, `phase4-fork-deploy.log`,
  `phase4-fork-postdeploy-verify.log`, `phase4-gas-math.log`,
  `phase4-inputs-env-check.log`, `phase4-bscscan-probe.log`
- Phase 5: `phase5-threshold-check.log`
- Phase 6: `phase6-wallet-compat.log`, `phase6-cancun-rpc.log`,
  `phase6-opcode-scan.log`
- Phase 7: `phase7-toolchain.log`, `phase7-install.log`,
  `phase7-contracts.log`, `phase7-fuzz.log`,
  `phase7-web-shared.log`, `phase7-build-format.log`,
  `phase7-e2e-smoke.log`, `phase7-wallet-e2e.log`,
  `phase7-anvil.log`, `phase7-slither.log`,
  `phase7-gitleaks.log`, `phase7-gitleaks-finding.json`,
  `phase7-remediation-verify.log`,
  `phase7-remediation-verify2.log`,
  `phase7-gitleaks-control.log`

## 8. Manifest regeneration

`PACKAGE_MANIFEST.md` is regenerated for the final commit after this
report is committed (the manifest excludes itself and is committed
separately from the commit it describes — the established pattern;
`verify-manifest.sh` confirms the recorded commit matches).

**Final verdict: CONDITIONAL GO for live BNB Testnet validation,
NO-GO for mainnet.** No deployment is authorized by this report —
only the user's explicit approval for a specific broadcast
authorizes one.
