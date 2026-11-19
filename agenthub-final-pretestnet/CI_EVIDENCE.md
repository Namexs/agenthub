# AGENTHUB — CI & Dependency Security Evidence (Phase 4)

## 1. The headline: CI has never run on GitHub

This repo has **no GitHub remote** (`git remote -v` is empty). The
workflow in `.github/workflows/ci.yml` has therefore **never executed
on GitHub**, and no claim of "CI passed" can be made until a remote
exists and a real run is green. What this document provides instead is
**local evidence**: every workflow step was run on this machine with
the same commands the workflow uses, and the logs are saved under
`logs/phase4-ci-*.log`.

Two workflow steps could NOT be reproduced locally, for environment
reasons (not repo reasons) — see §3.

## 2. What changed in the workflow

`.github/workflows/ci.yml` was rewritten (8 jobs, was 5):

| Job         | Steps                                             | New in Phase 4                                       |
| ----------- | ------------------------------------------------- | ---------------------------------------------------- |
| `web`       | lint, typecheck, **vitest**, build (chain 97)     | vitest step (M4 tests existed but CI never ran them) |
| `shared`    | lint, typecheck, **vitest**                       | vitest step                                          |
| `format`    | prettier check, forge fmt check                   | — (unchanged)                                        |
| `audit`     | `pnpm audit --audit-level=high`                   | — (unchanged; see §3 for the local result)           |
| `contracts` | forge build, forge test                           | — (unchanged)                                        |
| `fuzz`      | `forge test --fuzz-runs 10000 --fuzz-seed 42`     | **new job**                                          |
| `slither`   | `slither . --exclude-dependencies --fail-medium`  | **new job**                                          |
| `secrets`   | gitleaks over full history (`fetch-depth: 0`)     | **new job**                                          |
| `manifest`  | `./scripts/verify-manifest.sh` (`fetch-depth: 0`) | **new job — added in Phase 3, not Phase 4** (see §9) |

Other hardening:

- **Pinned toolchains in one place** (`env:` block): Node `20.17.6`
  (was the floating `20`), pnpm `9.15.4`, Foundry `1.9.0`, Slither
  `0.11.6`, Python `3.12`.
- **Concurrency group** with `cancel-in-progress: true` (one run per
  branch; a new push cancels the stale run).
- **`timeout-minutes` on every job** (10–30 min; no hung runner).
- **Minimal permissions kept**: `contents: read` (top level).
- **Frozen lockfile kept**: every JS job runs
  `pnpm install --frozen-lockfile`.
- **No secrets are printed or used** by any job. The workflow uses no
  repository secrets at all.

The fuzz job pins `--fuzz-seed 42` deliberately: an unreproduced
transient failure (1 in ~13 runs, cause never identified) was
documented during the remediation (see
`docs/REGRESSION_RESULTS.md` §4.4). A pinned seed makes a fuzz failure
reproducible; the main `contracts` job keeps the default random seed
for breadth. The trade-off is documented in the workflow itself.

### What was NOT added, and why

- **No E2E job.** The Playwright smoke test needs the `playwright`
  package, which is not in `package.json` (it cannot be added on this
  VM — see §4). Adding an E2E job that installs it ad-hoc in CI would
  mix npm into a pnpm workspace. The smoke test runs locally
  (`bash apps/web/scripts/run-e2e-smoke.sh`) until playwright is added
  to the repo on a normal machine.
- **No manifest-check job.** The package manifest is regenerated in
  Phase 3 (last). A CI job verifying it would fail on every commit
  between now and Phase 3, because Phases 1–8 changed files without
  regenerating the manifest (by design — Phase 3 certifies the FINAL
  commit). Recommended as a follow-up after Phase 3: add
  `scripts/verify-manifest.sh` as a CI step.
- **No `pnpm add` in CI.** Installing the missing test deps inside a
  CI run would mutate the checkout; the deps belong in `package.json`
  - the lockfile, committed from a normal machine (§4).

## 3. Local evidence per job (all run 2026-11-19)

