# AGENTHUB — CI/CD Final Validation (Phase G)

**Date:** 2026-11-19. **Phase:** G — CI/CD validation.
**Scope:** the full GitHub Actions workflow (`.github/workflows/ci.yml`,
9 jobs, 12 checks) — every step executed locally under the CI-pinned
toolchains, plus the dependency-audit allowlist mechanism that Phase B
identified as necessary.
**Verdict: GATE G — PASSED.** All 12 checks reproduce locally and pass
(11 in a fresh clean copy under Node v20.20.2 + pnpm 9.15.4 + Foundry
1.9.0 + Slither 0.11.6; the secrets scan in the repo). Three defects
were found and fixed in this phase — one of them (a nonexistent pinned
Node version) would have failed every JS job on GitHub at the setup
step. **CI has still never run on GitHub** (the repo has no remote):
nothing in this report claims a GitHub CI pass.

## 1. The 12 checks — local results

All steps below ran in a fresh clean copy (`git archive` of commit
`501d42c` + submodules, `/var/tmp/agenthub-ci`) except the secrets scan
and the manifest verification, which need git history and ran in the
repo. Toolchain in the clean copy: Node **v20.20.2**, pnpm **9.15.4**
(corepack), forge **1.9.0**, slither **0.11.6** — exactly the CI pins
after the fix in §2.1.

| #   | Check (CI job)        | Result | Evidence                                                                                                                                                                          |
| --- | --------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Web lint              | PASS   | `pnpm --filter @agenthub/web lint`, exit 0 (`phase-g-ci-web.log`)                                                                                                                 |
| 2   | Shared lint           | PASS   | `pnpm --filter @agenthub/shared lint`, exit 0 (`phase-g-ci-shared.log`)                                                                                                           |
| 3   | TypeScript            | PASS   | web `typecheck` exit 0; shared `typecheck` exit 0                                                                                                                                 |
| 4   | Unit tests            | PASS   | web vitest **136 passed + 4 skipped (140)**, 7 files passed + 1 skipped; shared **8/8** (`phase-g-ci-web.log`, `phase-g-ci-shared.log`)                                           |
| 5   | Production build      | PASS   | `NEXT_PUBLIC_CHAIN_ID=97 pnpm --filter @agenthub/web build`, exit 0, 8 routes, all static (`phase-g-ci-web.log`)                                                                  |
| 6   | Solidity tests        | PASS   | `forge build` exit 0; `forge test` **255/255** (19 suites, 52.88s) (`phase-g-ci-contracts.log`)                                                                                   |
| 7   | Solidity formatting   | PASS   | `forge fmt --check` exit 0; `pnpm format:check` exit 0 after the fixture fix (§2.3; recheck `phase-g-format-recheck.log`)                                                         |
| 8   | Fuzz                  | PASS   | `forge test --fuzz-runs 10000 --fuzz-seed 42` **255/255** (60.99s) (`phase-g-ci-fuzz.log`)                                                                                        |
| 9   | Slither               | PASS   | `slither . --exclude-dependencies --fail-medium` exit 0; 12 results (4 Low + 8 Info, 0 High/Medium — same checks as baseline) (`phase-g-ci-slither.log`)                          |
| 10  | Dependency audit      | PASS\* | Allowlist script against the fixture: exit 0, 12 allowlisted + 3 moderate non-gating (`phase-g-ci-audit.log`). \*Live `pnpm audit` cannot run on this VM (registry 403) — see §4. |
| 11  | Gitleaks (secrets)    | PASS   | gitleaks 8.27.2 `detect` in the repo: **69 commits scanned, no leaks found**, exit 0 (`phase-g-gitleaks.log`)                                                                     |
| 12  | Manifest verification | PASS   | `./scripts/verify-manifest.sh` in the repo: exit 0, **291 files, 100% SHA-256 match** for commit `9d71517`, submodules OK (`phase-g-ci-manifest-repo.log`)                        |

Supporting step: `pnpm install --frozen-lockfile` in the clean copy
under Node 20.20.2 exits 0 (`phase-g-ci-install.log`) — the second
verified clean install of this repo, the first under the CI-pinned
Node version.

## 2. Defects found and fixed in this phase

### 2.1 NODE_VERSION '20.17.6' does not exist — FIXED

