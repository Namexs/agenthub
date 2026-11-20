# AGENTHUB — Phase 9, Workstream 2: Review Deployment

**Tanggal:** 20 November 2026.
**Baseline:** HEAD `e1b316b` (Phase 8 final, Solidity 0.8.39, `via_ir=true`).
**Ruang lingkup:** deployment stack — `packages/contracts/script/DeployAgentHub.s.sol`,
`script/SafeValidation.sol`, `script/DeployLocalTestStack.s.sol`,
`script/DeployMock.s.sol`, `script/ValidateSafe.s.sol`,
`script/ProbeSafeProxy.s.sol`, role assignment pasca-deploy, ownership
MockAgentId, konfigurasi timelock, guard `CONFIRM_TESTNET_DEPLOY`, dan
seluruh environment variable (`.env.example` + semua `vm.env*`).
**Acuan:** `agenthub-phase8-remediation/PHASE8_SECURITY_REMEDIATION_REPORT.md`
(§2 M03/M04/M05/M06, §3 L17–L23),
`agenthub-phase7-review/PHASE7_INDEPENDENT_SECURITY_REVIEW.md`
(PH7-L17–L23), `packages/contracts/test/DeployScript.t.sol`,
`packages/contracts/test/PauserRole.t.sol`, `docs/DEPLOYMENT_PLAN.md`,
`docs/ROLE_MATRIX.md`,
`agenthub-final-pretestnet/FINAL_DEPLOYMENT_CHECKLIST.md`.
**Metode:** baca kode langsung + jalankan test + jalankan `forge script`
CLI terhadap anvil lokal (chain 97/1) dan fork BSC testnet live
(publicnode). Tidak ada broadcast ke chain nyata, tidak ada private key
nyata (hanya kunci test Anvil default). Semua perintah dicatat di §11.

---

## 1. Keputusan: CONDITIONAL GO testnet — 2 cacat ditemukan dan diperbaiki

**Dua cacat ditemukan audit ini, keduanya sudah diperbaiki + ditest +
di-commit (tanpa push):**

| ID      | Cacat                                                                                                                                                                                                                                                                                       | Status                                                                               |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| PH9-D01 | **Tidak ada penegakan "dua Safe harus berbeda"** — `adminMultisig == questCreator` lolos semua validasi dan deploy sukses, meruntuhkan separation of duties M03. Dokumen mewajibkan distinct (`FINAL_DEPLOYMENT_CHECKLIST.md:26`, `DEPLOYMENT_PLAN.md:80`) tetapi kode tidak menegakkannya. | **DIPERBAIKI** — error `AdminAndCreatorMustDiffer` + cek di `deploy()` + 2 test baru |
| PH9-D02 | **`DeployMock` tanpa guard konfirmasi** — jalur broadcast ke chain 97 yang sama sekali tidak memeriksa `CONFIRM_TESTNET_DEPLOY` (simulasi pra-perbaikan: `SIMULATION COMPLETE` tanpa env apa pun).                                                                                          | **DIPERBAIKI** — guard simetris PH7-M05 + 3 skenario test baru                       |

**Satu risiko residual didokumentasikan, bukan diperbaiki** (PH9-D03):
guard konfirmasi hidup di `run()`, bukan di `deploy()` — `deploy()`
bersifat publik dan tanpa guard, jadi script wrapper baru yang memanggil
`deploy()` + `startBroadcast` akan melewati guard. Ini memerlukan kode
baru yang disengaja (bukan kecelakaan operator): dibuktikan probe —
`forge script --broadcast` atas fungsi tanpa `startBroadcast`
menghasilkan `Warning: No transactions to broadcast` dan nonce tidak
berubah. Mitigasi: `run()` adalah satu-satunya entry point
terdokumentasi; rekomendasi SOP di §7.3.

**Verdict per poin (pasca-perbaikan):**

| Poin                                                               | Verdict                                                                  |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| 1. Quest creator memakai Safe tervalidasi (sama kuat dengan admin) | **LOLOS**                                                                |
| 2. Admin memakai Safe tervalidasi                                  | **LOLOS**                                                                |
| 3. Kedua Safe BERBEDA                                              | **LOLOS (pasca-perbaikan)** — GAGAL pada baseline                        |
| 4. Deployer tanpa privilege pasca-deploy                           | **LOLOS** (dengan rekomendasi hardening `_verifyWiring`, §4.3)           |
| 5. Tidak ada private key hardcoded                                 | **LOLOS**                                                                |
| 6. Tidak ada jalur deployment melewati guard                       | **LOLOS (pasca-perbaikan)** — PERLU PERBAIKAN pada baseline (DeployMock) |

**Battery regresi:** `forge test` penuh **323/323 (22 suite), 0 gagal,
0 skip** (baseline 321 + 2 test baru; 3 skenario DeployMock berada di
dalam test gabungan yang sudah ada). Tidak ada test dihapus, tidak ada
assertion dilemahkan.

