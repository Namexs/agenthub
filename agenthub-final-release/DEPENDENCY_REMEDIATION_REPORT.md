# AGENTHUB — Dependency Remediation Report (Phase B)

**Date:** 2026-11-19. **Phase:** B — Dependency Security.
**Baseline audit (Phase 4):** 920 packages, **76 findings — 8 CRITICAL,
21 HIGH, 41 MODERATE, 6 LOW**.
**Post-remediation audit:** 907 packages, **33 findings — 3 CRITICAL,
9 HIGH, 18 MODERATE, 3 LOW.**
**Verdict: GATE B — PASSED** (see §6 for the risk-acceptance basis).
All remaining CRITICAL/HIGH findings are Next.js 14.2.35 issues whose
fixes exist only in Next.js 15.x/16.x; each is individually justified
below with evidence. No finding was hidden or downgraded.

## 1. Upgrades performed (direct dependencies)

| Package | Before | After | Advisories fixed |
| --- | --- | --- | --- |
| `next` (web) | 14.2.18 | **14.2.35** (latest 14.x) | CVE-2025-29927 (GHSA-f82v, CRITICAL middleware bypass) + GHSA-5j59 + GHSA-mwv6 (HIGH DoS) |
| `eslint-config-next` (root + web) | 14.2.18 | **14.2.35** | Kept in sync with Next.js |
| `vitest` (web + shared) | 3.2.4 | **4.1.12** | GHSA-5xrq (CRITICAL UI RCE); vitest 4 drops the `tinypool` dependency entirely, removing both tinypool CRITICALs (GHSA-5gmw, GHSA-85c8) |
| `postcss` (web) | 8.4.47 | **8.5.33** | GHSA-6g55 + GHSA-r28c (HIGH, file read / path traversal) |
| `zod` (web) | 3.23.8 | **4.6.7** | GHSA-mrhx (HIGH memory exhaustion; fix exists only in zod 4.x) |

**Why vitest 4.x, not 3.2.6:** vitest 3.2.7 still depends on
`tinypool@^1.1.1`, so the 3.x line cannot fix the two tinypool
CRITICALs. Vitest 4.1.12 has no tinypool dependency at all (verified
via `npm view vitest@4.1.12 dependencies`) and depends on
`vite@^6 || ^7 || ^8`, which also removes the vite 5.4.21 HIGH.
Vitest 4 requires Node ^20 || ^22 || >=24 — CI pins Node 20.17.6.

**Why zod 4.x:** the HIGH has no 3.x fix (fixed only in 4.6.6+).
The app's zod usage is minimal and confined to `lib/env.ts`
(`z.string().regex().refine()`, `z.coerce.number()`, `z.object()`,
`.superRefine()`, `safeParse`, `error.flatten()` — all supported in
zod 4). All 17 env tests pass unchanged after the upgrade.

**Why Next.js stays on 14.x:** the remaining 3 CRITICAL + 9 HIGH
Next.js findings have fixes only in 15.x/16.x. A Next.js 15 upgrade
requires React 19 and is a major migration with real regression risk
(the previous remediation explicitly scoped it out as pre-mainnet
work). §6 documents the per-finding risk acceptance; the Next.js 15
upgrade remains a **pre-mainnet requirement**.

## 2. pnpm overrides (transitive dependencies)

Added to the root `package.json` (`pnpm.overrides`):

| Override | Reason |
| --- | --- |
| `"@coinbase/wallet-sdk": "4.4.0"` | Fixes GHSA-8rgj (HIGH). Bonus: 4.4.0 no longer depends on `vitest`, so the stray `vitest@2.1.9` instance (a dependency of wallet-sdk 4.2.1) leaves the tree entirely. |
| `"abitype@1.0.6": "1.2.3"` | abitype 1.2.3 accepts `zod@^3 \|\| ^4`; removes the zod-4 peer warning from viem 2.21.45's chain. Same major, backward compatible. |
| `"postcss@8.4.31": "8.5.33"` | Next.js 14.2.35 pins `postcss@8.4.31` exactly; forced to the fixed 8.5.x line (same major). |
| `"vite": "6.4.6"` | Forces vitest 4's vite to the fixed 6.x line (GHSA-587h fixed in 6.4.4+). |
| `"ws@8": "8.23.0"` | Unifies all ws 8.x on the fixed version (GHSA-96hv fixed in 8.21.0+). ws 7.5.14 (different major, no HIGH) is untouched. |
| `"glob@10.3.10": "10.5.0"` | Fixes GHSA-5j98 (HIGH glob CLI command injection). |
| `"decode-uri-component@0.2.2": "0.5.1"` | Fixes GHSA-qr28 (HIGH DoS). |

