# AGENTHUB — Security Review Package

> External-reviewer package for the security engineering phase.
> Code snapshot: commit `c666878` (2026-11-19).
> This package is a point-in-time snapshot: the canonical reports live in
> `docs/`; copies are frozen under `reports/` here so a reviewer can verify
> everything from this folder plus the code at the snapshot commit.
> **No mainnet deployment, no real funds, no testnet deployment** was part
> of this phase.

## Contents

| Path               | What it is                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `README.md`        | This file — final summary, counts, go/no-go                                                                                     |
| `FINDINGS.md`      | Every finding: file, function, line numbers, exploit scenario, impact; fixed vs open separated; before/after code for every fix |
| `TEST_EVIDENCE.md` | Test inventory, counts per category, commands, and the log index                                                                |
| `CHANGES.md`       | Every change made in this phase, by commit                                                                                      |
| `reports/`         | Frozen copies of the five security reports in `docs/`                                                                           |
| `logs/`            | Real command output: builds, tests, format checks, Slither, secret scan, env validation                                         |

## Final summary

### Findings by severity

| Severity      | Total | Fixed | Open                  | Notes                                                                                                |
| ------------- | ----- | ----- | --------------------- | ---------------------------------------------------------------------------------------------------- |
| Critical      | 0     | 0     | 0                     | —                                                                                                    |
| High          | 1     | 1     | 0                     | SEC-001 (fail-closed gate)                                                                           |
| Medium        | 1     | 1     | 0                     | SEC-002 (retained privilege)                                                                         |
| Low           | 2     | 1     | 1                     | SEC-003 fixed; SEC-004 accepted risk (timestamp)                                                     |
| Informational | 2     | 0     | 1 accepted group      | SEC-005 closed as false positive (no longer reported); SEC-006 accepted group of 4 Slither detectors |
| **Total**     | **6** | **3** | **2 (0 exploitable)** | **+ 1 closed false positive**                                                                        |

**Fixed: 3. Open: 2 — both accepted risks with documented rationale, neither
exploitable for fund loss or unauthorized access** (contracts hold no funds;
SEC-004's worst case is seconds-early quest completion; SEC-006 is four
reviewed informational notes). No finding was invented; every finding traces
to a failing test or a Slither detector run.

### Tests: passed vs failed

| Category                                                             | Passed  | Failed |
| -------------------------------------------------------------------- | ------- | ------ |
| Unit (MockAgentId, AgentGate, QuestManager, Reputation, Achievement) | 89      | 0      |
| Integration (real wiring + timelock)                                 | 6       | 0      |
| Stateful invariant (5 invariants, ~32,768 handler calls)             | 2       | 0      |
| Attack simulation                                                    | 7       | 0      |
| Access control matrix                                                | 10      | 0      |
| Economic attack                                                      | 6       | 0      |
| **Forge total**                                                      | **120** | **0**  |
| Web lint / typecheck / build (positive)                              | 3       | 0      |
| Web build (negative M5 case — must fail, did fail, exit 1)           | 1       | 0      |
| Format checks (`forge fmt`, prettier)                                | 2       | 0      |
| Env validation harness (8 cases)                                     | 8       | 0      |

**No failed test is hidden.** Failures encountered _during_ the phase (test
bugs and the two real contract bugs SEC-001/SEC-002) are described in
`FINDINGS.md` and `CHANGES.md`; the final full run is green and logged in
`logs/forge-test-final.log`.

### Static analysis

- **Slither 0.11.6** (solc 0.8.24), final run verified twice: **7 findings —
  0 Critical/High/Medium, 3 Low (accepted), 4 Informational (reviewed)**.
  Full JSON in `logs/slither-final.json`. An intermediate run reported 1
  Medium (`unused-return`, fixed as SEC-003) and 1 Medium false positive
  (`uninitialized-local`, SEC-005, absent from the final run).
- **Compiler warnings:** 0 solc warnings. **Foundry linter:** 20 warnings
  remain, all reviewed (4 more were fixed in code). Triage table in
  `reports/SECURITY_FINDINGS.md` (appendix).
- **`pnpm audit`:** never ran locally (registry 403 in this VM — Phase 1
  audit L9). A CI audit job now runs it on GitHub runners. **No local audit
  result is claimed.**

### Untestable risks (could not be verified in this phase)

1. Real Agent ID contract behavior on BSC mainnet (only MockAgentId tested).
2. BSC testnet Cancun EVM behavior (needs a testnet deploy).
3. Safe multisig + TimelockController interaction (only the timelock side tested).
4. Live BSC gas costs (only Foundry estimates exist).
5. Browser/wallet flows (no browser testing done).
6. Web/shared unit tests (M4): zero vitest tests — env validation was verified
   by harness + builds instead.

### Recommendation: GO / NO-GO

- **GO for BSC testnet staging** — once the user provides tBNB + a deployer
  key. All §7 security gates pass (see `reports/SECURITY_DEPLOYMENT_GATE.md`).
- **NO-GO for mainnet yet** — the pre-mainnet checklist (testnet verification,
  Safe setup, M4 vitest, CI `pnpm audit` green, external review) is not
  complete. Do not deploy to mainnet from this snapshot.

## How to verify (reviewer quickstart)

```bash
git checkout c666878
cd packages/contracts
forge build          # expect: "Compiler run successful!", 0 solc warnings
forge test           # expect: 120 passed, 0 failed (~45 s)
forge fmt --check    # expect: exit 0
cd ../..
pnpm --filter @agenthub/web lint typecheck   # expect: exit 0
NEXT_PUBLIC_CHAIN_ID=97 pnpm --filter @agenthub/web build  # expect: exit 0
pnpm format:check    # expect: exit 0
```

Compare each command's output with the matching file under `logs/`.
Slither: `slither . --exclude-dependencies` from `packages/contracts`
(Slither 0.11.6, solc 0.8.24) — expect 7 detectors, 0 Medium+; exit code
255 is Slither's "findings present" signal, not a crash.