---

## 2. Poin 1 — Quest creator memakai Safe tervalidasi: LOLOS

**Bukti kode.** `DeployAgentHub.s.sol:224,226` memvalidasi
`params.questCreator` dengan helper yang **persis sama** dengan
`adminMultisig` (`:211,216`), dengan nilai ekspektasi yang sama, sebelum
`CREATE` apa pun:

- Jalur kanonis (56/97): `SafeValidation.validate(params.questCreator)`
  — sama dengan admin (`:216`).
- Jalur eksplisit (31337): `SafeValidation.validate(params.questCreator,
params.safeSingleton, params.safeProxyCodehash)` — singleton +
  codehash yang sama dengan admin (`:211`).

**Bukti helper.** `SafeValidation.sol` fail-closed, 6 lapis
(`_validateCommon` `:147–153`, `validate` `:110–124`):

1. `candidate.code.length == 0` → `NotASafe("no code")` (EOA ditolak
   sebelum staticcall — EOA menjawab staticcall dengan sukses kosong).
2. `threshold >= MIN_SAFE_THRESHOLD (2)` **dan** `threshold <=
owners.length` **dan** `owners.length >= 2` (`:150`) — 1-of-n dan
   Safe yang tak pernah mencapai kuorum ditolak.
3. `masterCopy()` harus singleton kanonis v1.4.1
   `0x41675C099F32341bf84BFc5382aF534df5C7461a` atau v1.3.0
   `0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552` (`:115`).
4. `codehash` runtime harus codehash proksi kanonis (`:119`) — ini yang
   menutup spoofing `masterCopy()`: kontrak palsu tidak bisa memalsukan
   codehash tanpa MENJADI proksi kanonis.
5. `VERSION()` via delegatecall harus `"1.3.0"`/`"1.4.1"`.
6. Semua pemanggilan memakai staticcall level-rendah + cek panjang
   returndata (pola fail-closed AgentGate SEC-001).

**Bukti test** (`DeployScript.t.sol`, semua lulus pada run §11):

| Test                                                      | Hasil                                    |
| --------------------------------------------------------- | ---------------------------------------- |
| `test_DeployRejectsEoaCreator`                            | revert `NotASafe(eoa, "no code")`        |
| `test_DeployRejectsNonSafeCreatorContract`                | revert `NotASafe("getThreshold failed")` |
| `test_DeployRejectsThresholdOneCreatorSafe`               | revert `UnsafeThreshold(1, 3)`           |
| `test_DeployAcceptsDistinctCreatorSafe`                   | sukses, 3-of-3, role tepat               |
| `test_TestnetRejectsEoaCreator` (chain 97, jalur kanonis) | revert `NotASafe("no code")`             |

**Bukti CLI.** Fork BSC testnet live + anvil chain 97 dengan
`QUEST_CREATOR` EOA + `CONFIRM_TESTNET_DEPLOY=true`:
`NotASafe(0x1111…1111, "no code")` — validasi menyala sebelum deploy
(matriks §7, kasus D).

**Catatan batas:** seperti didokumentasikan di `SafeValidation.sol`,
cek ini membuktikan "ini Safe asli", BUKAN "ini Safe TIM" (identitas
owner adalah konfirmasi out-of-band — sudah tercakup checklist §3).
Bukan temuan baru.

---

## 3. Poin 2 — Admin memakai Safe tervalidasi: LOLOS

Validasi admin adalah jalur yang sama persis dengan poin 1
(`DeployAgentHub.s.sol:211,216`), dengan test negatif yang lebih
lengkap:

| Test                                               | Hasil                                                                               |
| -------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `test_DeployRejectsEoaMultisig`                    | revert `NotASafe("no code")`                                                        |
| `test_DeployRejectsNonSafeContract`                | revert `NotASafe("getThreshold failed")`                                            |
| `test_DeployRejectsThresholdOneSafe`               | revert `UnsafeThreshold(1, 3)`                                                      |
| `test_DeployRejectsThresholdAboveOwners`           | revert `UnsafeThreshold(3, 2)`                                                      |
| `test_DeployAcceptsThresholdThreeOfThree`          | sukses 3-of-3                                                                       |
| `test_DeployRejectsExplicitSafeValuesOnProduction` | revert `ExplicitSingletonNotAllowedOnProduction` (escape hatch lokal ditolak di 97) |
| `test_DeployRejectsMissingLocalSafeConfig`         | revert `LocalSafeConfigMissing` (31337 wajib nilai eksplisit)                       |

Jalur eksplisit lokal (`SafeValidation.validate/3`) menolak berjalan di
chain selain 31337 (`SafeValidation.sol`, `UnsupportedChain`), sehingga
produksi tidak pernah bisa memakai nilai operator-supplied. Jalur
kanonis menolak berjalan di chain selain 56/97. Kedua arah tertutup.