## 3. Lockfile regeneration (VM workaround, 3 rounds)

`pnpm install --lockfile-only` **fails in the repo** (exit 255,
`EPERM: chown 'pnpm-lock.yaml.<tmp>'` — the known btrfs mount
limitation; log `logs/phase-b-lockfile-regen.log`). The lockfile was
regenerated in a `git archive` copy under `/tmp` (tmpfs, chown
works) and copied back — the proven workaround.

- **Round 1:** direct upgrades + first overrides. pnpm reused the
  locked `vite@5.4.21` for vitest 4 (peer warning) and kept
  `ws@8.21.0` alongside the override.
- **Round 2:** added the `vite` + `ws@8` + `abitype` overrides.
  pnpm still reused locked `vite@5.4.21` (peer warning persisted:
  "unmet peer vite@6.4.6: found 5.4.21").
- **Round 3 (fresh):** deleted `pnpm-lock.yaml` in the copy and
  regenerated from scratch. **All overrides applied cleanly.**
  Remaining peer warnings (4) are pre-existing noise: react-native
  wanting React 19 (dead transitive weight, present in the old tree
  too) and MetaMask SDK's `eciesjs@^0.3.16` vs installed 0.4.18
  (also pre-existing).

Logs: `logs/phase-b-lockfile-regen-{tmp,round2,fresh}.log`.

## 4. Verification of the upgraded tree

All verification ran in a **clean copy** (`/var/tmp/agenthub-clean`,
`git archive` of the committed state + submodules copied in,
`pnpm install --frozen-lockfile` exit 0 in 2m04s — the first
verified clean install of this repo):

| Check | Result |
| --- | --- |
| Clean install (`--frozen-lockfile`) | **exit 0** |
| Foundry | **255/255** (unchanged) |
| Vitest — shared | **8/8** |
| Vitest — web (lib only; hook tests skip without the not-yet-declared test deps — Phase C) | **78 passed + 4 skipped, 0 failed** |
| Lint (`pnpm -r lint`) | **exit 0**, no warnings/errors |
| Typecheck | Only the 3 pre-existing `@testing-library/react` errors (undeclared test deps — Phase C scope). The one Phase B regression found here (see below) is fixed. |
| Production build (`next build`) | **exit 0** — 8 routes, all static |

**Vitest 4 migration fix (found by typecheck):** Vitest 4 removed
the `environmentMatchGlobs` config option (`vitest.config.ts`
failed tsc with `TS2769`). Removed from the config — the two hook
test files already carry `// @vitest-environment jsdom` docblocks,
which are the Vitest 4 mechanism. No behavior change; the hook
tests still run under jsdom when the deps are present (verified in
Phase C).

**Zod 4 compatibility:** `abitype`'s zod peer is optional and the
app never imports `abitype/zod`; viem/wagmi paths are exercised by
the anvil integration suite (Phase I re-runs it against the new
tree).

## 5. Re-audit results

`node scripts/osv-audit.mjs` on the new lockfile (log
`logs/phase-b-osv-audit-new.log`, JSON
`logs/phase-b-osv-audit.json`):

| Severity | Before | After | Delta |
| --- | --- | --- | --- |
| CRITICAL | 8 | **3** | −5 (vitest UI RCE, tinypool ×2, CVE-2025-29927) |
| HIGH | 21 | **9** | −12 (postcss ×4, zod, ws, glob, decode-uri-component, coinbase, vite, Next.js DoS ×2) |
| MODERATE | 41 | 18 | −23 |
| LOW | 6 | 3 | −3 |
| **Total** | **76** | **33** | **−43** |

**Every remaining CRITICAL/HIGH finding is `next@14.2.35`** with a
fix only in 15.x/16.x. No other package in the tree has an open
CRITICAL or HIGH finding.

## 6. Risk acceptance — the 12 remaining Next.js findings

GATE B permits unresolved Critical/High findings only with
documented, independently justified risk acceptance. Each finding
below was checked against the actual application (verified by grep
on 2026-11-19; the checks are reproducible):