| Job       | Local command(s)                                           | Result                                                                                  | Log                                                                                      |
| --------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| web       | lint, typecheck, vitest, build (`NEXT_PUBLIC_CHAIN_ID=97`) | **PASS** — lint clean, tsc clean, **136 passed + 4 skipped** (anvil), build 11/11       | `logs/phase4-ci-web.log`                                                                 |
| shared    | lint, typecheck, vitest                                    | **PASS** — 8/8                                                                          | `logs/phase4-ci-shared.log`                                                              |
| format    | `pnpm format:check`, `forge fmt --check`                   | **PASS** (after 2 fixes, see below)                                                     | `logs/phase4-ci-format.log`                                                              |
| audit     | `pnpm audit --audit-level=high`                            | **CANNOT RUN HERE** — registry 403 (see §3.1); OSV substitute: **76 findings** (see §6) | `logs/phase4-ci-audit.log`, `logs/phase4-ci-audit-osv.log`, `logs/phase4-osv-audit.json` |
| contracts | `forge build`, `forge test`                                | **PASS** — 255/255                                                                      | `logs/phase4-ci-contracts.log`                                                           |
| fuzz      | `forge test --fuzz-runs 10000 --fuzz-seed 42`              | **PASS** — 255/255, 10k runs, seed 42                                                   | `logs/phase4-ci-fuzz.log`                                                                |
| slither   | `slither . --exclude-dependencies --fail-medium`           | **PASS** (exit 0) — 12 results, **0 High/Medium**                                       | `logs/phase4-ci-slither.log`                                                             |
| secrets   | `gitleaks detect --log-opts="--all"` (v8.24.3)             | **PASS** — 46 commits, 0 leaks (after allowlist, see §5)                                | `logs/phase4-ci-secrets.log`                                                             |
| install   | `pnpm install --frozen-lockfile`                           | **CANNOT RUN HERE** — chown blocked (see §3.2)                                          | —                                                                                        |

### 3.1 `pnpm audit` cannot run on this VM (registry policy)

```
ERR_PNPM_AUDIT_BAD_RESPONSE — The audit endpoint
(https://registry.npmjs.org/-/npm/v1/security/audits) responded
with 403: {"detail": "POST /-/npm/v1/security/audits not permitted
by policy", "error": "policy_denied"}
```

The egress proxy allows registry metadata and package downloads but
denies the audit POST. This is the same block noted in the Phase 1
audit (L9) — it has not changed. The CI audit job will run on GitHub
runners, where the endpoint is reachable. The local substitute is the
OSV audit (§6), which queries the same advisory database.

### 3.2 `pnpm install --frozen-lockfile` cannot run on this VM (chown)

`chown` is blocked on this VM's filesystem even as root
(`Operation not permitted`), so every pnpm write fails with
`EPERM: chown '<lockfile>.tmp'` — including `--lockfile-only`.
Evidence the lockfile is nonetheless consistent: `git diff c5bed05`
over `**/package.json` + `pnpm-lock.yaml` is **empty** — no dependency
manifest has changed since the baseline, so a frozen-lockfile install
on a normal machine has nothing to disagree about. (The Phase 8 test
deps were deliberately NOT added to `package.json` for exactly this
reason — see §4.)

Side note: `pnpm` itself was intermittently missing from `PATH` on
this VM during Phase 4 (the binary is not in the current cell image;
earlier calls in this session had it). The local evidence runs used
`npx -y pnpm@9.15.4` (same pinned version) as a substitute. This does
not affect the repo or CI.

### 3.3 Format fixes made during the local run

The first local `format:check` failed on 3 files:

- `apps/web/.anvil-deployment.json` and
  `packages/contracts/.anvil-deployment.json` — generated, gitignored
  anvil artifacts. Fix: added to `.prettierignore` (machine-written
  JSON, same rationale as the generated ABIs).
- `FINAL_REMEDIATION_DIRECTIVE.md` — the remediation spec. Fix: ran
  `prettier --write` on it; the diff is 2 added blank lines only
  (formatting, no content change).

Re-run after the fixes: **all matched files use Prettier code style**,
`forge fmt --check` clean.

## 4. The test-dependency gap (hook tests + E2E in CI)

`@testing-library/react`, `jsdom`, and `playwright` are **not** in
`package.json` / `pnpm-lock.yaml`, because the lockfile cannot be
regenerated on this VM (§3.2). Consequences for CI:

- The `web` job's vitest step runs the **lib tests only (78)** on a
  fresh checkout — the hook tests (58) are not collected when the deps
  do not resolve (see `vitest.config.ts`). They never fail CI; they
  simply do not run until the deps are committed.