---

## 4. Poin 3 — Kedua Safe BERBEDA: LOLOS pasca-perbaikan (GAGAL pada baseline)

### 4.1 Bukti kegagalan baseline (PH9-D01)

Grep seluruh `script/` + `test/` + `src/` untuk pembanding
`adminMultisig` vs `questCreator`: **tidak ada satu pun**. Dokumen
mewajibkan distinct tetapi kode tidak menegakkan:

- `FINAL_DEPLOYMENT_CHECKLIST.md:26` (item 4): creator Safe
  "…threshold ≥ 2 (2-of-3 recommended), **DISTINCT from the admin
  multisig**."
- `docs/DEPLOYMENT_PLAN.md:80`: "**Use a Safe distinct from the admin
  multisig.**"
- Laporan Phase 8 §2 M03 mengklaim penutupan dengan "(creator Safe
  threshold ≥ 2, distinct dari admin)" — distinctness hanya ada di
  checklist, bukan di kode.

**Bukti eksekusi pra-perbaikan.** Probe sementara
(`test/Phase9GapProbe.t.sol`, dihapus setelah audit) yang mendeploy
dengan `adminMultisig == questCreator` (Safe 2-of-3 yang sama):

```
[PASS] test_GAP_SameSafeForAdminAndCreatorDeploys() (gas: 20111394)
```

Deploy sukses dan Safe yang sama memegang `QUEST_CREATOR_ROLE` —
separation of duties M03 runtuh diam-diam oleh satu copy-paste env var
yang sama ke `ADMIN_MULTISIG` dan `QUEST_CREATOR`. Satu set owner Safe
yang kompromi akan menguasai admin (timelock proposer/executor + badge
manager) DAN pembuatan quest sekaligus.

### 4.2 Perbaikan (di-commit, tanpa push)

`DeployAgentHub.s.sol` — error baru `:85` + cek di `deploy()` `:192`,
tepat setelah cek zero-address dan SEBELUM validasi Safe maupun `CREATE`
apa pun (fail-fast dengan alasan paling spesifik):

```solidity
error AdminAndCreatorMustDiffer();
...
if (params.adminMultisig == params.questCreator) revert AdminAndCreatorMustDiffer();
```

Cek ini chain-agnostic (berlaku di 56/97/31337) dan mencakup `run()`
karena `run()` memanggil `deploy()`. NatSpec kontrak diperbarui
(`:44–48`).

**Test baru** (`DeployScript.t.sol`):

| Test                                                                | Hasil pasca-perbaikan              |
| ------------------------------------------------------------------- | ---------------------------------- |
| `test_DeployRejectsSameSafeForAdminAndCreator` (31337)              | revert `AdminAndCreatorMustDiffer` |
| `test_TestnetRejectsSameSafeForAdminAndCreator` (97, jalur kanonis) | revert `AdminAndCreatorMustDiffer` |

**Mengapa perbaikan ini aman:** hanya menolak konfigurasi yang dokumen
sudah melarang; tidak mengubah jalur sukses mana pun (semua test lama
memakai dua Safe berbeda dan tetap lulus); tidak menyentuh kontrak
produksi (hanya script deploy).

---

## 5. Poin 4 — Deployer tanpa privilege pasca-deploy: LOLOS

### 5.1 Inventaris lengkap peran/kepemilikan pasca-deploy

Dibuktikan dari kode deploy (`DeployAgentHub.s.sol:250–296`) +
konstruktor OZ `TimelockController` (`lib/openzeppelin-contracts/
contracts/governance/TimelockController.sol:117,120–127`) +
`MockAgentId.sol` (`Ownable(msg.sender)`, `mint` onlyOwner).
`AgentGate` tidak punya role/owner sama sekali (hanya immutable
`agentIdContract` + `expectedChainId` — grep `Ownable|AccessControl`
di `src/AgentGate.sol`: nihil).

