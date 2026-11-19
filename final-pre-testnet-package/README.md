# AGENTHUB — Final Pre-Testnet Cleanup Evidence Package

**Date:** 2026-11-19. **Baseline:** `76572c6` (remediation, 193/193).
**Code frozen at:** `5775cd3`. This package is the frozen evidence for
`docs/FINAL_PRE_TESTNET.md` — read that report first; this README is the
index.

## Verdict (from the report)

**GO for BSC testnet staging** (conditional on tBNB + deployer key from
the user and acceptance of the transient-failure caveat — not
reproduced after 8 full green runs). **NO-GO for mainnet.**

## Results at a glance

| Check | Result |
|---|---|
| Foundry full suite (unseeded) | 218 passed, 0 failed (16 suites) |
| Foundry fuzz 10,000 runs | 218 passed, 0 failed |
| Foundry seeded runs (5 seeds) | 5 × 218 passed, 0 failed |
| Vitest (web + shared) | 24 passed, 0 failed |
| Slither 0.11.6 | 10 findings: 0 Critical/High/Medium, 4 Low, 6 Informational (identical set to baseline) |
| lint / typecheck / format / forge fmt / web build | all exit 0 |
| Aggregate `pnpm test` | exit 0 (forge 218 + vitest 24) |
| Manifest | 210 hashes, 0 mismatches |

## Contents

- `reports/FINAL_PRE_TESTNET.md` — frozen copy of the report.
- `logs/` — raw command output (never tail-only):
  - `baseline-forge-test.log` — 193/193 at `76572c6` (pre-cleanup baseline).
  - `transient-run-seed-{1,42,12345,987654321,20261119}.log` — the five
    seeded full runs (item 8); all 218/218.
  - `final-forge-test.log` — unseeded full run; 218/218.
  - `final-forge-fuzz-10k.log` — fuzz 10,000 runs; 218/218.
  - `final-slither.log`, `final-slither.json` — Slither 0.11.6 output.
  - `final-pnpm-lint.log`, `final-pnpm-typecheck.log`,
    `final-pnpm-format.log` (first run, failing — pre-existing),
    `final-pnpm-format2.log` (after the fix, green),
    `final-pnpm-build.log`, `final-pnpm-test.log`.
  - `final-forge-fmt.log` — `forge fmt --check`.

## How to verify

```bash
git clone --recurse-submodules <repo-url> agenthub && cd agenthub
./scripts/verify-manifest.sh   # manifest vs the recorded commit
cd packages/contracts && forge test   # 218 tests
cd ../.. && pnpm test                 # forge 218 + vitest 24
```

## Commits (cleanup, on top of `76572c6`)

`9cda09f` allowlist · `657502f` Safe validation · `abf7491` Vitest ·
`62ad154` VERIFIER_ROLE SOP · `05d6395` gate + design docs · `5775cd3`
format fix · report + package + manifest commits (see git log).
