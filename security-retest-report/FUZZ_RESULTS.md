# AGENTHUB — Fuzz Test Results (10.000 runs)

**Tanggal:** 2026-11-19 ~14:21 WIB
**Baseline:** audit — 5 fuzz test, masing-masing 10.000 run, semua lolos.

**Perintah:**
```
forge test --fuzz-runs 10000
```
**Exit code:** 0
**Hasil keseluruhan:** 120 lolos, 0 gagal, 0 dilewati (10 suite, 39,25 dtk)
**Log:** `logs/forge-test-fuzz10k.log`

## Hasil per fuzz test

| Test | Runs | Hasil | Gas μ / ~ |
|---|---|---|---|
| `testFuzz_MintGrantsBalance(address)` | 10.000 | PASS | 96.095 / 96.160 |
| `testFuzz_CreateQuestStoresParams(uint256,uint256,uint256)` | 10.000 | PASS | 336.705 / 337.069 |
| `testFuzz_AddPointsAccumulates(uint256,uint256)` | 10.000 | PASS | 163.645 / 164.000 |
| `testFuzz_GateAgreesWithDirectBalance(address,bool)` | 10.000 | PASS | 67.869 / 28.238 |
| `testFuzz_IssueGrantsUniqueTokenIds(uint8)` | 10.000 | PASS | 924.125 / 740.824 |

Total 50.000 kasus fuzz, 0 kegagalan.

## Catatan invariant

`--fuzz-runs` tidak memengaruhi pengujian invariant — invariant diatur oleh
`--invariant-runs` (default 256). Pada run ini invariant tetap berjalan pada
256 run / 32.768 handler call, 0 revert, 5 invariant terpenuhi (lihat
`logs/suite-Invariant.log`):

- `invariant_PointsMatchGhost`
- `invariant_BadgesMatchGhost`
- `invariant_CompletionsMatchAndRespectCap`
- `invariant_EventsMatchGhost`
- `invariant_NonHolderEarnsNothing`

## Verdict

✅ Tidak ada kegagalan fuzz pada 10.000 run per test. Hasil identik dengan
baseline audit. Tidak ada counterexample yang ditemukan.