| Kontrak      | Peran / kepemilikan             | Pemegang                                                                                                 | Deployer?            |
| ------------ | ------------------------------- | -------------------------------------------------------------------------------------------------------- | -------------------- |
| Reputation   | `DEFAULT_ADMIN_ROLE`            | Timelock                                                                                                 | ❌ (renounce `:283`) |
| Reputation   | `SCORE_SOURCE_ROLE`             | QuestManager                                                                                             | ❌                   |
| Achievement  | `DEFAULT_ADMIN_ROLE`            | Timelock                                                                                                 | ❌ (renounce `:284`) |
| Achievement  | `ISSUER_ROLE`                   | QuestManager                                                                                             | ❌                   |
| Achievement  | `BADGE_MANAGER_ROLE`            | Admin multisig                                                                                           | ❌                   |
| QuestManager | `DEFAULT_ADMIN_ROLE`            | Timelock                                                                                                 | ❌ (renounce `:285`) |
| QuestManager | `QUEST_CREATOR_ROLE`            | Creator Safe                                                                                             | ❌                   |
| QuestManager | `PAUSER_ROLE`                   | Pauser eksplisit / admin multisig (default)                                                              | ❌                   |
| QuestManager | `VERIFIER_ROLE`                 | Verifier pertama (bila di-set)                                                                           | ❌                   |
| Timelock     | `DEFAULT_ADMIN_ROLE`            | Timelock itu sendiri (OZ `:117`; admin opsional `address(0)` → tidak ada admin eksternal, OZ `:120–122`) | ❌                   |
| Timelock     | `PROPOSER_ROLE`                 | Admin multisig                                                                                           | ❌                   |
| Timelock     | `CANCELLER_ROLE`                | Admin multisig (OZ memberi ke setiap proposer, `:126–127`)                                               | ❌                   |
| Timelock     | `EXECUTOR_ROLE`                 | Admin multisig                                                                                           | ❌                   |
| MockAgentId  | `owner()` (Ownable, kuasa mint) | Admin multisig (transfer `:295`, PH7-M04)                                                                | ❌                   |
| AgentGate    | — (tanpa role/owner)            | —                                                                                                        | ❌                   |

**Konfigurasi timelock:** `TIMELOCK_DELAY = 2 days`
(`DeployAgentHub.s.sol:67`); proposers = `[adminMultisig]`, executors =
`[adminMultisig]`, admin = `address(0)` (`:256`) — self-administered,
perubahan konfigurasi timelock hanya lewat proposal. Delay diverifikasi
on-chain oleh `_verifyWiring` (`:332`, `timelock.delay`).

### 5.2 Bukti test

- `DeployScript.t.sol::test_LocalDeployWiresEverything` — 12 assert
  negatif deployer (admin ×3, scoreSource, issuer, badgeManager,
  creator, pauser, verifier, timelock admin/proposer/executor) +
  `mock.owner() == multisig`.
- `PauserRole.t.sol::test_DeployerHasNoOperationalRoleAfterHandover` —
  13 assert negatif, termasuk `CANCELLER_ROLE` (`:96`), +
  `mockId.owner() == multisig`.
- `test_RunEnvDrivenPaths` skenario (1) + (6) — jalur `run()` env-driven
  (broadcast nyata di test EVM): deployer Anvil account 0 tidak
  menyimpan admin/verifier; mock dimiliki multisig.
- `_verifyWiring` sendiri (`DeployAgentHub.s.sol:379–407`) memeriksa 10
  kondisi negatif deployer saat deploy dan revert bila satu pun gagal
  (jaring pengaman deploy-time, bukan hanya test-time).

### 5.3 Rekomendasi hardening (tidak menghalangi testnet)

`_verifyWiring` belum memeriksa 4 kondisi yang sudah dicakup test:
(1) `CANCELLER_ROLE` positif ke multisig (= PH7-L17, §9);
(2–4) negatif deployer untuk `PROPOSER_ROLE`, `EXECUTOR_ROLE`,
`CANCELLER_ROLE` timelock. State on-chain benar (dibuktikan test di
§5.2); yang hilang hanya jaring deploy-time. Rekomendasi: tambahkan
keempat assert sebelum smoke test (patch persis di §9, L17) — satu
menit kerja, risiko nol, dan menutup celah "test menangkapnya, deploy
tidak".

---

## 6. Poin 5 — Tidak ada private key hardcoded: LOLOS

**Gitleaks — riwayat git penuh:** `~/workspace/bin/gitleaks detect
--log-opts="--all"` → **107 commit dipindai, 0 leak.** Konfigurasi
`.gitleaks.toml` memakai `[extend] useDefault = true` (rule default
aktif — bukan false clean) dengan allowlist HANYA nilai eksak kunci
publik Anvil + 1 false positive alamat token + 1 cache-key CI.
CI menjalankan gitleaks-action v2 (`ci.yml:234–242`).

**Gitleaks — working tree** (`--no-git`): 4 temuan, semuanya false
positive `generic-api-key` di direktori build yang di-gitignore
(`apps/web/.next/*`, `packages/contracts/out/*`) — hash build dan nama
kontrak (`IERC20Balance`), bukan kredensial. Tidak ada satu pun di file
yang di-track.

**Grep pola kunci (file ter-track):**

- `0x[0-9a-fA-F]{64}` di `*.sol`: hanya kunci publik Anvil
  (`DeployLocalTestStack.s.sol:40,44` — account 0/1, tercetak di setiap
  banner anvil dan di Foundry book; di-allowlist gitleaks),
  codehash proksi Safe (`SafeValidation.sol:83,88` — konstanta publik),
  konstanta `SECP256K1_N`, codehash nol, dan filler test `0x1111…`.
- `private[_ ]?key\s*=\s*0x…` (dengan nilai): **nihil**.
- `DEPLOYER_PRIVATE_KEY=` dengan nilai: hanya placeholder `<key>` di
  `docs/DEPLOYMENT.md:43`, `docs/DEPLOYMENT_PLAN.md:60`.