- The E2E smoke test does not run in CI at all (see §2).

On a normal machine, one command closes the gap:

```
pnpm add -D @testing-library/react jsdom playwright
npx playwright install chromium
```

then commit the updated `package.json` + `pnpm-lock.yaml`. The hook
tests join the `web` job automatically, and the E2E script becomes
runnable in CI. This is a documented follow-up, not a silent gap:
the workflow, the vitest config, and the E2E script header all say
so. Local evidence that the tests pass WITH the deps is in
`logs/phase8-vitest.log` (136 passed) and
`logs/phase8-e2e-smoke.log` (23/23).

## 5. Secret scanning — what was found, and the config trap

**First run (no config): 11 leaks found** (exit 1) —
`logs/phase4-ci-secrets-before-allowlist.log`. Every one is the same
class:

- 10× Foundry **Anvil dev private keys** (accounts 0/1/2:
  `0xac09…`, `0x59c6…`, `0x5de4…`) in test files, local deploy
  scripts, and their logs. These are PUBLIC keys printed in every
  `anvil` banner and in the Foundry book; they hold no real funds and
  are used only against a local anvil instance.
- 1× a **MockERC20 token address** in an anvil log — a false positive
  of the `generic-api-key` rule (an address, not a secret).

**Handling:** `.gitleaks.toml` allowlists the exact values (5 regexes),
with a written justification in the file. The allowlist is by VALUE,
not by path — a real secret in any file still fails the scan. One
entry is the `…4f3ff80` transcription typo of the account-0 key that
lived in one old commit (fixed in the tree since); it is allowlisted
because gitleaks scans full history.

**The config trap (caught by a negative control):** the first
`.gitleaks.toml` contained only the allowlist — and gitleaks
**replaces** its default rule set when a config file is given, so
that config produced a silent false clean (0 rules, 0 findings).
The negative control (a fake `-----BEGIN RSA PRIVATE KEY-----` block

- a `ghp_` token in a scratch dir) was NOT detected, which exposed
  the problem. The fix is `[extend] useDefault = true` at the top of
  the config. After the fix:

* Repo scan: **46 commits, 0 leaks** (exit 0) —
  `logs/phase4-ci-secrets.log`.
* Negative control: **2 leaks found** (the private key + the token)
  with the same config — `logs/phase4-ci-secrets-control.log`. (The
  AWS example key `AKIAIOSFODNN7EXAMPLE` in the control dir was not
  flagged — gitleaks' default config allowlists that documented
  example value.)

The `secrets` CI job uses `gitleaks/gitleaks-action@v2`, which loads
`.gitleaks.toml` from the repo root automatically.

## 6. Dependency audit (OSV substitute — the headline finding)

`pnpm audit` is blocked here (§3.1), so the locked tree was audited
against the OSV database (same GitHub Advisory Database that backs
npm audit) with the committed script `scripts/osv-audit.mjs`:
**920 packages queried, 76 findings — 8 CRITICAL, 21 HIGH,
41 MODERATE, 6 LOW.** Full JSON: `logs/phase4-osv-audit.json`.

### 6.1 HIGH/CRITICAL findings (29)

Dominated by **`next@14.2.18`** (13 HIGH/CRITICAL, incl. 3 CRITICAL):

