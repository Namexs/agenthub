# AGENTHUB — Phase 9.1, Workstream 01: Code Changes (L17 / L18 / L19)

- **HEAD baseline:** `81947ce` (Phase 9) → **HEAD akhir kode:** `bcba559`
- **Commit:** `cb73818` (L17), `8d2f9dc` (L18), `b63b19a` (L19),
  `0313922` (fix typo ANVIL_KEY), `bcba559` (forge fmt)
- **Test:** 323 → **343** (+20), fuzz 10k 343/343, 0 test dihapus,
  0 assertion dilemahkan. `packages/contracts/src/`: 0 file berubah.

## L17 — CANCELLER_ROLE di `_verifyWiring` (`cb73818`)

- `script/DeployAgentHub.s.sol`: `_verifyWiring` kini menegaskan
  `timelock.hasRole(CANCELLER_ROLE, adminMultisig)` (revert
  `timelock.canceller`) dan deployer TIDAK memegangnya (revert
  `deployer.canceller`).
- Hitungan cek: 30 → 32 (testnet/local), 31 mainnet. `docs/DEPLOYMENT.md`
  diperbarui.
- Test: harness `DeployAgentHubHarness` + 3 test baru di
  `test/DeployScript.t.sol` (positif + 2 negatif).

## L18 — Artefak deployment JSON otomatis (`8d2f9dc`)

- `DeployAgentHub.run()` menulis `deployments/<chainId>.json` (16 field:
  chainId, blockNumber, timestamp, deployer, 6 alamat, 6 tx hash).
  Opt-out: `WRITE_DEPLOYMENT_ARTIFACT=false`. Tidak pernah menulis secret.
- `script/RecordDeployment.s.sol` (baru): mengisi 6 tx hash dari broadcast
  JSON + koreksi blockNumber; idempotent; dry-run → warning.
  Parser untuk format broadcast forge 1.9 (receipt di array `receipts`).
- `foundry.toml`: `fs_permissions` → `./deployments` (rw) + `./broadcast`
  (ro). `.gitignore`: `deployments/31337*.json`, `*.fixture.json`.
- Test: `test/DeploymentArtifact.t.sol` (baru), 5 test (format,
  pengisian hash, preservasi no-match, revert file hilang).
- E2E anvil: 6/6 hash cocok byte-per-byte dengan receipts; blockNumber
  terkoreksi 2 → 6.

## L19 — ProposeGrantVerifier (`b63b19a`)

- `script/ProposeGrantVerifier.s.sol` (baru): `buildProposal()` (view +
  validasi) + `scheduleGrant()` (via timelock, delay 2 hari). Tanpa jalur
  direct-grant. `run()` preview-only default; `SCHEDULE=true` hanya
  EOA-proposer / simulasi fork.
- `script/ProposeGrantVerifier.md` (baru): runbook propose → schedule →
  delay → execute.
- Test: `test/ProposeGrantVerifier.t.sol` (baru), 12 test (termasuk
  execute prematur revert, cancel menggagalkan grant, non-proposer
  ditolak).
- E2E anvil: preview mencetak operation id / salt / calldata / delay
  172800 / readyAt dengan benar; tidak ada yang terjadwal.

## Perbaikan insidental

- `0313922`: typo `ANVIL_KEY` di `DeployScriptTest` (`...f4f3ff80` →
  `...f4f2ff80`; yang salah men-derive 0x7f22…, bukan anvil account 0).
  Ditemukan saat E2E.
- `bcba559`: `forge fmt` 4 file baru (lint gate; diff murni formatting,
  diverifikasi koordinator).

## Catatan implementasi (untuk maintainer)

- Format broadcast forge 1.9: receipt TIDAK ada di objek per-tx
  (`receipt: null`), melainkan di array top-level `receipts`.
- Quirk `console.log` forge 1.9 di `forge script`: overload multi-arg
  `(string, uint)` dan format `%s/%d` diam-diam tidak tampil; gunakan
  single-string via `string.concat`.
- Getter role OZ (`CANCELLER_ROLE()`) adalah _call_ yang menghabiskan
  `vm.prank`/`vm.expectRevert` — hoist sebelum prank.
- Test paralel forge: file artefak memakai path per-test untuk
  menghindari race.