- File `.env` yang ter-track: hanya `.env.example`. Tidak ada `.env` /
  `.env.local` di disk `packages/contracts/`.
- `broadcast/` + `out/` + `.env` di-gitignore (`.gitignore:15,20–22`).

**Catatan:** `DeployLocalTestStack.s.sol:40,44` menyimpan kunci Anvil
0/1 sebagai konstanta — by design dan terdokumentasi di komentar
("PUBLIC anvil test key 0 — it holds no real funds anywhere"). Script
itu di-chain-guard ke 31337 (PH7-M06, §7 kasus F), sehingga kunci
publik itu tidak pernah bisa dipakai di chain nyata lewat jalur ini.
Bukan temuan.

---

## 7. Poin 6 — Tidak ada jalur deployment melewati guard: LOLOS pasca-perbaikan

### 7.1 Matriks jalur (CLI `forge script`, dijalankan langsung)

| #   | Jalur                                                                            | Kondisi                                                             | Hasil                                                                                                                                                            | Alasan                                                                          |
| --- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| A   | `DeployAgentHub.run()` dry-run, anvil chain 97                                   | Tanpa env sama sekali                                               | **REVERT** `TestnetDeployNotConfirmed()`                                                                                                                         | Guard `:147` sebelum baca env lain                                              |
| B   | `DeployAgentHub.run()` dry-run, anvil chain 97                                   | `CONFIRM_TESTNET_DEPLOY=false`                                      | **REVERT** `TestnetDeployNotConfirmed()`                                                                                                                         | `vm.envOr(..., false)`                                                          |
| C   | `DeployAgentHub.run()` dry-run, anvil chain 97                                   | `CONFIRM=true`, `ADMIN_MULTISIG` hilang                             | **REVERT** `vm.envAddress: environment variable "ADMIN_MULTISIG" not found`                                                                                      | Fail-closed sebelum deploy                                                      |
| C2  | `DeployAgentHub.run()`, fork 97 live                                             | `CONFIRM=true`, admin+creator terisi, `DEPLOYER_PRIVATE_KEY` hilang | **REVERT** `vm.envUint: environment variable "DEPLOYER_PRIVATE_KEY" not found`                                                                                   | Fail-closed sebelum broadcast                                                   |
| D   | `DeployAgentHub.run()` dry-run, anvil chain 97                                   | `CONFIRM=true`, admin+creator EOA, kunci Anvil                      | **REVERT** `NotASafe(0x1111…1111, "no code")`                                                                                                                    | Validasi Safe sebelum `CREATE`                                                  |
| E   | `DeployAgentHub.run()` dry-run, anvil chain 1                                    | Tanpa env                                                           | **REVERT** `UnsupportedChain(1)`                                                                                                                                 | Allowlist chain `:136`                                                          |
| F   | `DeployLocalTestStack.run()`, anvil chain 97                                     | —                                                                   | **REVERT** `DeployLocalTestStack: local Anvil only`                                                                                                              | Guard PH7-M06                                                                   |
| G   | `DeployMock.run()` dry-run, anvil chain 97                                       | Tanpa `CONFIRM_*`, kunci Anvil                                      | **PRA-PERBAIKAN: SIMULATION COMPLETE** (lolos guard — PH9-D02). **PASCA-PERBAIKAN: REVERT** `TestnetDeployNotConfirmed()`; dengan `CONFIRM=true` simulasi sukses | Guard baru `DeployMock.s.sol:28`                                                |
| H   | `DeployAgentHub.run()`, **fork BSC testnet live** (publicnode, blok 143.737.179) | Tanpa env                                                           | **REVERT** `TestnetDeployNotConfirmed()`                                                                                                                         | Guard bekerja di fork live, bukan hanya anvil lokal                             |
| I   | Probe sementara tanpa `startBroadcast` + `--broadcast`, anvil chain 97           | —                                                                   | `Warning: No transactions to broadcast`, nonce deployer 0 → 0                                                                                                    | Forge tidak mengirim apa pun tanpa blok broadcast (probe dihapus setelah audit) |

Unit test yang menguatkan: `test_RunEnvDrivenPaths` skenario (3)–(6)
(mainnet tanpa/dengan konfirmasi, testnet tanpa/dengan konfirmasi),
`test_DeployRejectsUnsupportedChain`,
`test_LocalTestStackRejectsTestnetChain/MainnetChain`,
`test_DeployRejectsMissingLocalSafeConfig`.

### 7.2 Inventaris jalur deployment (lengkap)

