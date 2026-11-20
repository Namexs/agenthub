# AGENTHUB — Build Reproduction

> **Source.** Settings below are quoted from
> `packages/contracts/foundry.toml` at the audit commit (a verbatim
> copy is in `deployment/foundry.toml`). The fresh build for this
> package was run 20 November 2026 with forge 1.9.0 and reproduced the
> Phase 8 published bytecode hashes 4/4 (see `BYTECODE.md`).

## 1. Compiler configuration

| Setting            | Value                                                           | Source                                                     |
| ------------------ | --------------------------------------------------------------- | ---------------------------------------------------------- |
| Solidity version   | **0.8.39** (`0.8.39+commit.ce47f2c8`)                           | `foundry.toml`: `solc_version = "0.8.39"`                  |
| Via-IR             | **true** (REQUIRED, not optional)                               | `foundry.toml`: `via_ir = true`                            |
| EVM version        | **cancun**                                                      | `foundry.toml`: `evm_version = "cancun"`                   |
| Optimizer          | enabled, **200 runs**                                           | `foundry.toml`: `optimizer = true`, `optimizer_runs = 200` |
| Forge              | **1.9.0** (commit `6056c58`, build 2026-11-02)                  | `forge --version`; pinned in CI                            |
| OpenZeppelin       | **5.0.2** (pinned git submodule)                                | `lib/openzeppelin-contracts` + `foundry.lock`              |
| forge-std          | pinned git submodule                                            | `lib/forge-std`                                            |
| Remappings         | `@openzeppelin/=lib/openzeppelin-contracts/`, `@agenthub/=src/` | `foundry.toml`                                             |
| Fuzz defaults      | 256 runs, `max_test_rejects = 65536`                            | `foundry.toml` `[fuzz]`                                    |
| Invariant defaults | 256 runs, depth 128, `fail_on_revert = true`                    | `foundry.toml` `[invariant]`                               |

### Why via-IR is mandatory

The 11-parameter `createQuest` (threshold added 2026-11-19) exceeds the
legacy code generator's stack ("Stack too deep … Variable dataEnd is 1
slot(s) too deep") even with an empty function body — the failure is in
the ABI decoder for the 11 params, so no body restructure can fix it
(verified by bisection 2026-11-19: removing the 11th param restores
legacy compilation; via-IR compiles the full new code). Bytecode for
ALL contracts changes with this flag. There is no mainnet deployment
yet, so there is no migration concern.

### Why solc 0.8.39

