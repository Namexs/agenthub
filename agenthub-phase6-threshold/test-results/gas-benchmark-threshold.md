# AGENTHUB — Phase 6 gas benchmark: threshold attestation (R-010)

**Date:** 2026-11-19. **HEAD:** `53849d9` (Phase 6 threshold work:
`48e80a5` implementation + `aea064f` tests; the numbers below were
measured on that code and re-verified by the coordinator regression
battery at `53849d9` — the gas tests are part of the 287-test suite).
**Toolchain:** solc 0.8.24, via-IR enabled (`foundry.toml`, required — see below), optimizer runs 200, EVM Cancun, Foundry `forge test`.

## Results (authoritative numbers)

Gas of one `completeQuestWithAttestation` call, measured with `gasleft()` around the call
(`test/ThresholdAttestation.t.sol`, `testGas_Threshold*` + `testGas_MarginalCostPerExtraSignature`):

| Threshold | Signatures | Completion gas |
| --------- | ---------- | -------------- |
| 1         | 1          | **242,735**    |
| 2         | 2          | **253,867**    |
| 3         | 3          | **265,221**    |

Marginal cost per extra signature:

| Step    | Marginal gas |
| ------- | ------------ |
| 1 → 2   | **11,132**   |
| 2 → 3   | **11,354**   |
| Average | **~11,243**  |

3-of-3 overhead vs 1-of-1: **22,486 gas (+9.3%)**.

Cross-check (same measurements repeated inside `testGas_MarginalCostPerExtraSignature`,
fresh account per threshold): 242,735 / 253,868 / 265,229 — agrees with the standalone
numbers within 8 gas (memory-layout noise). The standalone numbers above are the reported ones.

## Methodology

- **Identical quests:** OneTime, Attested, 100 rewardPoints, no badge, 30-day window,
  unlimited completions — the three quests differ ONLY in `attestationThreshold` (1/2/3).
- **Fresh account per threshold:** each completion is by a different Agent-ID holder
  (alice / bob / carol), so every completion touches only cold per-account + per-quest
  storage. `Reputation.addPoints` writes only `_points[account]` / `_events[account]`
  (no shared counters), so there is no cross-measurement warming.
- **Measurement:** `gasleft()` immediately before `vm.prank` + the call, minus `gasleft()`
  immediately after. `vm.prank` costs 0 gas in tests, so the number is the completion call itself.
- **What the number includes:** the full completion — attestation verification (all M
  signatures), quest state writes (6 cold zero→non-zero SSTOREs), `Reputation.addPoints`,
  and event emissions (`AttestationUsed` × M + `QuestCompleted`). The absolute figure
  (~243–265k) is dominated by the cold storage writes, not by the signatures.
- **Reproduce:** `forge test --match-test testGas -vv` (the `log_named_uint` lines print
  the measurements). The `forge test` per-test totals (266,484 / 288,264 / 309,566) are
  NOT the completion cost — they include `setUp` + off-chain signing.

## Comparison with the plan estimate

The remediation plan (§6) expected "~3k gas per extra ecrecover + calldata" and a 3-of-3
completion "still small (< 15k gas over baseline)". **Actual is ~11.2k per extra signature
and 22.5k over baseline for 3-of-3 — higher than estimated.** The plan's estimate counted
only `ecrecover` + calldata; the real per-signature cost is:

| Component (per extra signature)                   | Approx. gas |
| ------------------------------------------------- | ----------- |
| `ecrecover` precompile                            | 3,000       |
| Cold `VERIFIER_ROLE` SLOAD (distinct signer slot) | 2,100       |
| `AttestationUsed` event (LOG, 4 topics)           | ~2,000      |
| Calldata + `bytes[]` decoding + memory copy       | ~2,000      |
| Duplicate-check loop + array bookkeeping          | ~2,000      |
| **Total**                                         | **~11,100** |

**Not a blocker:** the overhead is ~9% on a ~243k-gas completion. In BNB terms at 1 gwei:
3-of-3 = 0.000265 BNB per completion; at 0.1 gwei = 0.0000265 BNB. (USD depends on the BNB
price at execution time; no USD figure is asserted here.)

## Build note (why via-IR)

These numbers are measured on a **via-IR build**. The 11-parameter `createQuest`
(threshold added as the 11th parameter) cannot compile under solc 0.8.24's legacy
code generator at all — "Stack too deep … Variable dataEnd is 1 slot(s) too deep" —
even with an empty function body, and a minimal 11-param + modifier repro fails the
same way; the delegate-to-internal-function workaround fails too (the optimizer
inlines it back). `via_ir = true` in `foundry.toml` is therefore required, not
optional. Legacy-codegen gas numbers for the same code do not exist (it does not compile),
so no legacy-vs-via-IR gas comparison is possible. Bytecode for ALL contracts changes
under via-IR; the Phase 5 opcode scan (MCOPY PCs in NEXT_PHASE_VALIDATION.md) must be
re-run before the testnet smoke test.