The workflow pinned `NODE_VERSION: '20.17.6'`. Checked against the
nodejs.org dist index (2026-11-19): the 20.17 line stops at **20.17.0**;
there is no 20.17.6 (the line continues 20.18.0–20.18.3, 20.19.x,
20.20.x). `actions/setup-node@v4` with a nonexistent exact version
fails the step, so **every JS job (web, shared, format, audit) would
have failed on GitHub before running a single check** — the first
GitHub run would have been red for a typo, not for the code.

Fix: pinned to **`20.20.2`**, the latest Node 20 LTS patch at
verification time (keeps the Node 20 line the project chose; vitest 4
requires Node ^20||^22||>=24). The tarball was downloaded and the
binary verified (`v20.20.2`) — the whole §1 battery then ran under it.
The workflow comment records why the pin changed.

All other pins were verified to exist: pnpm **9.15.4** (used
throughout), Foundry **1.9.0** (GitHub release `v1.9.0`; local forge
is 1.9.0), Slither **0.11.6** (PyPI; local venv is 0.11.6), Python
**3.12** (a setup-python range, resolves to the latest 3.12.x).

### 2.2 The audit job would fail on GitHub — allowlist mechanism added

Phase B left 12 Next.js 14.2.35 findings (3 CRITICAL + 9 HIGH, fixes
only in Next.js 15.x/16.x) with documented risk acceptance. A bare
`pnpm audit --audit-level=high` would fail on them, so the audit job
as committed could never go green on GitHub. The job was **not**
weakened or deleted; it is now scoped, visibly:

- **New script `scripts/pnpm-audit-allowlist.mjs`** (committed,
  prettier-formatted). It runs `pnpm audit --json`, then:
  - passes only allowlisted advisories, matched on **full GHSA id +
    package** (an advisory without a GHSA id can never match —
    fail-closed);
  - prints every allowlisted finding on each run, with its
    justification and fixed-in version (each entry references
    `DEPENDENCY_REMEDIATION_REPORT.md` §6) — the accepted risk stays
    visible in every CI log;
  - **fails (exit 1)** on any NEW high/critical finding;
  - **fails (exit 1)** on a STALE allowlist entry (an advisory no
    longer reported) so the allowlist cannot rot;
  - **fails (exit 2)** if `pnpm audit` itself errors or returns
    non-JSON — it never passes silently;
  - counts moderate/low findings and prints them, but does not gate
    on them (matches the old `--audit-level=high` semantics).
- **Fixture `scripts/pnpm-audit-allowlist.fixture.json`**: the 12
  allowlisted advisories + 3 moderate, built from the real OSV audit
  (`phase-c-osv-audit.json`), in `pnpm audit --json` shape. The
  script accepts `--audit-file <path>` for local testing only; CI
  never uses it.
- **Workflow updated**: the audit job now runs
  `node scripts/pnpm-audit-allowlist.mjs` with an explanatory comment.

**Test evidence** (`phase-g-audit-allowlist-test.log`), 4 cases:

| Case | Input                                  | Expected | Actual                        |
| ---- | -------------------------------------- | -------- | ----------------------------- |
| 1    | Fixture only (12 allowlisted + 3 mod.) | exit 0   | exit 0                        |
| 2    | Fixture + 1 fake new HIGH (lodash)     | exit 1   | exit 1, names the finding     |
| 3    | Fixture minus 1 allowlisted advisory   | exit 1   | exit 1, names the stale entry |
| 4    | Audit error shape (registry 403)       | exit 2   | exit 2                        |

### 2.3 Stale web-job comment — FIXED

The workflow comment claimed the hook tests "join automatically once
@testing-library/react + jsdom are added … until then they are
skipped". False since Phase C: the deps are declared and the 58 hook
tests run (136 passed in §1). The comment now says so.

### 2.4 Audit fixture failed `format:check` — FIXED

The clean-copy format job returned prettier exit 1 on
`scripts/pnpm-audit-allowlist.fixture.json` (machine-written JSON,
1-space indent). The fixture was formatted with prettier (JSON
semantics unchanged — the allowlist script still passes on it) and a
full `pnpm format:check` re-run exits 0. The failure and the fix are
both in the evidence logs; this is exactly what the format job is
for. `forge fmt --check` passed throughout.

## 3. Workflow structure — review