| ID                                               | Package                     | Issue                                                | Fixed in             |
| ------------------------------------------------ | --------------------------- | ---------------------------------------------------- | -------------------- |
| GHSA-2464-fhr4-w9xw (CRITICAL)                   | next@14.2.18                | Unauthenticated RCE in Image Optimization API (SVG)  | 15.5.28 / 16.4.1     |
| GHSA-2xp9-vwfh-vxw4 (CRITICAL)                   | next@14.2.18                | Unauthenticated RCE in Image Optimization API (AVIF) | 15.5.24 / 16.3.3     |
| GHSA-p293-qw3h-jr36 / CVE-2026-75604 (CRITICAL)  | next@14.2.18                | Unauthenticated RCE on Windows-hosted servers        | 15.5.24 / 16.3.3     |
| GHSA-f82v-jwr5-mffw / CVE-2025-29927 (CRITICAL)  | next@14.2.18                | Authorization bypass in Middleware                   | 14.2.25 / 15.2.3     |
| GHSA-5xrq-8626-4rwp / CVE-2026-47429 (CRITICAL)  | vitest@2.1.9 + vitest@3.2.4 | Vitest UI server: arbitrary file read/exec           | 3.2.6 / 4.1.0        |
| GHSA-5gmw-xhrv-c9v3 / CVE-2026-104848 (CRITICAL) | tinypool@1.1.1              | Prototype pollution → RCE in worker options          | 2.1.1                |
| GHSA-85c8-ppgw-ccpr / CVE-2026-104849 (CRITICAL) | tinypool@1.1.1              | Prototype pollution → RCE in run() options           | 2.1.2                |
| + 9 more HIGH on next@14.2.18 (SSRF, DoS)        |                             |                                                      | mostly 15.5.x / 16.x |
| GHSA-8rgj-285w-qcq4 (HIGH)                       | @coinbase/wallet-sdk@4.2.1  | Unknown vuln in Coinbase Wallet SDK                  | 4.3.0                |
| GHSA-qr28-fpjm-wq7f / CVE-2026-118664 (HIGH)     | decode-uri-component@0.2.2  | ReDoS                                                | 0.5.1                |
| GHSA-5j98-mcp5-4vw2 / CVE-2025-64756 (HIGH)      | glob@10.3.10                | CLI command injection via --cmd                      | 10.5.0 / 11.1.0      |
| GHSA-6g55-p6wh-862q / CVE-2026-45623 (HIGH)      | postcss@8.4.31 + 8.4.47     | Arbitrary file read via sourceMappingURL             | 8.5.12               |
| GHSA-r28c-9q8g-f849 / CVE-2026-73646 (HIGH)      | postcss@8.4.31 + 8.4.47     | Path traversal via sourceMappingURL                  | 8.5.18               |
| GHSA-587h-7wmj-h5pm / CVE-2026-112942 (HIGH)     | vite@5.4.21                 | launch-editor check bypass (Windows)                 | 6.4.4+               |
| GHSA-96hv-2xvq-fx4p / CVE-2026-48779 (HIGH)      | ws@8.18.0                   | Memory exhaustion DoS                                | 8.21.0               |
| GHSA-mrhx-c7xc-m3w5 / CVE-2023-54404 (HIGH)      | zod@3.23.8                  | Memory exhaustion on oversized collections           | 4.6.6                |

MODERATE/LOW (47): next 19, vite 7, postcss 4, @vitest/mocker 4,
vitest 2, uuid 2, + 9 singles (full list in the JSON).

### 6.2 Exploitability in THIS project (honest assessment)

None of the 29 HIGH/CRITICAL findings is directly exploitable in
AGENTHUB as deployed — but "not exploitable here" is not "not a
finding", and the CI audit job will FAIL on them until they are
addressed (see §6.3).

- **Next.js RCEs (Image Optimization):** require the Image
  Optimization API serving attacker-chosen SVG/AVIF. The app is a
  **static export** (11/11 static pages, no `next/image` remote
  images, no server). Not reachable.
- **Next.js Windows RCE:** requires Windows hosting. The deploy
  target is Linux (Vercel/Node). Not reachable.
- **Next.js middleware bypass (CVE-2025-29927):** requires
  middleware. The app has **no middleware**. Not reachable.
- **Next.js SSRF/DoS (Server Actions, rewrites, RSC):** require
  Server Actions / custom servers / middleware. The app uses none.
  Not reachable.
- **Vitest UI RCE:** requires the Vitest UI server listening
  (`vitest --ui`). The repo only ever runs `vitest run`. Not
  reachable in dev or CI.
- **tinypool RCE:** requires attacker-controlled worker options.
  tinypool is a vitest transitive dep; options come from the repo's
  own vitest config. Not reachable.
- **PostCSS file read/traversal:** requires attacker-controlled CSS
  with malicious `sourceMappingURL` comments. PostCSS runs at build
  time on the repo's own CSS. Not reachable.
- **zod memory exhaustion:** requires validating attacker-sized
  collections. The app uses zod only for env validation (small,
  fixed inputs). Not reachable.
- **glob CLI injection:** requires invoking the glob CLI with
  `--cmd`. The repo never invokes it. Dev-only transitive dep.
- **ws / vite / decode-uri-component / coinbase SDK:** dev-only
  transitive deps (or, for the wallet SDK, a client-side dep whose
  advisory has no published detail — "unknown vulnerability").

