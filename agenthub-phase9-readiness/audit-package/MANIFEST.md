# AGENTHUB — Audit Package Manifest

Prepared 20 November 2026 (Phase 9, Workstream 5) for the audit commit
`7dff852d0a303411e060772747fcbafa5c9dd820` (`7dff852`).
Refreshed by the Phase 9 coordinator from the original `e1b316b` pin:
only deploy scripts + tests changed between the two commits (no contract,
frontend, or ABI change), deployment copies re-verified byte-identical
to `7dff852`, and this manifest regenerated.
Package location in the repo:
`agenthub-phase9-readiness/audit-package/` — 28 files, 456 KB
(26 content files + this manifest document + `MANIFEST.sha256`).

## 1. SHA-256 manifest

Verify with: `cd agenthub-phase9-readiness/audit-package && sha256sum -c MANIFEST.sha256`
(the checksum file `MANIFEST.sha256` sits next to this document and
lists every file below except itself and this manifest document).

```
4d61331d2690033aa42c170e51a050b1c6cbac291e636b62617bc3ce449e80be  ARCHITECTURE_OVERVIEW.md
1979304d2679894abf446f3cabb5bc830a010089a49b229d5600ddf8dba5a951  BUILD_REPRODUCTION.md
e1cada40664ad3914622a86198bae44d6319d723be766e6677aa896641f222ab  BYTECODE.md
6ddaf743607dc4aeeeaac5235e4756a134fc43acba7e3903fe23b57bc58c0c86  FINDINGS.md
7d9114a7b2733ebd1d74d30ba73d5b5bcfb3a7a055661cdbcd328719079a4cc5  KNOWN_LIMITATIONS.md
337ce024f25cd83434603a8de62fcc14f645c62ddae83e9750404381ec0dfcdb  README.md
8dfe6ecd8c1dd965293836d0445b5e4f0f88bb21c0d7447c60ecdfe6674d2c3f  TEST_RESULTS.md
c668dd593fec2ee0ed80fa8955e479dd8b7a87d9a00ddc04823faa6d59547c85  THREAT_MODEL.md
ef7720f6c6cecfdc4b2988fdaab5e301e01ae353cfc9c2e254519f3323ce9893  abis/Achievement.ts
6484351200c7c3c203a5f366efc0f59285f260567bac848d998b8caea9a9f1b8  abis/AgentGate.ts
8fb7ca7c31b5a78f9cc9fa6924308fafaae0060677bd72fe1f350f07429067b7  abis/QuestManager.ts
dd551cfd00efe65bb50f78bb23eca8ab0c6e63f5483d60b2175c27ca4c57c53d  abis/Reputation.ts
4c197d2de4b2eeae5458aaddef4c58b93ecf3353d8ca01ad3a46a27f4058e7cf  abis/abi-parity.test.ts
a7e29e89c1ea140a439c0e96c77d951d7c526f66ec5be6e4bd51100a65bd79b6  bytecode/bytecode-audit.log
2d1ce49b8adc0722b4f184f94cbb03457fe0ecae063985558602630f4423dd93  bytecode/bytecode-audit.py
4042268981a4e61ce4fe2c9481895ac5c32320725c63d691e6f51a7628940b95  deployment/DeployAgentHub.s.sol
ae68828b1a3e066fb2dbdf298b99ad0d1a51709521687bd9b4c733b7a2dc2f65  deployment/DeployLocalTestStack.s.sol
c82f0658815e1da11be7cb7ebb3dde231d7b3667703f79d50f932360ca3ff542  deployment/DeployMock.s.sol
cc9a47e6c72f6a2209c2e16988d96faa5987a507d34347adc715de2bc9cdb381  deployment/ProbeSafeProxy.s.sol
9c4b824cf2aaf6363377b00f3699915983e335ac1bd8c59cd43ec4c3168811f6  deployment/SafeValidation.sol
f67ab0af933a41656fdc534730ec75dbe3a6756f8da037260c4a1504a1a625fa  deployment/ValidateSafe.s.sol
a7cc49e6781b5b282732645f1af8618614329b257fe387cb65a4b206b6095a53  deployment/export-abis.mjs
4942995eb8d29057405e3d77c021942dad548e02a8345e710a438f4bc7e25ef1  deployment/foundry.toml
aebc7505b71004c6bac6437a60ba6279e4571a5dbf0f26d7302dbaddb42c9374  reports/PHASE7_INDEPENDENT_SECURITY_REVIEW.md
46238d6115151a8cb0f437cc53ead68268a3f81a0a5611d2da54bcdcd27806c2  reports/PHASE8_SECURITY_REMEDIATION_REPORT.md
4f9a4c72e458aafa3e51d40b637bdfd474deb5e56a6044866e18000d03ed1a1a  reports/solc-evaluation.md
```