| Script                       | Broadcast?                                                                                  | Guard chain                                                                                                   | Guard konfirmasi                                                     |
| ---------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `DeployAgentHub.run()`       | Ya (`startBroadcast`)                                                                       | Allowlist 56/97/31337                                                                                         | 56: `CONFIRM_MAINNET_DEPLOY`; 97: `CONFIRM_TESTNET_DEPLOY`           |
| `DeployAgentHub.deploy()`    | **Tidak** (tanpa broadcast di dalam; probe I membuktikan `--broadcast` saja tidak mengirim) | Allowlist 56/97/31337                                                                                         | **Tidak ada** — lihat PH9-D03 §7.3                                   |
| `DeployMock.run()`           | Ya                                                                                          | Allowlist 97/31337                                                                                            | 97: `CONFIRM_TESTNET_DEPLOY` (**baru, PH9-D02**); 31337 dikecualikan |
| `DeployLocalTestStack.run()` | Ya (kunci publik Anvil)                                                                     | `require(chainid == 31337)`                                                                                   | Tidak perlu (lokal saja)                                             |
| `ValidateSafe.run()`         | Tidak (read-only)                                                                           | Via `SafeValidation` (56/97 kanonis, 31337 eksplisit)                                                         | Tidak perlu                                                          |
| `ProbeSafeProxy.run()`       | Tidak (tanpa `startBroadcast`; eksperimen fork one-off)                                     | Tidak ada guard chain eksplisit — tetapi tanpa blok broadcast, `--broadcast` tidak mengirim apa pun (probe I) | Tidak perlu                                                          |

### 7.3 Risiko residual PH9-D03: guard hidup di `run()`, bukan `deploy()`

`deploy()` bersifat `public`, tanpa guard konfirmasi, dan sudah
dibuktikan test (`test_TestnetAcceptsMock` berjalan di chain 97 tanpa
env apa pun). Siapa pun yang menulis script wrapper baru yang memanggil
`deploy()` + `startBroadcast` akan melewati guard. Ini **bukan jalur
kecelakaan**: memerlukan kode baru yang disengaja, dan `deploy()`
sendiri tidak pernah broadcast (probe I). Alternatif — memindahkan
guard ke `deploy()` — ditolak: `deploy()` dirancang bebas-env agar
dapat di-unit-test, dan guard adalah cek niat operator yang inheren
berbasis env. **Rekomendasi:** tambahkan satu baris ke SOP/checklist —
"deploy HANYA lewat `run()`; script apa pun yang memanggil `deploy()`
langsung wajib mereplikasi guard `CONFIRM_*`". Tidak ada perubahan
kode.

---

## 8. Temuan baru lain

Tidak ada temuan High/Medium baru selain PH9-D01 dan PH9-D02 di atas.
Observasi:

- **L20 terselesaikan di luar audit ini (lihat §9).** Artefak broadcast
  fork chain 97 hilang dari disk selama jendela audit (direktori
  `broadcast/DeployAgentHub.s.sol/` lenyap seluruhnya; mtime direktori
  `broadcast/` 2026-11-20 07:51 WIB). Perintah audit ini tidak
  menghapusnya (semua `rm` saya menargetkan path eksplisit lain:
  `ProbeNoBroadcast`, `DeployMock`, `cache/*`). Aktivitas konkuren
  workstream Phase 9 lain berlangsung di repo yang sama pada saat itu
  (anvil fork workstream 03 di port 8545, `fork-dryrun/`). Hasil akhir
  sudah benar (artefak basi tidak ada lagi); koordinator dapat
  mengonfirmasi siapa yang membersihkannya. Inventaris pra-pembersihan
  tercatat di log audit awal: `97/run-1795091254300.json`,
  `97/run-1795096631567.json`, `97/run-latest.json`,
  `97/run-latest.recovery.lock`, `97/dry-run/` — semuanya artefak fork
  (Phase 7 sudah memverifikasi receipt null di testnet live).
- **Anvil fork workstream 03 (port 8545) tidak lagi berjalan** pada
  akhir audit ini. Bukan disebabkan perintah saya: pola `pkill` saya
  hanya mencocokkan cmdline anvil milik sendiri (`--chain-id 97 --port
854[78]`); cmdline anvil tersebut (`--fork-url … --port 8545`) tidak
  cocok dengan pola mana pun. Kemungkinan dihentikan pemiliknya
  setelah fork-dryrun selesai.

---

## 9. Klasifikasi temuan terbuka PH7-L17–L23 (bonus)