Upgraded from 0.8.24 in Phase 8 (PH7-L13). 0.8.39 is the latest stable
solc with **zero known bugs** in the official list; it closes
`YulOptimizerKnowledgeBaseStaleBookkeeping` (low, "any code may be
affected") plus 5 other bugs affecting 0.8.24. 0.8.38 was NOT chosen —
it is still exposed to medium bug SOL-2026-8. Full evaluation:
`reports/solc-evaluation.md` (482 lines: build/test/fuzz, compiler-bug
analysis, bytecode comparison). **Caveat:** solc 0.8.39 was 1 day old
(released 19 Nov 2026) at evaluation; exposure to undiscovered compiler
bugs is in principle higher than for a long-circulating release. The
full battery was re-verified on 0.8.39 (see `TEST_RESULTS.md`).

### Why `evm_version = "cancun"` is now a real dependency

solc ≥ 0.8.25 emits **MCOPY** in generated code (1× in QuestManager,
1× in Achievement under 0.8.39 — verified by metadata-aware
disassembly, Phase 8; re-verified for this package, see `BYTECODE.md`).
Cancun is therefore a REAL feature dependency, not just a
reproducibility pin: **do not lower `evm_version` below Cancun.**
Cancun is proven active on BSC testnet and mainnet (Phase 5
validation), and Cancun-opcode support on BSC must still be
smoke-tested on testnet before any mainnet deploy (see
`docs/SECURITY_DEPLOYMENT_GATE.md`).

## 2. Exact reproduction steps

Prerequisites: Foundry (forge 1.9.0), git. No JS toolchain is needed
for the contract build. On a machine where `/tmp` is small, point
`TMPDIR` at a larger directory (the preparation VM's `/tmp` is a
512 MB tmpfs).

```bash
git clone https://github.com/Namexs/agenthub.git
cd agenthub
git checkout e1b316bbb76614a7e2d0daa4a3f897d920f1bae9
git submodule update --init --recursive

cd packages/contracts
forge build --force
```

- Expected: `Compiler run successful` (warnings only — all in
  `lib/`/test files and known forge-lint warnings; see §4).
- Build time on the preparation VM: solc finished in 97.07 s (total
  command ~99 s). Older docs cite ~5 min for the via-IR build; the
  difference is machine/CI dependent — allow several minutes.
- Artifacts land in `packages/contracts/out/<Contract>.sol/<Contract>.json`
  (git-ignored). Each artifact records `metadata.compiler.version`
  (`0.8.39+commit.ce47f2c8`) and the full compilation settings.

Verify the build against this package:

```bash
# From the repo root, with this package at agenthub-phase9-readiness/audit-package:
python3 agenthub-phase9-readiness/audit-package/bytecode/bytecode-audit.py \
  packages/contracts/out
# Expected: ALL SHA-256 MATCH PHASE 8: True, and the keccak256 hashes
# in BYTECODE.md reproduced exactly.
```

## 3. Re-running the test suites

From `packages/contracts/` (after the build above):

```bash
forge test                                   # 321/321 expected
forge test --fuzz-runs 10000 --fuzz-seed 42  # 321/321 expected (CI fuzz command)
forge test --match-test testGas -vv          # gas benchmark (see TEST_RESULTS.md §6)
```

From the repo root (requires the pinned JS toolchain — Node 20+,
pnpm 9.15.4; see `TEST_RESULTS.md` §7 caveat about the stale local
tree on the preparation VM):

```bash
pnpm install
pnpm --filter @agenthub/web test     # vitest web: 173 + 5 skip
pnpm --filter @agenthub/shared test  # vitest shared: 8/8
pnpm typecheck && pnpm lint && pnpm build
```

ABI parity (the committed frontend ABIs vs the fresh build) is checked
by `apps/web/lib/abis/abi-parity.test.ts` (4 deep-equals, run in the
web vitest suite) and by:

```bash
node packages/contracts/script/export-abis.mjs --check   # exit 0 expected
```

## 4. Expected build warnings (not errors)

A fresh `forge build --force` at the audit commit succeeds with
warnings only:

- **forge-std / OpenZeppelin warnings** (dependency code, not
  AGENTHUB): deprecated `pragma experimental ABIEncoderV2` (×9),
  `"error"` becoming a reserved keyword (×~60 in `Vm.sol`/`ECDSA.sol`).
- **AGENTHUB lint warnings** (forge lint, informational): 3
  `reentrancy-events`, 2 `reentrancy-no-eth`, 1
  `unsafe-oz-erc721-mint` (deliberate `_mint` — see
  `ARCHITECTURE_OVERVIEW.md` §3), 2 `missing-events-arithmetic`
  (`_verifierCount`, new in Phase 8), 7 `block-timestamp` (day/minute
  windows, triaged in Phase 7), 3 `require-revert-in-loop`
  (attestation verification loop), 1 `missing-view` (`ValidateSafe`),
  1 `missing-view` (test), 8 `environment-read-across-mutation`
  (test files only, `vm.warp` usage).
- These warnings are also present in the Phase 8 build log
  (`agenthub-phase8-remediation/logs/01-forge-build.log`).

## 5. Determinism notes

- The fresh build for this package reproduced the Phase 8 published
  SHA-256 runtime hashes **exactly, 4/4** (see `BYTECODE.md`). The
  build is therefore reproducible across machines given the same
  toolchain (forge 1.9.0, solc 0.8.39) and the same submodule commits.
- Metadata CBOR (51-byte payload + 2-byte length suffix = 53 bytes
  stripped) embeds the IPFS hash of the compilation metadata; it is
  part of the deployed bytecode and is included in the hashes.
- No library linking: `linkReferences` is empty for all four contracts.