## 2. Copy-integrity check

Every file copied into this package from the repo was verified
byte-identical to its source at the audit commit with `cmp`
(20 November 2026):

- `abis/`: all four ABI files + `abi-parity.test.ts` — IDENTICAL to
  `apps/web/lib/abis/`.
- `deployment/`: all seven script files — IDENTICAL to
  `packages/contracts/script/`; `foundry.toml` — IDENTICAL to
  `packages/contracts/foundry.toml`.
- `reports/`: Phase 7 review, Phase 8 remediation report,
  `solc-evaluation.md` — IDENTICAL to their repo originals.
  (The Phase 8 report hash `46238d61…` matches the hash recorded in
  `agenthub-phase8-remediation/VERIFICATION.md`.)

## 3. Secret scan — CONFIRMED CLEAN

**Gitleaks 8.24.3** (repo config `.gitleaks.toml`), run 20 November 2026:

```
gitleaks detect --no-git --config .gitleaks.toml \
  --source agenthub-phase9-readiness/audit-package
→ scanned ~398922 bytes (398.92 KB) — no leaks found (exit 0)
```

**Targeted grep** over the package for secret patterns (`private key`,
`mnemonic`, `seed phrase`, `BEGIN ... PRIVATE KEY`, `sk-…` tokens,
64-hex values, `*_API_KEY=…` assignments, passwords) found only the
following, each triaged **not a secret**:

| Match                                                                                               | Triage                                                                                                                                                                                                                                                                                                                                               |
| --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| keccak256 bytecode hashes (`0x` + 64 hex) in `BYTECODE.md` and `bytecode/bytecode-audit.log`        | Public hashes of public bytecode, not key material.                                                                                                                                                                                                                                                                                                  |
| `DEPLOYER_PRIVATE_KEY` in `deployment/*.sol` and the Phase 7 report                                 | Environment-variable **name** only; no value anywhere. The deployer key is operator-supplied at deploy time and is not in this package.                                                                                                                                                                                                              |
| `DEPLOYER_KEY = 0xac0974…` and `ALICE_KEY = 0x59c6995e…` in `deployment/DeployLocalTestStack.s.sol` | The **public Anvil default test keys** (accounts 0 and 1 of Anvil's well-known default mnemonic). Documented in-file as public test keys holding no real funds, used only against a local Anvil instance; the script is chain-guarded to 31337 (PH7-M06). Phase 7 finding PH7-I16 records the same conclusion ("kunci uji publik, bukan kebocoran"). |
| `0xd7d408eb…` / `0xb89c1b3b…` in `deployment/SafeValidation.sol`                                    | Public Safe proxy **codehashes** (v1.4.1 / v1.3.0), not key material.                                                                                                                                                                                                                                                                                |
| `BSCSCAN_API_KEY` / `ETHERSCAN_API_KEY` in `deployment/foundry.toml`                                | Env-var interpolation (`${BSCSCAN_API_KEY}`) — no key value.                                                                                                                                                                                                                                                                                         |

**No `.env` file, no `.pem`/`.key` file, no private key, no mnemonic,
no API key value is present in this package.** No private key was used
to prepare it (no deploy, no broadcast — per the Phase 9 workstream
constraints).

## 4. Audit-commit binding

This manifest binds the package to the audit commit `7dff852`
(full hash in `README.md` §2). The package was refreshed to `7dff852`
from the original `e1b316b` pin by the Phase 9 coordinator: only deploy
scripts + tests changed between the two commits, the `deployment/`
copies were re-verified byte-identical to `7dff852`, and this manifest
was regenerated. If the audit commit moves again, this manifest,
`BYTECODE.md`, and the copied `abis/`/`deployment/` files must all be
regenerated from the new HEAD.