The residual risk is **supply-chain drift, not direct exploitation**:
the tree is 11+ months behind on Next.js patch releases, and any
future feature that turns on middleware, image optimization, or
Server Actions would activate these vulns. The upgrade path is a
pre-mainnet requirement, not a testnet blocker (see §6.3).

### 6.3 Consequence for CI + recommended remediation

- The `audit` CI job (`pnpm audit --audit-level=high`) is
  **expected to FAIL** on its first real run, because the locked tree
  carries HIGH/CRITICAL advisories. The job is correctly strict; the
  tree is not clean. This is recorded here rather than hidden by
  weakening the job (no `continue-on-error`, no audit-level
  downgrade).
- **Recommended (on a normal machine, before mainnet):**
  1. `pnpm update next@14.2.35` (latest 14.x patch — fixes
     CVE-2025-29927 + 2 HIGH DoS; the RCEs need 15.x/16.x).
  2. Plan the **Next.js 15.5.28+ / 16.4.1+ major upgrade** before any
     deploy that uses image optimization, middleware, or Server
     Actions (breaking-change review required; out of scope for this
     remediation).
  3. `pnpm update vitest@3.2.6` (fixes the CRITICAL UI RCE + pulls a
     fixed tinypool), `postcss@8.5.18`, `ws@8.21.0`.
  4. Re-run `scripts/osv-audit.mjs` after the upgrades and confirm
     the HIGH/CRITICAL count drops to 0.
- **Not done in this phase:** no dependency was upgraded here. Every
  upgrade needs a lockfile regeneration, which is impossible on this
  VM (§3.2), and a Next.js major upgrade is out of scope for the
  remediation directive. The findings are carried into
  `FINAL_SECURITY_FINDINGS.md` (Phase 9) as open items.

## 7. Slither in CI — count change 10 → 12

The local Slither run (same command as the CI job) exits 0 with
`--fail-medium`: **12 results, 0 High/Medium**. The count rose from
10 (post-remediation baseline) to 12 because the Phase 5 staticcall
hardening added 2 intentional low-level-call sites
(`QuestManager._validateOnChain`, `TokenBalanceValidator.validate`),
each flagged once by the `assembly` detector and once by the
`low-level-calls` detector (both Informational). Breakdown: timestamp
4 (Low), assembly 3 (Info), low-level-calls 3 (Info), pragma 1
(Info), cyclomatic-complexity 1 (Info). The new findings are the
hardening itself, not regressions — see `FINAL_SECURITY_FINDINGS.md`
(Phase 9) for the per-detector disposition.

## 8. Verdict for Phase 4

- Workflow strengthened: 8 jobs (vitest, fuzz 10k pinned seed,
  Slither `--fail-medium`, gitleaks), pinned toolchains,
  concurrency + timeouts, minimal permissions, frozen lockfile.
- Local evidence: 7 of 8 jobs green locally (web, shared, format,
  contracts, fuzz 10k, slither, secrets); the 8th (audit) cannot run
  its `pnpm audit` step on this VM and was substituted with the OSV
  audit (§6).
- Two steps cannot run on this VM (audit endpoint 403, pnpm install
  chown) — both documented with substitutes (OSV audit; lockfile
  untouched since baseline).
- **Open item carried forward:** the dependency tree carries 8
  CRITICAL + 21 HIGH advisories (mostly Next.js 14.2.18); the CI
  audit job will fail until the upgrades in §6.3 land. Not
  exploitable in the current static deployment, but a pre-mainnet
  requirement.
- **CI has still never run on GitHub.** The first real run needs a
  remote + a push; until then this document is the evidence.

## 9. Addendum (Phase 3, 2026-11-19): the 9th job

Phase 4 deliberately did NOT add a manifest-check job (the manifest
is regenerated in Phase 3 LAST, so the check would have failed on
every commit until then). Phase 3 added it: job `manifest` runs
`./scripts/verify-manifest.sh` with a full-history checkout. Local
evidence: `logs/phase3-manifest-verify.log` — 288 files checked,
100% match, both submodule gitlinks OK. The workflow now has
**9 jobs**. The "8 jobs" wording in §2 and §8 above describes the
workflow as Phase 4 left it; it is kept as the Phase 4 record.
