# AGENTHUB — Bytecode (fresh build at the audit commit)

> **Measured, not copied.** The hashes below were produced for this
> package on 20 November 2026 from a fresh `forge build --force` of the
> audit commit `e1b316b` (solc 0.8.39, via-IR, forge 1.9.0), using
> `bytecode/bytecode-audit.py` (run log: `bytecode/bytecode-audit.log`).
> The SHA-256 runtime hashes reproduce the Phase 8 published hashes
> **exactly, 4/4** — the build is reproducible. The opcode scan
> re-measures the MCOPY locations independently and confirms the Phase 8
> figures (QuestManager PC 1933, Achievement PC 4432).
>
> **Still valid for the current audit commit `7dff852`.** The only
> changes between `e1b316b` and `7dff852` are deploy scripts and tests
> (`git diff e1b316b 7dff852 -- packages/contracts/src/ apps/` is
> empty), so contract bytecode — and every hash below — is unchanged.

## 1. Bytecode hashes

| Contract     | keccak256 (creation bytecode)                                        | keccak256 (deployed bytecode)                                        |
| ------------ | -------------------------------------------------------------------- | -------------------------------------------------------------------- |
| AgentGate    | `0x36dff20ab3c5e5d3c1a9a571ce4988d2b8507af1a8ae9c4a1d9aa9853fea08e9` | `0xb23085a2b563639ade4c25a04405e457d1257ff8c42958c13c1774c174911ce6` |
| QuestManager | `0x1ee0dc194f17b76745ecd5baace7694aa75ddba475eef10d31c388ae5f269e53` | `0x993562f96730ac99ea830b7a266ccf669ccee6df7bd86989330605ac5abd4b9f` |
| Reputation   | `0xae8ff42af61f24109b338f1d65967f1fe3e7feb55a3482eaf79165337c9bc041` | `0x10b89e302bb8f9bb55457219ab9b2243d7ba4006c214400c2a205def437804c2` |
| Achievement  | `0xd14c10490a1ecdaebe711d62b1aa99feacaf519dcfecd2ddeae1ba392705da2d` | `0xc317ccd3d2730956e75bdedb7a3607c91fe8c48fe164fe4314d23b490785f4ef` |

keccak256 computed with `cast keccak` (foundry 1.9.0) over the full
bytecode hex from the forge artifacts (metadata CBOR included).

### SHA-256 (deployed bytecode) — cross-check vs Phase 8

| Contract     | SHA-256 (deployed)                                                 | Phase 8 published | Match |
| ------------ | ------------------------------------------------------------------ | ----------------- | ----- |
| AgentGate    | `adb2e727d223a34f9a81ea9f886cee76d9020c939ef43f29ea81b974dffb32d8` | `adb2e727…fb32d8` | ✅    |
| QuestManager | `c3120d24aebece3131bb77f78844616f61009e5b5cef04794d0066fcdb223e33` | `c3120d24…223e33` | ✅    |
| Reputation   | `2444f4eacd0b2dd28081021be417f9dea1f637ad98e2eb1d0202a3c9619c0258` | `2444f4ea…c0258`  | ✅    |
| Achievement  | `c4af7dedde69b1301c3ebcee2fb81c74f15083dc8b21c2b6ef70ff3d9fd75fe0` | `c4af7ded…75fe0`  | ✅    |

Full Phase 8 hashes: `agenthub-phase8-remediation/logs/18-bytecode-audit.log`
and `reports/PHASE8_SECURITY_REMEDIATION_REPORT.md` §7.

## 2. Sizes

| Contract     | Creation (bytes) | % EIP-3860 limit (49,152) | Deployed (bytes) | % EIP-170 limit (24,576) |
| ------------ | ---------------: | ------------------------: | ---------------: | -----------------------: |
| AgentGate    |            1,457 |                     2.96% |            1,058 |                    4.31% |
| QuestManager |           14,890 |                    30.29% |           13,104 |                   53.32% |
| Reputation   |            2,584 |                     5.26% |            2,255 |                    9.18% |
| Achievement  |            7,359 |                    14.97% |            6,246 |                   25.42% |