Read in full (`.github/workflows/ci.yml`): 9 jobs, all with
`timeout-minutes`; top-level `permissions: contents: read` (minimal);
concurrency group with `cancel-in-progress: true`; toolchains pinned
in one `env:` block (after §2.1, all pins exist); the `secrets` job
uses `fetch-depth: 0` (full-history scan) and so does `manifest`.
Trigger: push + pull_request on `main`. No job writes anything, no
job needs secrets, no job deploys. The workflow header already states
the repo has no GitHub remote and the workflow has never run on
GitHub — still true (see §4).

**Not in CI (deliberate, recorded):** the E2E smoke test and the
wallet E2E suite (Phase F) are not CI jobs. Phase 4 excluded E2E
because playwright was not a declared dependency; that blocker is
gone since Phase C (playwright 1.65.1 is declared). Adding an E2E job
is a recommended follow-up, not done here: it needs anvil + a
Playwright browser install in the runner and would be a new job, not
a fix to an existing one. The suites are run locally and their
evidence is in the Phase C/F reports.

## 4. What could NOT be verified locally — stated plainly

1. **CI on GitHub (BLOCKER, unchanged).** The repo has no GitHub
   remote. The workflow has never run on GitHub, and no local run —
   however faithful — proves a GitHub run. The first real GitHub run
   needs a user-created remote. This is the single largest blocker
   for a GO decision and is carried into Phase I.
2. **Live `pnpm audit`.** The VM registry proxy returns 403
   (`policy_denied`, `zz_managed_internal_spaces_package_registries`)
   for `POST /-/npm/v1/security/audits` — `pnpm audit` exits 1 with
   `ERR_PNPM_AUDIT_BAD_RESPONSE` (evidence:
   `phase-g-pnpm-audit.json` + `phase-g-pnpm-audit.err`; same
   limitation as Phase 4). The allowlist script's **live path** is
   therefore untested locally; only the fixture path was exercised
   (4 cases, §2.2). The first GitHub run is the real test of the
   audit job. The OSV audit (Phase B/C: 33 findings) remains the
   working local substitute for the dependency-audit evidence.
3. **Gitleaks version delta.** Locally 8.27.2 (downloaded from
   GitHub releases — gitleaks is not installed on the VM);
   `gitleaks-action@v2` bundles its own recent 8.x. Same rule family;
   a future rule addition could flag something locally clean, but
   the current scan is clean on 69 commits.
4. **Manifest job in the clean copy.** `verify-manifest.sh` needs
   git history, which a `git archive` copy has by design not. It
   exits 1 there with "not a git repository" — an artifact of the
   copy method, not a repo failure (`phase-g-ci-manifest.log`). The
   real result is the repo run: exit 0 (§1, check 12). In CI the job
   runs in a full checkout (`fetch-depth: 0`), so this does not
   apply.
5. **The battery ran from commit `501d42c`.** The only later commit
   at report time (`d1947b7`) is the formatting-only fixture fix
   (§2.4), verified by re-running the allowlist script (exit 0) and
   `format:check` (exit 0). Phase I re-runs the full suite from the
   final commit anyway.

## 5. Files changed in this phase

| File                                        | Change                                                                                                                 |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/ci.yml`                  | Node pin 20.17.6 → 20.20.2 (+ comment); audit job runs the allowlist script (+ comment); stale hook-test comment fixed |
| `scripts/pnpm-audit-allowlist.mjs`          | NEW — fail-closed audit allowlist (12 Next.js advisories)                                                              |
| `scripts/pnpm-audit-allowlist.fixture.json` | NEW — fixture built from the real OSV audit (12 + 3 advisories)                                                        |
| `agenthub-final-release/CI_FINAL_REPORT.md` | This report                                                                                                            |
| `agenthub-final-release/logs/phase-g-*`     | 15 evidence files (battery, allowlist tests, gitleaks, audit 403, manifest, format recheck)                            |

No application code, no contract code, and no test was changed in
this phase. No CI check was disabled, weakened, or deleted: the
audit job is scoped by an explicit, visible, fail-closed allowlist,
and the format job caught a real defect (§2.4) — proof the checks
still bite.

## 6. Gate G verdict

**GATE G — PASSED.** All 12 checks reproduce locally and pass under
the CI-pinned toolchains; the two defects that would have failed the
first GitHub run (nonexistent Node pin, unpassable audit job) are
fixed with evidence; the remaining blocker — no GitHub remote — is
explicitly outside what this phase can resolve and is carried
forward to the final decision.