| ID      | Temuan                                                      | Klasifikasi                             | Alasan + rekomendasi konkret                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------- | ----------------------------------------------------------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **L17** | `_verifyWiring` tidak memeriksa `CANCELLER_ROLE`            | **TUTUP SEBELUM SMOKE**                 | Satu baris, risiko nol, state on-chain sudah benar — yang hilang hanya jaring deploy-time. Patch: setelah cek `timelock.executor` (`DeployAgentHub.s.sol:337`), tambah `if (!timelock.hasRole(timelock.CANCELLER_ROLE(), params.adminMultisig)) revert WiringCheckFailed("timelock.canceller");` + perbarui hitungan "30 checks" → 31 di komentar `:321`. Sekalian tambah 3 assert negatif deployer (proposer/executor/canceller, §5.3). Tidak diimplementasikan audit ini karena di luar klausul perbaikan (bukan blocker) — diserahkan ke koordinator.                                                                               |
| **L18** | Deploy script tidak menulis artefak JSON                    | **TUTUP SEBELUM SMOKE**                 | Smoke test butuh 6 alamat + blok deploy yang akurat; pencatatan manual 6 alamat + nomor blok adalah sumber kesalahan yang sudah terbukti berbahaya di proyek ini (kesalahan hitung wiring L16). Pola `_writeJson` sudah ada di `DeployLocalTestStack.s.sol`. Perlu perluas `fs_permissions` di `foundry.toml` (saat ini hanya `./.anvil-deployment.json`) ke mis. `./.deployment-97.json` + kerangka `docs/DEPLOYMENT_RECORD.md`. Usaha kecil, nilai operasional tinggi.                                                                                                                                                               |
| **L19** | Tanpa helper proposal timelock pasca-deploy                 | **TUTUP SEBELUM SMOKE**                 | Smoke test butuh grant verifier ke-2 via timelock (R-010: threshold-2 end-to-end); merakit calldata manual via `cast`/Safe UI termasuk hash role yang benar adalah titik kesalahan manual tepat di jalur kritis smoke. Minimal: dokumentasikan perintah `cast` persis di checklist §5 (murah); ideal: script `ProposeGrantRole.s.sol` dry-run + ringkasan human-readable.                                                                                                                                                                                                                                                              |
| **L20** | Artefak broadcast fork chain 97 yang basi                   | **SUDAH TERTUTUP** (di luar audit ini)  | Terverifikasi tidak ada lagi di disk 2026-11-20 (§8). Tidak ada tindakan.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **L21** | `AGENT_ID_ADDRESS` di-supply di chain 97 tidak divalidasi   | **BISA DITUNDA** (dengan penguatan dok) | Jalur default (variabel kosong → mock baru) aman dan itulah jalur smoke test. Risiko hanya bila operator mengisi variabel dengan kontrak jahat — ancaman yang mensyaratkan operator memasukkan alamat penyerang sendiri. Validasi kodehash ketat (`type(MockAgentId).runtimeCode`) berisiko false positive bila mock di-deploy dari checkout/solc berbeda; cek `supportsInterface(ERC721)` hanya teater lawan kontrak jahat. Rekomendasi: perkuat `.env.example` + checklist — "HARUS kosong di testnet kecuali mock yang di-deploy dari repo ini via `DeployMock`" — dan tambahkan langkah verifikasi alamat di checklist bila diisi. |
| **L22** | Verifikasi BscScan manual kekurangan tabel constructor args | **TUTUP SEBELUM SMOKE**                 | Verifikasi sumber adalah bagian dari definisi "deployment testnet selesai" (checklist §4); tanpa tabel, operator verifikasi manual menebak args per kontrak — dan via-IR + solc 0.8.39 + optimizer 200 + cancun harus identik atau gagal "bytecode mismatch". Dokumen saja (tanpa kode): tabel constructor args per kontrak + perintah `forge verify-contract` lengkap + peringatan "verifikasi dari checkout yang sama".                                                                                                                                                                                                              |
| **L23** | 3 prasyarat operasional tersembunyi                         | **TUTUP SEBELUM SMOKE**                 | Murah (dokumen) dan tepat sasaran: ketiganya (URL RPC teruji, Safe testnet sudah dibuat + didanai, dompet uji didanai) adalah blocker deployment-day bila tidak siap. Catatan: RPC publicnode + binance.org keduanya merespons saat audit ini (blok 143.737.179/181), tetapi default dokumentasi pernah 403 dari VM build — prasyarat "RPC teruji" tetap valid. Tambahkan §1.x ke checklist.                                                                                                                                                                                                                                           |

**Ringkasan klasifikasi:** tutup sebelum smoke — L17, L18, L19, L22,
L23 (semuanya murah: 1 baris kode + dokumen + 1 script opsional);
sudah tertutup — L20; bisa ditunda — L21 (jalur default aman).

---

## 10. File yang berubah (di-commit ke `main`, tanpa push)