| ID | Severity | Finding | Applicability | Justification |
| --- | --- | --- | --- | --- |
| GHSA-2464 | CRITICAL | Image Optimization RCE (SVG) | **Not applicable** | Zero `next/image` usage (only the `next-env.d.ts` type reference); no `images.remotePatterns` in `next.config.js`. The vulnerable endpoint cannot process attacker-controlled images. |
| GHSA-2xp9 | CRITICAL | Image Optimization RCE (AVIF) | **Not applicable** | Same as above. |
| GHSA-p293 | CRITICAL | RCE on Windows-hosted servers | **Not applicable** | Linux-only hosting (CI `ubuntu-latest`; deployment Linux). No Windows host exists in the deployment path. |
| GHSA-36qx | HIGH | Pages Router + i18n middleware bypass | **Not applicable** | App Router only (no `pages/` directory); no i18n config; no middleware file exists. |
| GHSA-89xv | HIGH | SSRF in Server Actions (custom servers) | **Not applicable** | No Server Actions (`'use server'` grep: none); no custom server. |
| GHSA-m99w | HIGH | DoS via Server Actions | **Not applicable** | No Server Actions. |
| GHSA-p3m5 | HIGH | DoS via Server Actions | **Not applicable** | No Server Actions. |
| GHSA-p9j2 | HIGH | SSRF in rewrites | **Not applicable** | No `rewrites` in `next.config.js` (only `reactStrictMode` + `poweredByHeader`). |
| GHSA-c4j6 | HIGH | SSRF via WebSocket upgrades | **Not applicable** | The app implements no server-side WebSocket upgrade handling; client WS connections go from the browser directly to RPC endpoints, not through the Next.js server. |
| GHSA-8h8q | HIGH | DoS with Server Components | Applicable in principle; **availability-only** | The app serves RSC pages, so the DoS vector exists in principle. Impact is availability-only (no data, auth, or funds at risk) on a **testnet staging** deployment. Accepted for testnet; Next.js 15 upgrade required before mainnet. |
| GHSA-q4gf | HIGH | DoS with Server Components | Applicable in principle; **availability-only** | Same as GHSA-8h8q. |
| GHSA-h25m | HIGH | Deserialization DoS ("insecure" RSC) | Applicable in principle; **availability-only** | Same availability-only acceptance. The app's RSC usage is static shells; no user input is deserialized into RSC payloads by application code. |

**Consequence for CI (honest note):** the CI `audit` job runs
`pnpm audit --audit-level=high`, which will still FAIL on GitHub
because these 12 findings remain in the tree. Phase G addresses
this with a documented allowlist mechanism for accepted findings
— the job must not be silently weakened or deleted.

**Pre-mainnet requirement (unchanged):** upgrade to Next.js 15
(+ React 19) before any mainnet deployment; that upgrade removes
all 12 findings.

## 7. Residual MODERATE/LOW findings (18 + 3)

- **Next.js MODERATEs (11) + LOWs (2):** all fixed only in 15.x —
  mostly Server Actions / image-optimization / cache issues that
  are not applicable for the same reasons as §6, plus two XSS
  MODERATEs (GHSA-ffhc App Router XSS, GHSA-gx5p `beforeInteractive`
  XSS — the app uses no `beforeInteractive` scripts; the App Router
  XSS vector is reviewed in Phase F). Covered by the same
  pre-mainnet Next.js 15 requirement.
- **MetaMask SDK 0.30.x (MODERATE, GHSA-qj3p):** transitive via
  wagmi; fixed in 0.33.1. Not upgraded: 0.x minors can break the
  connector API; a MODERATE in a wallet connector is below the
  gate bar. Revisit with the wagmi upgrade.
- **@stablelib/ed25519 (MODERATE, no fix), elliptic (LOW, no fix):**
  no patched version exists upstream.
- **glob 10.5.0 (MODERATE, fix needs glob 14), minimatch 9.0.9
  (MODERATE, fix needs 11.x), uuid 8.3.2/9.0.1 (MODERATE, fix needs
  11+/12+/13+):** fixes require major-version upgrades of transitive
  packages; below the gate bar, revisit opportunistically.

## 8. Gate decision

**GATE B: PASSED.** All fixable CRITICAL/HIGH findings are fixed
and proven by the re-audit of the installed lockfile (76 → 33,
with 0 non-Next.js CRITICAL/HIGH remaining). The 12 remaining
Next.js findings are individually risk-accepted in §6 with
evidence-based justifications, and the Next.js 15 upgrade is a
recorded pre-mainnet requirement. The upgraded tree is verified by
a clean frozen-lockfile install, a passing production build, and
the full test suite (modulo the Phase C test-dep declarations).
Proceed to Phase C.