All contracts are comfortably within both limits. QuestManager is the
largest at 53.32% of the EIP-170 deployed-size limit (11,472 bytes of
headroom); growth is worth watching (PH7-I12 — a CI size check has not
yet been added). Size deltas vs the Phase 6 baseline (solc 0.8.24):
QuestManager +832 bytes (solc effect −588, code effect +1,420 from the
H01/M01/M02/L07 guards); Achievement +236 (solc −30, code +266 from the
high-value flag); AgentGate −11, Reputation +37 (code effect 0 —
unchanged contracts). No library linking (`linkReferences` empty for
all four contracts). Metadata CBOR: 51-byte payload + 2-byte length
suffix; solc version byte `000827` (0.8.39).

## 3. Opcode scan — Cancun-only opcodes (re-measured)

**Method** (same as the Phase 8 scanner): the metadata CBOR is stripped
before disassembly, and bytes inside PUSH immediates are never counted
as opcodes. Raw-hex grep is NOT used — it produces false positives
(e.g. MCOPY=4 in QuestManager by raw grep vs 1 real opcode). Scanner:
`bytecode/bytecode-audit.py`; log: `bytecode/bytecode-audit.log`.

| Contract     |             MCOPY (0x5e) | TSTORE (0x5d) | TLOAD (0x5c) | BLOBHASH (0x49) | BLOBBASEFEE (0x4a) | Total |
| ------------ | -----------------------: | ------------: | -----------: | --------------: | -----------------: | ----: |
| AgentGate    |                        0 |             0 |            0 |               0 |                  0 | **0** |
| QuestManager |  **1 @ PC 1933 (0x78d)** |             0 |            0 |               0 |                  0 | **1** |
| Reputation   |                        0 |             0 |            0 |               0 |                  0 | **0** |
| Achievement  | **1 @ PC 4432 (0x1150)** |             0 |            0 |               0 |                  0 | **1** |

### What the MCOPY findings mean

- Both MCOPYs are **real, in-code** opcodes (not metadata false
  positives — both sit far before the end of the code section), emitted
  by solc ≥ 0.8.25 codegen (memory-copy helper for `bytes[]` handling).
  This **reverses** the Phase 5/6 claim that via-IR "eliminates MCOPY":
  that claim was a metadata-hash false positive (PH7-M10, closed with
  errata in Phase 8).
- **Not a blocker:** Cancun is proven active on BSC testnet and mainnet
  (Phase 5 validation); the full test suite runs on Anvil (Cancun) and
  executes these paths. Consequence: `evm_version = "cancun"` is now a
  REAL feature dependency (see `BUILD_REPRODUCTION.md` §1) and must
  not be lowered below Cancun. The testnet smoke test must still cover
  the completion path on live BSC testnet before any mainnet deploy.
- TSTORE/TLOAD (transient storage, EIP-1153) are **absent** everywhere:
  OpenZeppelin 5.0.2's `ReentrancyGuard` is storage-based (no
  `ReentrancyGuardTransient` exists in 5.0.2).

## 4. How to re-run

```bash
# From the repo root, after `forge build` in packages/contracts:
python3 agenthub-phase9-readiness/audit-package/bytecode/bytecode-audit.py \
  packages/contracts/out
```

Expected output: the four keccak256/SHA-256 hashes above, the sizes
above, MCOPY 1× in QuestManager (PC 1933) and 1× in Achievement
(PC 4432), and `ALL SHA-256 MATCH PHASE 8: True`. The script requires
`cast` on PATH for keccak256 (no Python keccak library is installed on
the preparation VM). The Phase 8 scanner (same method, plus baseline
comparison) is at `agenthub-phase8-remediation/logs/phase8-bytecode-audit.py`.