| File                                                            | Perubahan                                                                                                                                            |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/contracts/script/DeployAgentHub.s.sol`                | +16: error `AdminAndCreatorMustDiffer` (`:85`), cek distinctness di `deploy()` (`:192`), NatSpec (`:44–48`)                                          |
| `packages/contracts/script/DeployMock.s.sol`                    | +15/−1: error `TestnetDeployNotConfirmed`, guard `CONFIRM_TESTNET_DEPLOY` di chain 97 (`:28`), NatSpec usage                                         |
| `packages/contracts/test/DeployScript.t.sol`                    | +68/−6: 2 test distinctness baru (31337 + 97), 3 skenario DeployMock (7–9) di `test_RunEnvDrivenPaths`, impor `DeployMock`, komentar grup diperbarui |
| `agenthub-phase9-readiness/workstreams/02-deployment-review.md` | Laporan ini (tidak di-commit — konsisten dengan laporan workstream 01/03 yang masih untracked; koordinator yang mengelola direktori ini)             |

**Diff:** +92/−7 pada 3 file kode/test. File sementara audit
(`script/ProbeNoBroadcast.s.sol`, `test/Phase9GapProbe.t.sol`) dibuat
dan **dihapus** dalam audit ini — tidak ada yang tersisa di tree.
Artefak `broadcast/`/`cache/` yang dihasilkan CLI audit ini dibersihkan.

**Verifikasi akhir pasca-perubahan:** `forge test` 323/323 (22 suite);
`forge fmt` bersih pada 3 file yang diubah; CLI pasca-perbaikan kasus G
(`DeployMock` tanpa konfirmasi → `TestnetDeployNotConfirmed()`,
dengan konfirmasi → simulasi sukses).

---

## 11. Lampiran — perintah yang dijalankan (reproduksi)

```bash
# Baseline (HEAD e1b316b)
forge test --match-contract "DeployScriptTest|PauserRoleTest|SafeValidationTest"
# → 54 passed

# Gitleaks
~/workspace/bin/gitleaks detect --log-opts="--all"          # 107 commit, 0 leak
~/workspace/bin/gitleaks detect --no-git                    # 4 FP di .next/ + out/ (gitignored)

# Matriks guard CLI (anvil lokal chain 97/1 + fork live publicnode)
forge script script/DeployAgentHub.s.sol --rpc-url http://127.0.0.1:8545   # A/B/C/D/E
forge script script/DeployLocalTestStack.s.sol --rpc-url http://127.0.0.1:8545  # F
forge script script/DeployMock.s.sol --rpc-url http://127.0.0.1:8545          # G (pra + pasca)
forge script script/DeployAgentHub.s.sol --fork-url https://bsc-testnet-rpc.publicnode.com  # H, C2

# Bukti celah pra-perbaikan (probe sementara, sudah dihapus)
forge test --match-contract Phase9GapProbe
# → [PASS] test_GAP_SameSafeForAdminAndCreatorDeploys()

# Regresi penuh pasca-perbaikan
forge test   # → 323 passed, 0 failed, 0 skipped (22 suite)
forge fmt script/DeployAgentHub.s.sol script/DeployMock.s.sol test/DeployScript.t.sol
```

### Inventaris environment variable (lengkap)

Semua `vm.env*` di `script/` dan cakupannya di `.env.example`:

| Variabel                 | Dipakai di                                                          | `.env.example` | Wajib?                        |
| ------------------------ | ------------------------------------------------------------------- | -------------- | ----------------------------- |
| `CONFIRM_MAINNET_DEPLOY` | `DeployAgentHub.run()` `:141`                                       | ✅             | Ya (chain 56)                 |
| `CONFIRM_TESTNET_DEPLOY` | `DeployAgentHub.run()` `:147`, `DeployMock.run()` `:28`             | ✅             | Ya (chain 97)                 |
| `AGENT_ID_ADDRESS`       | `DeployAgentHub.run()` `:151`                                       | ✅             | Tidak (default mock)          |
| `ADMIN_MULTISIG`         | `DeployAgentHub.run()` `:152`, `ValidateSafe.run()`                 | ✅             | Ya                            |
| `QUEST_CREATOR`          | `DeployAgentHub.run()` `:153`                                       | ✅             | Ya                            |
| `PAUSER`                 | `DeployAgentHub.run()` `:154`                                       | ✅             | Tidak (default multisig)      |
| `VERIFIER`               | `DeployAgentHub.run()` `:155`                                       | ✅             | Tidak                         |
| `SAFE_SINGLETON`         | `DeployAgentHub.run()` `:156`, `ValidateSafe.run()`                 | ✅             | Ya (31337); terlarang (56/97) |
| `SAFE_PROXY_CODEHASH`    | `DeployAgentHub.run()` `:157`, `ValidateSafe.run()`                 | ✅             | Ya (31337); terlarang (56/97) |
| `DEPLOYER_PRIVATE_KEY`   | `DeployAgentHub.run()` `:159`, `DeployMock.run()`                   | ✅             | Ya                            |
| `BSCSCAN_API_KEY`        | `foundry.toml` `[etherscan]` (interpolasi env, tanpa nilai di file) | ✅             | Ya (untuk verifikasi)         |

Tidak ada variabel ke-11 yang dibaca script mana pun (grep `vm.env`
lengkap, §1). Tidak ada input rahasia ke-9 di luar 8 input checklist +
kunci deployer — konsisten dengan temuan Phase 7 L23.
