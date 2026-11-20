# AGENTHUB — Phase 9.1, Workstream 04: Final Security Review (Jalur Deployment)

**Item:** 6 — audit ulang keamanan jalur deployment pasca-perubahan Phase 9.1.
**Tanggal:** 20 November 2026.
**Repo HEAD:** `0313922` (`fix(test): correct ANVIL_KEY typo in DeployScriptTest`) —
4 commit Phase 9.1 setelah `81947ce`.
**Target:** BNB Testnet, chain 97.
**Solidity:** 0.8.39, `via_ir = true`, `evm_version = "cancun"`.
**Ruang lingkup:** audit baca-source saja — tidak ada perubahan file repo
ter-track, tidak ada commit/push, tidak ada deployment, tidak ada broadcast,
tidak ada private key yang dipakai atau diminta.

> **⚠️ PRIVATE KEY TIDAK PERNAH DIKIRIM KE CHAT, LAPORAN, ATAU REPO.**
> Laporan ini tidak memuat dan tidak membutuhkan private key apa pun.
> Semua bukti berasal dari source yang dibaca langsung, bukan dari klaim
> laporan lain (laporan Phase 7/Phase 9 dipakai hanya sebagai konteks
> temuan yang dirujuk).

## 0. Ringkasan

Jalur deployment **aman untuk dilanjutkan ke persetujuan user**, dengan
3 temuan Low baru dan 5 observasi Info — semuanya bersifat
integritas-rekaman / defense-in-depth, **tidak ada** yang menyentuh dana,
kunci, atau otoritas on-chain, dan **tidak ada** yang menjadi blocker
smoke test bila mitigasi SOP-nya diterapkan. Tidak ada temuan
Critical/High/Medium baru.

| #         | Temuan baru                                                                                                         | Severity | Status                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------------- |
| PH9.1-F01 | Dry-run `DeployAgentHub.run()` menimpa artefak deployment nyata dengan alamat simulasi + tx hash kosong (§1.6, §10) | Low      | Terbuka — mitigasi SOP tersedia          |
| PH9.1-F02 | `RecordDeployment` mempercayai broadcast file fork (receipt ada) sebagai deployment live (§3.3, §10)                | Low      | Terbuka — mitigasi SOP tersedia          |
| PH9.1-F03 | `ProposeGrantVerifier.run()` tanpa chain allowlist / guard `CONFIRM_*` pada jalur schedule (§4.3, §10)              | Low      | Terbuka — blast radius dibatasi on-chain |
| PH9.1-I01 | 2 dari 4 assert §5.3 Phase 9 masih hilang: deployer `PROPOSER_ROLE`/`EXECUTOR_ROLE` negatif (§1.5)                  | Info     | Terbuka — by-construction impossible     |
| PH9.1-I02 | 7 env var script baru tidak didokumentasikan di `.env.example` (§8.3)                                               | Info     | Terbuka — dokumen saja                   |
| PH9.1-I03 | Komentar "32 checks" di `_verifyWiring` tidak presisi (§1.5)                                                        | Info     | Terbuka — dokumen saja                   |
| PH9.1-I04 | Forge menyimpan nilai sensitif (kunci deployer) di `cache/` saat dry-run (§8.3)                                     | Info     | Diterima — `cache/` di-gitignore         |
| PH9.1-I05 | Rekomendasi SOP D03 belum ditulis di dokumen mana pun (§7.3)                                                        | Info     | Terbuka — satu baris dokumen             |

Verdict per item cakupan:

| Item | Cakupan                                                           | Verdict                                                                           |
| ---- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| 1    | `DeployAgentHub.s.sol` (L17, L18, M05, D01, Safe, zero-privilege) | **TEMUAN** (F01 — Low; sisanya AMAN)                                              |
| 2    | `DeployMock.s.sol` (guard D02)                                    | **AMAN**                                                                          |
| 3    | `RecordDeployment.s.sol` (baru, L18)                              | **TEMUAN** (F02 — Low; sisanya AMAN)                                              |
| 4    | `ProposeGrantVerifier.s.sol` (baru, L19)                          | **TEMUAN** (F03 — Low; sisanya AMAN)                                              |
| 5    | `SafeValidation.sol`                                              | **AMAN**                                                                          |
| 6    | Timelock (konfigurasi + ownership pasca-deploy)                   | **AMAN**                                                                          |
| 7    | PH9-D03 — guard di `run()`, bukan `deploy()`                      | **AMAN** (risiko residual tidak berubah; SOP masih belum ditulis — I05, lihat §7) |
| 8    | Environment config (`foundry.toml`, `.gitignore`, env var)        | **TEMUAN** (I02/I04 — Info; tidak ada secret terekspos)                           |
| 9    | Bukti: tidak ada broadcast tanpa konfirmasi eksplisit             | **TERBUKTI** (§9)                                                                 |

Verifikasi empiris yang dilakukan dalam audit ini (di luar baca source):

- `forge test --match-contract "DeployScriptTest|DeploymentArtifactTest|
ProposeGrantVerifierTest|SafeValidationTest"` → **67/67 PASS** (HEAD
  `0313922`, build cache hangat).
- Dry-run `DeployLocalTestStack` tanpa `--broadcast` terhadap anvil lokal
  **membuktikan** `vm.writeJson` dieksekusi saat simulasi (file
  `.anvil-deployment.json` tertulis dengan alamat simulasi) — dasar bukti
  F01. Artefak percobaan dibersihkan setelahnya; `git status` bersih
  kecuali direktori laporan untracked.
- Grep repo penuh untuk `startBroadcast` / `vm.broadcast` dan untuk
  kontrak `is Script` — inventaris lengkap di §9.

## 1. `packages/contracts/script/DeployAgentHub.s.sol`

### 1.1 Cek CANCELLER_ROLE di `_verifyWiring` (PH7-L17) — AMAN

- Cek positif multisig ada di `:403`:
  `timelock.hasRole(timelock.CANCELLER_ROLE(), params.adminMultisig)`,
  revert `WiringCheckFailed("timelock.canceller")` bila hilang.
- Cek negatif deployer ada di `:479`:
  `timelock.hasRole(timelock.CANCELLER_ROLE(), deployer)` → revert
  `WiringCheckFailed("deployer.canceller")`.
- Premisnya benar terhadap OZ yang di-vendor: konstruktor
  `TimelockController`
  (`lib/openzeppelin-contracts/contracts/governance/TimelockController.sol:126-127`)
  memberikan `CANCELLER_ROLE` kepada setiap proposer — jadi multisig
  memegangnya by construction, dan assert ini adalah jaring deploy-time
  seperti yang diminta L17.
- Test menutupnya: `test_CancellerRoleHeldByMultisig` dan
  `test_VerifyWiringRevertsWhenCancellerMissing` /
  `test_VerifyWiringRevertsWhenDeployerHoldsCanceller`
  (`test/DeployScript.t.sol:526-551`) — semuanya PASS (§0).
- **PH7-L17 DITUTUP**, dengan satu catatan kelengkapan (I01, §1.5).

### 1.2 Artefak JSON otomatis `deployments/<chainId>.json` (PH7-L18) — AMAN, kecuali F01

- Penulisan di `run()` `:184-186`, setelah `stopBroadcast()` (`:174`):
  `if (vm.envOr("WRITE_DEPLOYMENT_ARTIFACT", true)) writeDeploymentArtifact(...)`.
- `writeDeploymentArtifact` (`:207-230`) menulis 16 field datar:
  `chainId`, `blockNumber`, `timestamp`, `deployer`, 6 alamat kontrak,
  6 tx-hash (string kosong — forge baru tahu hash setelah broadcast).
  **Tidak ada secret yang tertulis**: tidak ada pemanggilan
  `vm.envUint`, tidak ada kunci/mnemonic di serialisasi manapun; hanya
  alamat + data chain publik. Deployer address adalah data publik
  on-chain.
- Path berasal dari `artifactPath()` (`:191-193`):
  `deployments/<block.chainid>.json` — tidak ada input operator yang
  bisa mengarahkan path (chainId adalah uint dari chain). Parameter
  `path` di `writeDeploymentArtifact` bersifat publik, tetapi penulisan
  file dibatasi `fs_permissions` ke `./deployments` (lihat §8.1), jadi
  tidak bisa menulis ke luar direktori itu.
- `WRITE_DEPLOYMENT_ARTIFACT=false` opt-out **tidak membuka celah
  keamanan**: efeknya hanya menghilangkan catatan (record loss), bukan
  mengubah perilaku on-chain. Satu-satunya risiko adalah operasional:
  env var yang tertinggal `false` dari sesi test akan membuat deploy
  nyata tidak tercatat — dicakup sebagai sub-kasus F01 (§10).
- **PH7-L18 DITUTUP** untuk penulisan artefaknya; temuan F01 adalah
  soal integritas artefak, bukan soal rahasia.

### 1.3 Guard `CONFIRM_TESTNET_DEPLOY` chain 97 (PH7-M05) — AMAN

- Urutan di `run()` (`:144-158`) benar dan fail-closed: allowlist chain
  (`:145-147`, hanya 56/97/31337) → guard mainnet (`:150-152`) →
  guard testnet (`:156-158`, `vm.envOr("CONFIRM_TESTNET_DEPLOY", false)`).
  Semua guard berjalan **sebelum** env lain dibaca dan sebelum
  `DEPLOYER_PRIVATE_KEY` dibaca (`:168`).
- Guard simetris mainnet/testnet seperti yang diminta M05; guard tidak
  bisa membedakan dry-run dari broadcast (didokumentasikan di checklist 03) — justru itu yang membuat F01 mungkin (dry-run pun menulis
  artefak).
- **PH7-M05 tetap TERTUTUP.**

### 1.4 `AdminAndCreatorMustDiffer` (PH9-D01) — AMAN

- Error dideklarasikan `:94`; cek di `deploy()` `:250`, sebelum
  validasi Safe maupun `CREATE` apa pun:
  `if (params.adminMultisig == params.questCreator) revert AdminAndCreatorMustDiffer();`
- Penempatan di `deploy()` (bukan hanya `run()`) berarti pemisahan
  tugas ditegakkan juga untuk pemanggil langsung `deploy()` — lebih
  kuat dari guard konfirmasi (lihat §7).
- Test `test_TestnetRejectsSameSafeForAdminAndCreator` PASS.
- **PH9-D01 tetap TERTUTUP.**

### 1.5 Validasi Safe admin/creator — AMAN (dengan 2 Info)

- Admin divalidasi sebelum deploy apa pun (`:265-275`); creator
  divalidasi dengan helper yang sama (`:279-285`) — PH7-M03.
  Jalur 31337 memakai overload eksplisit (wajib
  `SAFE_SINGLETON` + `SAFE_PROXY_CODEHASH`, `:266-268`); jalur
  56/97 **menolak** nilai eksplisit (`:271-273`,
  `ExplicitSingletonNotAllowedOnProduction`) sehingga tidak ada
  override terhadap cek kanonis di production.
- Kekuatan mekanisme validasinya sendiri dinilai di §5 — AMAN.
- **PH9.1-I01 (Info):** rekomendasi Phase 9 workstream 02 §5.3 meminta
  4 assert — CANCELLER positif + 3 negatif deployer
  (proposer/executor/canceller). Phase 9.1 menambahkan 2 dari 4
  (`:403`, `:479`); assert negatif deployer untuk `PROPOSER_ROLE` dan
  `EXECUTOR_ROLE` timelock **masih hilang**. Dampak praktis nihil:
  konstruktor OZ hanya memberikan kedua role itu ke daftar
  proposer/executor (= admin multisig saja, `:310-314`), jadi deployer
  tidak mungkin memegangnya by construction, dan state on-chain sudah
  dibuktikan test (Phase 9 §5.2). Ini murni kelengkapan jaring
  deploy-time — sarankan tambah 2 baris pada kesempatan berikutnya,
  bukan blocker.
- **PH9.1-I03 (Info):** komentar `:374-376` mengklaim "with it,
  `_verifyWiring` performs 32 checks" (merujuk ke cek `mock.owner`).
  Hitungan aktual dari source: 32 cek hanya bila mock di-deploy **dan**
  verifier di-set (6 identitas + 6 timelock + 3 admin + 6 operasional
  - 11 negatif deployer); tanpa verifier = 31, tanpa mock = 30–31.
    Ketidakpresisian dokumen kelas L16 — perbaiki komentarnya, bukan
    blocker.

### 1.6 Penulisan artefak saat dry-run — TEMUAN F01 (Low)

Lihat §10 (PH9.1-F01). Ringkas: `run()` menulis artefak tanpa
membedakan simulasi dari broadcast (forge tidak menyediakan sinyal itu
di dalam script), sehingga dry-run pasca-deploy menimpa artefak nyata.
Dibuktikan empiris (§0). Tidak ada dampak on-chain; artefak dapat
direkonstruksi dari broadcast artifact + `RecordDeployment`.

### 1.7 Deployer zero-privilege pasca-deploy — AMAN

- `deploy()` `:336-343`: timelock diberi `DEFAULT_ADMIN_ROLE` di
  Reputation, Achievement, QuestManager, lalu deployer me-renounce
  ketiganya.
- Mock ownership ditransfer ke admin multisig (`:352-354`, PH7-M04) —
  tanpa ini deployer mempertahankan mint power tak terbatas atas
  Agent ID test.
- `_verifyWiring` menegaskan 11 kondisi negatif deployer (`:449-481`):
  admin di 3 kontrak, `SCORE_SOURCE_ROLE`, `ISSUER_ROLE`,
  `BADGE_MANAGER_ROLE`, `QUEST_CREATOR_ROLE`, `PAUSER_ROLE`,
  `VERIFIER_ROLE`, timelock admin, timelock canceller — plus
  `mock.owner() == adminMultisig` (`:377-381`).
- Tidak ada jalur di script yang memberi deployer role operasional
  apa pun; `effectivePauser` default ke admin multisig, dan bila
  operator mengisi `PAUSER` = alamat deployer, cek negatif
  `deployer.pauser` (`:473-475`) akan me-revert deploy — fail-closed.
- **Deployer berakhir dengan NOL privilege. AMAN.**

## 2. `packages/contracts/script/DeployMock.s.sol` — AMAN

- Allowlist chain `:24`: hanya 97 atau 31337 (`require`, bukan
  denylist) — mock tidak pernah bisa di-deploy ke mainnet 56.
- Guard testnet PH9-D02 `:28-30`: `block.chainid == 97` tanpa
  `CONFIRM_TESTNET_DEPLOY=true` → revert `TestnetDeployNotConfirmed()`.
  Guard berjalan sebelum `DEPLOYER_PRIVATE_KEY` dibaca (`:31`) dan
  sebelum `startBroadcast` (`:32`). Simetris dengan DeployAgentHub.
- Anvil 31337 dikecualikan dari guard, konsisten dengan DeployAgentHub
  (tidak ada nilai nyata di chain lokal).
- Satu-satunya efek: deploy `MockAgentId` baru; tidak ada role, tidak
  ada wiring, tidak ada transfer ownership di script ini (mock yang
  di-deploy lewat jalur ini dimiliki deployer sampai dipakai —
  pemakaian produksi adalah sebagai `AGENT_ID_ADDRESS` untuk
  DeployAgentHub, dan ownership mock hasil DeployAgentHub ditransfer
  ke multisig per §1.7).
- **PH9-D02 tetap TERTUTUP. AMAN.**

## 3. `packages/contracts/script/RecordDeployment.s.sol` (BARU, PH7-L18)

### 3.1 Tidak ada broadcast, tidak ada secret — AMAN

- Grep penuh file: **nol** kemunculan `startBroadcast` / `broadcast`
  sebagai aksi (kata "broadcast" hanya muncul di komentar/NatSpec dan
  di nama path `broadcast/...`). Script ini murni file I/O:
  `vm.readFile` (`:57-58`) + `vm.writeJson` (`:101`).
- Tidak membaca kunci: satu-satunya env var adalah `CHAIN_ID`
  (`vm.envUint`, `:43`) — non-sensitif. Tidak ada `vm.envUint` lain.
- Path dikonstruksi dari `CHAIN_ID` (uint) — tidak ada injeksi path
  dari operator; `record()` yang publik memang menerima path arbitrer,
  tetapi `fs_permissions` membatasi baca ke `./broadcast` dan tulis
  ke `./deployments` (lihat §8.1), jadi `record()` tidak bisa dipakai
  untuk membaca `.env` atau menulis ke luar direktori artefak.
- Field yang ditulis ulang adalah 16 field yang sama dengan skema
  artefak (alamat + hash + metadata publik) — tidak ada secret yang
  bisa masuk lewat broadcast file, karena hanya `transactionHash`,
  `contractAddress`, dan `blockNumber` dari receipt yang dipakai
  (`_findTx`, `:133-171`).

### 3.2 Idempotent / dry-run aman — AMAN (dengan catatan F02)

- Aturan pencocokan ketat dan fail-safe: hanya receipt dengan
  `contractAddress` == alamat artefak yang cocok (`:149-153`); receipt
  non-create (contractAddress null) dilewati via try/catch; entri
  yang gagal parse dilewati, tidak pernah fatal (`:144-170`).
- Hash yang sudah ada **dipertahankan** bila tidak ada receipt yang
  cocok (`:70-76`) — re-run idempotent dan tidak pernah menghapus
  hash yang sudah tercatat. `blockNumber` hanya dikoreksi bila ada
  receipt yang cocok (`:82-85`).
- File dry-run (array `receipts` kosong) meninggalkan semua hash
  kosong + peringatan (`:115-118`), tidak pernah mencatat hash
  prediksi sebagai hash nyata. Klaim "dry-run aman" di NatSpec
  terverifikasi dari kode.
- Test `DeploymentArtifact.t.sol` menutup skenario ini (termasuk
  fixture `deployments/31337-missing.json` — file test, di-gitignore).

### 3.3 Broadcast file fork dipercaya sebagai live — TEMUAN F02 (Low)

Lihat §10 (PH9.1-F02). Ringkas: perlindungan "hanya receipt yang
dihitung" membedakan dry-run dari broadcast, tetapi **tidak**
membedakan broadcast ke fork anvil chain 97 dari broadcast ke testnet
live — keduanya punya receipts. Ini analog langsung PH7-L20 (artefak
fork basi yang terlihat seperti deployment nyata). Dampaknya hanya
integritas rekaman; mitigasi SOP tersedia (jalankan segera setelah
broadcast live; verifikasi ≥1 hash di BscScan).

## 4. `packages/contracts/script/ProposeGrantVerifier.s.sol` (BARU, PH7-L19)

### 4.1 Preview-only default — AMAN

- `run()` (`:67-90`): membangun proposal, mencetak ringkasan, lalu
  hanya broadcast bila `vm.envOr("SCHEDULE", false)` (`:78`).
  Default-nya preview-only dengan pesan eksplisit (`:86-88`).
- `PROPOSER_PRIVATE_KEY` hanya dibaca di dalam cabang `SCHEDULE=true`
  (`:79`) — preview tidak pernah menyentuh kunci.
- Runbook `script/ProposeGrantVerifier.md` konsisten dengan kode:
  proposer produksi adalah Safe (tanpa kunci), jadi jalur broadcast
  script tidak bisa dipakai untuk Safe; schedule normal dilakukan
  lewat transaksi Safe dengan argumen dari ringkasan.

### 4.2 Tidak ada jalur direct-grant — AMAN

- Satu-satunya pemanggilan state-changing ke timelock adalah
  `timelock.schedule(...)` (`:142-144`). Script tidak pernah memanggil
  `QuestManager.grantRole` secara langsung — calldata grant
  (`abi.encodeCall(IAccessControl.grantRole, ...)`, `:115`) hanya
  dibungkus sebagai payload operasi timelock, dan hanya timelock
  (pemegang `DEFAULT_ADMIN_ROLE` di QM) yang bisa mengeksekusinya
  setelah delay.
- `buildProposal` memvalidasi prasyarat sebelum apa pun dijadwalkan
  (`:96-120`): verifier non-zero, timelock + QM punya code,
  verifier belum memegang role, **timelock adalah admin QM**
  (`:108-110`), dan `minDelay` persis 2 hari (`:112-113`,
  `UnexpectedTimelockDelay`).
- Salt default deterministik per verifier
  (`keccak256("agenthub-grant-verifier" || verifier)`, `:114`) —
  preview yang diulang mereproduksi operation id yang sama; tidak ada
  risiko tabrakan antar verifier yang berbeda.
- Tidak ada broadcast tersembunyi: satu-satunya `startBroadcast` ada
  di `:80`, di dalam cabang `SCHEDULE=true`. Grep file mengonfirmasi
  tidak ada `vm.broadcast` lain.
- Test `ProposeGrantVerifier.t.sol` membuktikan: schedule → delay
  2 hari → execute memberi role; execute sebelum delay revert;
  non-proposer tidak bisa schedule; grant langsung revert; cancel
  sebelum execute menggagalkan grant. Semua PASS (§0).

### 4.3 Tanpa chain allowlist / guard konfirmasi pada jalur schedule — TEMUAN F03 (Low)

Lihat §10 (PH9.1-F03). Ringkas: `run()` tidak memeriksa
`block.chainid` sama sekali dan tidak memakai guard `CONFIRM_*`;
satu-satunya gerbang niat adalah `SCHEDULE=true`. Ini menyimpang dari
standar proyek sendiri (M05) yang diterapkan di DeployAgentHub dan
DeployMock. Blast radius dibatasi on-chain (hanya `PROPOSER_ROLE`
yang bisa schedule — OZ `:273` `onlyRole(PROPOSER_ROLE)` — plus delay
2 hari + bisa di-cancel), sehingga severity Low, tetapi inkonsistensi
ini layak ditutup dengan allowlist chain sebelum smoke test.

## 5. `packages/contracts/script/SafeValidation.sol` — AMAN

Validasi masih kuat; tidak ada perubahan Phase 9.1 pada file ini dan
tidak ada celah baru yang ditemukan saat dibaca ulang penuh:

- Urutan cek fail-closed (`_validateCommon`, `:140-149`): ada code
  dulu (EOA ditolak — staticcall ke EOA sukses dengan returndata
  kosong, jadi cek code **harus** pertama, dan memang pertama),
  lalu threshold ∈ [2, ownerCount] dan ownerCount ≥ 2
  (`MIN_SAFE_THRESHOLD = 2`, `:67`).
- Anti-spoofing berlapis (`validate`, `:111-122`): `masterCopy()`
  harus singleton kanonis v1.4.1 (`0x41675C...`, `:72`) atau v1.3.0
  (`0xd9Db27...`, `:77`), **dan** runtime codehash proxy harus
  codehash kanonis (`:119`, konstanta `:82`/`:87`). Kontrak palsu
  bisa memalsukan `masterCopy()` tetapi tidak bisa memalsukan
  codehash tanpa **menjadi** proxy kanonis — dan proxy kanonis tidak
  bisa berbohong soal threshold/owner karena mendelegasikan ke
  singleton asli. `VERSION()` "1.3.0"/"1.4.1" sebagai cek konsistensi
  (`:195-203`).
- Semua pembacaan memakai low-level `staticcall` + cek panjang
  returndata (`:151-193`) — pola fail-closed yang sama dengan
  AgentGate SEC-001; decode yang malformed me-revert (aman: deploy
  batal).
- Overload eksplisit (`:131-139`) revert di chain apa pun selain
  31337, dan DeployAgentHub menolak nilai eksplisit di 56/97 (§1.5)
  — tidak ada jalur override kanonis di production.
- Batasan yang masih berlaku dan sudah didokumentasikan (bukan
  temuan baru): cek ini membuktikan "ini Safe asli", **bukan** "ini
  Safe milik tim yang benar" — identitas owner tetap harus
  dikonfirmasi out-of-band oleh operator (DEPLOYMENT_PLAN.md §5).
  Konstanta kanonis mengandalkan verifikasi dua-arah Phase 1
  (safe-deployments + pembacaan on-chain BSC 56/97); audit ini tidak
  mengulang verifikasi on-chain tersebut karena tidak ada Safe
  testnet yang diketahui alamatnya untuk dibandingkan — dicatat
  sebagai ketergantungan, bukan keraguan.

## 6. Timelock — konfigurasi & ownership pasca-deploy — AMAN

Dibaca dari `DeployAgentHub.deploy()` `:305-314` + `_verifyWiring`
`:387-414` + konstruktor OZ yang di-vendor:

| Role / parameter                              | Nilai                                | Bukti                                                                                                                                                  |
| --------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `minDelay`                                    | 2 hari (`TIMELOCK_DELAY`, `:76`)     | `new TimelockController(TIMELOCK_DELAY, ...)` `:314`; ditegaskan `:390`                                                                                |
| `PROPOSER_ROLE`                               | admin multisig (satu-satunya)        | proposers[0] `:309-310`; ditegaskan `:393-395`                                                                                                         |
| `EXECUTOR_ROLE`                               | admin multisig (satu-satunya)        | executors[0] `:311-312`; ditegaskan `:396-398`                                                                                                         |
| `CANCELLER_ROLE`                              | admin multisig (satu-satunya)        | OZ ctor `:126-127` (setiap proposer); ditegaskan `:403` (L17)                                                                                          |
| `DEFAULT_ADMIN_ROLE`                          | timelock itu sendiri                 | OZ ctor `:117`; admin param = `address(0)` (`:314`, OZ `:121` tidak memberi ke siapa pun); ditegaskan `:406-413` (self-admin ya, multisig bukan admin) |
| Admin Reputation / Achievement / QuestManager | timelock                             | grant `:336-340`; ditegaskan `:416-426`                                                                                                                |
| Deployer pasca-deploy                         | nol role di semua kontrak + timelock | renounce `:341-343`; ditegaskan `:449-481`                                                                                                             |

- Tidak ada admin opsional: perubahan konfigurasi timelock sendiri
  harus lewat proposal timelock (self-administered) — sesuai panduan
  OZ yang dikutip di NatSpec.
- Executor = multisig saja (bukan `address(0)` = siapa pun boleh
  execute): eksekusi tetap di tangan multisig, konsisten dengan
  model admin proyek.
- Satu-satunya peran operasional di luar timelock: `PAUSER_ROLE`
  (default = admin multisig, tanpa timelock — by design, fast pause)
  dan `QUEST_CREATOR_ROLE` (Safe creator terpisah, D01) — keduanya
  bukan jalur untuk mengubah admin, role, atau konfigurasi.
- **Konfigurasi timelock benar dan ditegakkan deploy-time. AMAN.**

## 7. PH9-D03 — guard hidup di `run()`, bukan `deploy()`: dinilai ulang

**Status: risiko residual TIDAK BERUBAH oleh Phase 9.1. Bukan jalur
kecelakaan. AMAN dengan satu SOP yang masih belum ditulis.**

### 7.1 Apa yang masih benar

- `deploy()` (`DeployAgentHub.s.sol:238`) tetap `public`, tanpa guard
  konfirmasi, dan tetap tidak mengandung `startBroadcast`. Bukti
  empiris Phase 9 (probe I, workstream 02 §7.1): script tanpa blok
  broadcast + `--broadcast` menghasilkan "No transactions to
  broadcast" — forge tidak mengirim apa pun. Artinya memanggil
  `deploy()` langsung via `forge script --sig deploy(...) --broadcast`
  **tidak** men-deploy; satu-satunya cara melewati guard adalah
  menulis **script wrapper baru** yang memanggil `deploy()` di dalam
  blok `startBroadcast` miliknya sendiri — kode baru yang disengaja,
  bukan kecelakaan CLI.
- `deploy()` sendiri tetap mempertahankan semua guard non-konfirmasi:
  allowlist chain (`:240`), `AdminAndCreatorMustDiffer` (`:250`),
  validasi Safe admin + creator (`:269-285`), kunci Agent ID mainnet
  (`:287-289`), dan `_verifyWiring` (`:357`). Wrapper yang nakal
  masih harus melewati semua itu; yang dilewati hanya cek niat
  operator (`CONFIRM_*`).

### 7.2 Apakah Phase 9.1 memperkenalkan jalur baru?

- **Tidak.** Inventaris script lengkap (7 kontrak `is Script`,
  §9): tidak ada wrapper baru yang memanggil `deploy()`. Pemanggil
  `deploy()` di repo hanyalah test (`DeployScript.t.sol`,
  `DeploymentArtifact.t.sol`, `ProposeGrantVerifier.t.sol`).
- `RecordDeployment` tidak memanggil `deploy()`, tidak broadcast,
  tidak membaca kunci (§3).
- `ProposeGrantVerifier` tidak memanggil `deploy()`; fungsi
  `scheduleGrant()`-nya yang publik (`:137`) adalah analog D03 —
  tetapi analog yang **tidak bisa** di-bypass lewat `--sig` begitu
  saja, dengan alasan yang sama seperti probe I: `scheduleGrant`
  tidak mengandung `startBroadcast`, jadi pemanggilan langsung +
  `--broadcast` tidak mengirim apa pun; broadcast hanya terjadi
  lewat blok `startBroadcast` di `run()` (`:80`), yang dijaga
  `SCHEDULE=true`. Melewati `SCHEDULE` membutuhkan wrapper baru yang
  disengaja — kelas risiko yang sama persis dengan D03.
- Tidak ada script/shell/CI baru yang menjalankan `forge script`
  dengan `--broadcast` selain yang sudah ada (dua skrip anvil lokal,
  §9).

### 7.3 Satu-satunya yang masih terbuka: SOP-nya belum ditulis

Rekomendasi Phase 9 (§7.3) adalah menambahkan satu baris ke
SOP/checklist: \_"deploy HANYA lewat `run()`; script apa pun yang
memanggil `deploy()` langsung wajib mereplikasi guard `CONFIRM\__`"\*.**
Grep atas `docs/`, checklist Phase 9, dan workstream Phase 9.1
(termasuk checklist 03 yang baru) **tidak menemukan baris itu\*\* —
checklist 03 mendokumentasikan guard `CONFIRM_TESTNET_DEPLOY` (§9)
tetapi tidak menyebut larangan wrapper/`deploy()`langsung. Ini
dicatat sebagai temuan Info tersendiri di §10 (PH9.1-I05). Rekomendasi: tambahkan satu baris itu ke checklist 03
§9 dan/atau`docs/DEPLOYMENT_PLAN.md` sebelum smoke test. Murah,
tanpa kode, dan menutup satu-satunya tindak lanjut D03 yang tersisa.

## 8. Environment config

### 8.1 `foundry.toml` — `fs_permissions` — AMAN

```toml
fs_permissions = [
  { access = "read-write", path = "./.anvil-deployment.json" },
  { access = "read-write", path = "./deployments" },   # BARU Phase 9.1 (L18)
  { access = "read",       path = "./broadcast" },     # BARU Phase 9.1 (L18)
]
```

Penilaian risiko perluasan (perubahan Phase 9.1, commit `8d2f9dc`):

- `./deployments` read-write, scoped ke direktori: script hanya bisa
  menulis artefak deployment di sana. Risiko terburuk dari sebuah
  script yang dikompromikan/ditulis salah adalah **meracuni rekaman**
  (artefak dengan alamat salah yang lalu di-commit) — bukan eksekusi
  kode, bukan pencurian kunci, bukan perubahan on-chain. Artefak
  adalah data publik (alamat + hash) dan diverifikasi ulang terhadap
  BscScan saat smoke test. Risiko diterima.
- `./broadcast` read-only: script bisa membaca artefak broadcast
  (diperlukan `RecordDeployment`) tetapi **tidak bisa** mengubah atau
  menghapusnya — arah yang benar.
- Tidak ada perluasan ke path sensitif: tidak ada akses ke `.env`,
  `~/.ssh`, atau root proyek. `vm.readFile` di luar path yang
  diizinkan revert — ini yang membuat `record()` publik (§3.1) aman
  dari penyalahgunaan path.
- Catatan: perluasan ini **diperlukan** oleh L18; alternatifnya
  (tanpa artefak otomatis) adalah pencatatan manual 6 alamat +
  nomor blok, yang sudah terbukti rawan salah (L16).
- Bagian `[etherscan]` memakai interpolasi env
  `${BSCSCAN_API_KEY}` — tidak ada materi kunci di file.
- **AMAN.**

### 8.2 `.gitignore` — artefak 56/97 bisa di-commit — AMAN

- Root `.gitignore`: `.env` / `.env.*` (kecuali `.env.example`),
  `*.pem`, `*.key`, `packages/contracts/broadcast/`,
  `packages/contracts/cache/`, `packages/contracts/out/` — semua
  diabaikan. Hanya `.env.example` yang ter-track (verifikasi:
  `git ls-files | grep -i .env` → hanya `.env.example`).
- Aturan Phase 9.1 (L18): `packages/contracts/deployments/31337*.json`
  dan `*.fixture.json` diabaikan; artefak `56.json` / `97.json`
  **sengaja** bisa di-commit sebagai rekaman deployment.
- **Tidak ada secret yang bisa ikut ter-commit lewat jalur ini:**
  satu-satunya penulis ke `deployments/` adalah
  `writeDeploymentArtifact` (16 field publik, §1.2) dan
  `RecordDeployment` (field yang sama + hash dari receipt, §3.1).
  Tidak ada penulis lain ke direktori itu (grep `writeJson` di
  `script/` → hanya 3 lokasi: DeployAgentHub, DeployLocalTestStack
  ke `.anvil-deployment.json`, RecordDeployment).
- Satu-satunya file di `deployments/` saat audit:
  `.gitkeep` (ter-track, berisi peringatan "NEVER store keys or
  secrets here") dan `31337-missing.json` (fixture test, untracked,
  di-gitignore). Tidak ada artefak 56/97 — konsisten dengan status
  "belum pernah deploy".
- **AMAN.**

### 8.3 Env var yang dipakai script — inventaris lengkap

Grep `vm.env*` atas seluruh `script/*.sol` (tidak ada `vm.env` di
`src/`):

| Env var                                      | Dipakai di                                        | Sensitif?             | Penanganan                                                                                                                             |
| -------------------------------------------- | ------------------------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `DEPLOYER_PRIVATE_KEY`                       | DeployAgentHub `:168`, DeployMock `:31`           | **Ya**                | Dibaca setelah guard konfirmasi; hanya dipakai sebagai argumen `startBroadcast`; **tidak pernah** ditulis ke file; `.env` di-gitignore |
| `PROPOSER_PRIVATE_KEY`                       | ProposeGrantVerifier `:79`                        | **Ya**                | Hanya dibaca bila `SCHEDULE=true`; hanya untuk setup EOA/simulasi; tidak pernah ditulis ke file                                        |
| `ADMIN_MULTISIG`                             | DeployAgentHub `:161`, ValidateSafe `:28`         | Tidak (alamat publik) | Wajib; divalidasi sebagai Safe asli sebelum deploy                                                                                     |
| `QUEST_CREATOR`                              | DeployAgentHub `:162`                             | Tidak                 | Wajib; divalidasi sebagai Safe asli; harus ≠ admin (D01)                                                                               |
| `PAUSER`                                     | DeployAgentHub `:163`                             | Tidak                 | Opsional; default = admin multisig                                                                                                     |
| `VERIFIER`                                   | DeployAgentHub `:164`, ProposeGrantVerifier `:70` | Tidak                 | Opsional di deploy; wajib di ProposeGrantVerifier                                                                                      |
| `AGENT_ID_ADDRESS`                           | DeployAgentHub `:160`                             | Tidak                 | Opsional; kosong = deploy Mock (97/31337); wajib = official di 56                                                                      |
| `SAFE_SINGLETON` / `SAFE_PROXY_CODEHASH`     | DeployAgentHub `:165-166`, ValidateSafe `:29-30`  | Tidak                 | Hanya 31337; ditolak di 56/97                                                                                                          |
| `CONFIRM_MAINNET_DEPLOY`                     | DeployAgentHub `:150`                             | Tidak                 | Guard boolean, default false                                                                                                           |
| `CONFIRM_TESTNET_DEPLOY`                     | DeployAgentHub `:156`, DeployMock `:28`           | Tidak                 | Guard boolean, default false                                                                                                           |
| `WRITE_DEPLOYMENT_ARTIFACT`                  | DeployAgentHub `:184`                             | Tidak                 | Opt-out boolean, default true (lihat F01)                                                                                              |
| `CHAIN_ID`                                   | RecordDeployment `:43`                            | Tidak                 | Uint; menentukan path artefak + broadcast                                                                                              |
| `TIMELOCK_ADDRESS` / `QUEST_MANAGER_ADDRESS` | ProposeGrantVerifier `:68-69`                     | Tidak                 | Wajib; divalidasi punya code + wiring                                                                                                  |
| `PROPOSAL_SALT`                              | ProposeGrantVerifier `:71`                        | Tidak                 | Opsional; default deterministik dari verifier                                                                                          |
| `SCHEDULE`                                   | ProposeGrantVerifier `:78`                        | Tidak                 | Guard boolean, default false                                                                                                           |
| `BSCSCAN_API_KEY`                            | `foundry.toml` `[etherscan]` (bukan script)       | **Ya (API key)**      | Interpolasi env; dipakai `forge verify`, tidak pernah dibaca script                                                                    |

- **PH9.1-I02 (Info):** 7 var baru Phase 9.1 — `WRITE_DEPLOYMENT_ARTIFACT`,
  `CHAIN_ID`, `TIMELOCK_ADDRESS`, `QUEST_MANAGER_ADDRESS`,
  `PROPOSAL_SALT`, `SCHEDULE`, `PROPOSER_PRIVATE_KEY` — **tidak ada**
  di `.env.example` (grep: nol kemunculan; yang ada hanya varian
  `NEXT_PUBLIC_*`). `PROPOSER_PRIVATE_KEY` adalah kunci sensitif yang
  penanganannya hanya didokumentasikan di `ProposeGrantVerifier.md`.
  Rekomendasi: tambahkan ketujuhnya ke `.env.example` (dengan
  placeholder kosong + catatan `SCHEDULE`/`PROPOSER_PRIVATE_KEY`
  hanya untuk EOA/simulasi). Dokumen saja, bukan blocker.
- **PH9.1-I04 (Info):** saat dry-run, forge mencetak
  `Sensitive values saved to: .../cache/<script>/<chain>/dry-run/run-latest.json`
  — forge menyimpan materi kunci deployer di `cache/` untuk resume
  broadcast. `cache/` di-gitignore (`packages/contracts/cache/`), jadi
  tidak ikut ter-commit; catatan higiene operator saja: pakai deployer
  khusus yang didanai minimal (sudah menjadi praktik yang
  didokumentasikan) dan jangan bagikan direktori `cache/`.
- Tidak ada private key hardcoded di file ter-track (kecuali kunci
  publik Anvil di `DeployLocalTestStack.s.sol:40,44` — tercetak di
  setiap banner anvil, di-allowlist gitleaks, hanya dipakai di chain
  31337; sudah diverifikasi Phase 9 §6, tidak berubah di Phase 9.1).

## 9. Konfirmasi akhir: tidak ada broadcast tanpa konfirmasi eksplisit

### 9.1 Inventaris lengkap titik broadcast

Grep repo penuh (`.sol`, di luar `lib/`): hanya **4 situs**
`vm.startBroadcast`, **nol** `vm.broadcast` satu-tembakan, di **4 dari
7** kontrak `is Script`. Tidak ada titik broadcast lain di repo.

| #   | Situs                              | Guard chain                                  | Guard konfirmasi eksplisit                                                                     | Kunci                         |
| --- | ---------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------- |
| 1   | `DeployAgentHub.run()` `:172`      | Allowlist 56/97/31337 (`:145-147`)           | 56: `CONFIRM_MAINNET_DEPLOY=true` (`:150-152`); 97: `CONFIRM_TESTNET_DEPLOY=true` (`:156-158`) | `DEPLOYER_PRIVATE_KEY` (env)  |
| 2   | `DeployMock.run()` `:32`           | Allowlist 97/31337 (`:24`)                   | 97: `CONFIRM_TESTNET_DEPLOY=true` (`:28-30`); 31337 dikecualikan (lokal)                       | `DEPLOYER_PRIVATE_KEY` (env)  |
| 3a  | `DeployLocalTestStack.run()` `:78` | `require(chainid == 31337)` (`:66`, PH7-M06) | Tidak perlu — lokal saja, kunci publik Anvil                                                   | Hardcoded anvil key 0         |
| 3b  | `DeployLocalTestStack.run()` `:86` | Sama (`:66`)                                 | Tidak perlu — lokal saja                                                                       | Hardcoded anvil key 1 (Alice) |
| 4   | `ProposeGrantVerifier.run()` `:80` | **Tidak ada** (F03)                          | `SCHEDULE=true` (`:78`) + kunci proposer; on-chain: timelock `onlyRole(PROPOSER_ROLE)`         | `PROPOSER_PRIVATE_KEY` (env)  |

### 9.2 Script tanpa broadcast

| Script                                          | Mengapa tidak bisa broadcast                                                                                                                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `RecordDeployment`                              | Nol `startBroadcast`; murni file I/O (§3.1)                                                                                                                                                        |
| `ValidateSafe`                                  | Read-only (staticcall + console.log)                                                                                                                                                               |
| `ProbeSafeProxy`                                | Tanpa blok broadcast; eksperimen fork one-off. Bukti Phase 9 probe I: tanpa `startBroadcast`, `--broadcast` tidak mengirim apa pun                                                                 |
| `DeployAgentHub.deploy()` (publik)              | Tanpa `startBroadcast` di dalam; pemanggilan langsung + `--broadcast` tidak mengirim (probe I). Hanya wrapper baru yang disengaja bisa melewati guard — tidak ada wrapper seperti itu di repo (§7) |
| `ProposeGrantVerifier.scheduleGrant()` (publik) | Sama: tanpa `startBroadcast`; broadcast hanya lewat `run()` `:80` yang dijaga `SCHEDULE=true` (§7.2)                                                                                               |

### 9.3 Invokasi `--broadcast` di luar Solidity

- `apps/web/scripts/run-anvil-integration.sh:31` dan
  `apps/web/scripts/run-wallet-e2e.sh:59` — keduanya
  `--rpc-url http://127.0.0.1:8545 --broadcast --private-key "$ANVIL_KEY0"`:
  anvil lokal saja, kunci publik Anvil. Bukan jalur production.
- `docs/DEPLOYMENT.md`, `docs/DEPLOYMENT_PLAN.md` — menyebut
  `--broadcast` hanya sebagai instruksi operator (dengan peringatan
  "Never broadcast a dry-run ... without a reviewed decision").
- Tidak ada job CI yang menjalankan `forge script --broadcast`
  (grep `.github/` — tidak ada kemunculan di luar konteks di atas).

### 9.4 Verdict item 9

**TERBUKTI.** Setiap titik broadcast yang ada membutuhkan salah satu
dari: (a) guard konfirmasi eksplisit berbasis env
(`CONFIRM_TESTNET_DEPLOY` / `CONFIRM_MAINNET_DEPLOY` / `SCHEDULE`)
yang default-nya false, atau (b) chain guard lokal 31337 dengan kunci
publik yang tidak bernilai. Tidak ada jalur — di script, test, shell,
maupun CI — yang dapat melakukan broadcast ke chain 56/97 tanpa
operator secara eksplisit menyetel env var konfirmasi **dan**
menjalankan perintah broadcast. Satu-satunya penyimpangan dari pola
ini adalah F03 (tidak ada chain allowlist di ProposeGrantVerifier),
yang blast radius-nya dibatasi on-chain oleh `PROPOSER_ROLE` +
delay 2 hari + cancel — dan tetap membutuhkan `SCHEDULE=true` yang
eksplisit.

## 10. Daftar temuan baru

### PH9.1-F01 — Low — Dry-run menimpa artefak deployment nyata

- **Lokasi:** `DeployAgentHub.s.sol:184-186` (`run()` memanggil
  `writeDeploymentArtifact` tanpa syarat selain opt-out).
- **Bukti:** `vm.writeJson` dieksekusi saat simulasi forge — dibuktikan
  empiris dalam audit ini: dry-run `DeployLocalTestStack` tanpa
  `--broadcast` menulis `.anvil-deployment.json` dengan alamat
  simulasi (§0). Jalur kode `run()` identik (cheatcode yang sama,
  setelah `stopBroadcast`, tanpa pembedaan simulasi vs broadcast —
  forge tidak menyediakan sinyal itu di dalam script).
- **Skenario:** setelah deploy testnet nyata + `RecordDeployment`
  (artefak 97.json berisi alamat + 6 tx hash), operator menjalankan
  dry-run `run()` lagi (mis. untuk menguji ulang, atau lupa
  `WRITE_DEPLOYMENT_ARTIFACT=false`) — artefak tertimpa alamat
  simulasi + 6 tx hash kosong. Kerugian: rekaman deployment rusak
  (dapat direkonstruksi dari `broadcast/…/run-latest.json` +
  `RecordDeployment`, selama broadcast artifact masih ada).
  Sub-kasus: env `WRITE_DEPLOYMENT_ARTIFACT=false` yang tertinggal
  dari sesi test membuat deploy nyata tidak tercatat sama sekali —
  tanpa peringatan.
- **Dampak:** integritas rekaman saja; nol dampak on-chain, nol dana.
- **Mitigasi SOP (sebelum smoke test):** (1) dokumentasikan —
  dry-run `run()` WAJIB dengan `WRITE_DEPLOYMENT_ARTIFACT=false`;
  (2) setelah broadcast nyata, verifikasi `deployments/97.json`
  terisi + jalankan `RecordDeployment` segera; (3) jangan jalankan
  dry-run `run()` di chain 97 setelah deploy nyata tanpa opt-out.
- **Perbaikan kode (opsional, bukan blocker):** `writeDeploymentArtifact`
  membaca artefak yang sudah ada (bila ada) dan mempertahankan tx hash
  non-kosong untuk alamat yang sama — pola merge-preserve yang sama
  dengan `RecordDeployment` `:70-76`. Atau: tulis artefak simulasi ke
  path berbeda — tidak dimungkinkan tanpa sinyal broadcast dari forge.

### PH9.1-F02 — Low — `RecordDeployment` mempercayai broadcast file fork

- **Lokasi:** `RecordDeployment.s.sol:133-171` (`_findTx` hanya
  mencocokkan `contractAddress` receipt, tanpa membedakan asal file).
- **Bukti:** perlindungan "hanya receipt yang dihitung" (`:21-23`)
  membedakan dry-run (receipts kosong) dari broadcast — tetapi
  broadcast ke **fork anvil chain 97 juga punya receipts** (status
  `0x1`). Ini analog langsung PH7-L20, yang mendokumentasikan artefak
  fork 97 dengan receipts yang terlihat seperti deployment nyata.
  Bila `run-latest.json` terakhir berasal dari broadcast fork
  (mis. operator menguji broadcast ke fork setelah deploy live, lalu
  menjalankan `RecordDeployment`), hash tx fork akan tercatat sebagai
  hash deployment live. `run-latest.json` selalu ditimpa tiap run,
  jadi urutan operasilah yang menentukan.
- **Dampak:** integritas rekaman saja; dapat diperbaiki dengan
  menjalankan ulang setelah broadcast live + verifikasi BscScan.
- **Mitigasi SOP (sebelum smoke test):** jalankan `RecordDeployment`
  segera setelah broadcast live, sebelum run fork/broadcast lain apa
  pun; verifikasi ≥1 tx hash di BscScan testnet sebelum artefak
  di-commit. **Perbaikan kode (opsional):** flag `--verify` opsional
  yang cross-check satu receipt via RPC (di luar cakupan "no RPC"
  script saat ini — keputusan desain, bukan keharusan).

### PH9.1-F03 — Low — `ProposeGrantVerifier` tanpa chain allowlist / guard `CONFIRM_*`

- **Lokasi:** `ProposeGrantVerifier.s.sol:67-82` (`run()` tidak
  memeriksa `block.chainid`; satu-satunya gerbang adalah
  `SCHEDULE=true`).
- **Bukti:** bandingkan `DeployAgentHub.run()` `:145-158` dan
  `DeployMock.run()` `:24-30` — keduanya punya allowlist chain +
  guard `CONFIRM_*`. ProposeGrantVerifier tidak punya keduanya.
  Skenario terburuk yang realistis: operator salah `--rpc-url`
  (mainnet vs testnet) + `SCHEDULE=true` + kunci yang memegang
  `PROPOSER_ROLE` di timelock yang dituju (`TIMELOCK_ADDRESS` salah
  ketik ke timelock lain) → proposal grant terjadwal di timelock yang
  salah. Dibatasi on-chain: hanya proposer yang bisa schedule (OZ
  `:273`), grant tidak efektif selama 2 hari, dan bisa di-cancel
  (`CANCELLER_ROLE`). Di setup produksi, proposer adalah Safe tanpa
  kunci, sehingga jalur broadcast script praktis tidak bisa dipakai
  sama sekali terhadap timelock produksi.
- **Dampak:** kesalahan operator yang reversibel dalam 2 hari; bukan
  jalur pencurian atau eskalasi privilege.
- **Rekomendasi:** tambahkan allowlist chain (56/97/31337 +
  `UnsupportedChain`) ke `run()`, dan pertimbangkan guard
  `CONFIRM_TESTNET_DEPLOY` untuk cabang schedule di chain 97 —
  konsistensi dengan standar M05. Satu-dua baris + test; sarankan
  sebelum smoke test, bukan blocker (gerbang `SCHEDULE=true` +
  enforcement on-chain sudah memadai untuk testnet).

### PH9.1-I01 — Info — 2 assert negatif deployer masih hilang

Lihat §1.5. Tambahkan cek `PROPOSER_ROLE`/`EXECUTOR_ROLE` negatif
untuk deployer di `_verifyWiring` (2 baris, melengkapi rekomendasi
Phase 9 §5.3). By-construction impossible; bukan blocker.

### PH9.1-I02 — Info — 7 env var baru tidak ada di `.env.example`

Lihat §8.3. Tambahkan `WRITE_DEPLOYMENT_ARTIFACT`, `CHAIN_ID`,
`TIMELOCK_ADDRESS`, `QUEST_MANAGER_ADDRESS`, `PROPOSAL_SALT`,
`SCHEDULE`, `PROPOSER_PRIVATE_KEY` ke `.env.example` dengan
placeholder kosong + catatan. Dokumen saja.

### PH9.1-I03 — Info — Komentar "32 checks" tidak presisi

Lihat §1.5. Perbaiki komentar `DeployAgentHub.s.sol:374-376`
("32 checks" hanya bila mock + verifier). Dokumen saja.

### PH9.1-I04 — Info — Forge menyimpan nilai sensitif di `cache/`

Lihat §8.3. `cache/` di-gitignore; higiene operator saja (deployer
khusus, didanai minimal).

### PH9.1-I05 — Info — Rekomendasi SOP D03 belum ditulis di dokumen mana pun

Lihat §7.3. Tambahkan satu baris ke checklist 03 §9 dan/atau
`docs/DEPLOYMENT_PLAN.md`: \_"deploy HANYA lewat `run()`; script apa
pun yang memanggil `deploy()` langsung wajib mereplikasi guard
`CONFIRM\__`"\*. Dokumen saja.

### Temuan Phase 7/9 yang dirujuk — status penutup

| Temuan                           | Status setelah audit ini                                         |
| -------------------------------- | ---------------------------------------------------------------- |
| PH7-L17 (CANCELLER_ROLE)         | **TERTUTUP** (§1.1); sisa I01 (Info)                             |
| PH7-L18 (artefak deployment)     | **TERTUTUP** untuk penulisan (§1.2, §3); sisa F01/F02 (Low, SOP) |
| PH7-L19 (helper timelock)        | **TERTUTUP** (§4.1-4.2); sisa F03 (Low)                          |
| PH7-M05 (guard testnet)          | **Tetap TERTUTUP** (§1.3, §2)                                    |
| PH7-M06 (chain guard test stack) | **Tetap TERTUTUP** (tidak berubah; test PASS)                    |
| PH9-D01 (admin ≠ creator)        | **Tetap TERTUTUP** (§1.4)                                        |
| PH9-D02 (guard DeployMock)       | **Tetap TERTUTUP** (§2)                                          |
| PH9-D03 (guard di `run()`)       | **Risiko residual TIDAK BERUBAH** (§7); sisa I05 (SOP)           |

## 11. Verdict keseluruhan

**Jalur deployment AMAN untuk dilanjutkan ke persetujuan user.**

Alasan:

1. Semua guard konfirmasi broadcast utuh dan fail-closed
   (DeployAgentHub + DeployMock, §9.4 terbukti menyeluruh).
2. Validasi Safe, pemisahan admin/creator, konfigurasi timelock, dan
   zero-privilege deployer semuanya ditegakkan di dalam `deploy()`
   dan diverifikasi deploy-time oleh `_verifyWiring` — termasuk
   CANCELLER_ROLE (L17) yang kini ditutup.
3. Dua script baru Phase 9.1 benar sesuai klaimnya: RecordDeployment
   murni file I/O tanpa broadcast/kunci; ProposeGrantVerifier
   preview-only secara default tanpa jalur direct-grant.
4. Tidak ada temuan Critical/High/Medium baru. Ketiga temuan Low
   (F01–F03) menyentuh integritas rekaman dan konsistensi
   defense-in-depth — bukan dana, kunci, atau otoritas — dan
   masing-masing punya mitigasi SOP yang murah.

**Syarat yang tersisa sebelum smoke test** (tidak ada yang
memblokir persetujuan user — semuanya SOP/dokumen, tanpa perubahan
kontrak):

1. **SOP artefak (F01+F02):** dry-run `run()` wajib
   `WRITE_DEPLOYMENT_ARTIFACT=false`; `RecordDeployment` dijalankan
   segera setelah broadcast live + verifikasi ≥1 tx hash di BscScan
   sebelum artefak di-commit. (Satu paragraf di checklist 03.)
2. **SOP D03 (I05):** satu baris larangan wrapper `deploy()`
   langsung di checklist 03 §9 / DEPLOYMENT_PLAN.md.
3. **Disarankan (bukan syarat):** tutup F03 dengan allowlist chain di
   ProposeGrantVerifier (1–2 baris + test); lengkapi I01 (2 assert);
   tambahkan 7 env var ke `.env.example` (I02); perbaiki komentar
   "32 checks" (I03).
4. **Syarat eksternal yang tidak berubah dari Phase 9:** 8 input user
   - persetujuan broadcast eksplisit tetap menjadi gate terakhir;
     mainnet tetap NO-GO; R-010 tetap IMPLEMENTED, belum CLOSED.

## Lampiran — perintah & bukti yang dijalankan

```bash
# HEAD + status (tidak ada file ter-track yang diubah audit ini)
git log --oneline -8            # HEAD 0313922
git status --short              # hanya direktori laporan untracked

# Inventaris broadcast + script (lengkap, §9)
grep -rn "startBroadcast\|vm.broadcast" packages/contracts/script/ --include="*.sol"
grep -rn "is Script" --include="*.sol" packages/ apps/ | grep -v "/lib/"
grep -rn -- "--broadcast" packages/ apps/ .github/ docs/   # + filter out/, broadcast/, cache/

# Pemanggil deploy()/scheduleGrant() (hanya test, §7)
grep -rn "\.deploy(\|scheduleGrant" packages/contracts/test packages/contracts/script

# Env var lengkap (§8.3)
grep -hn "vm\.env[A-Za-z]*(" packages/contracts/script/*.sol

# Test suite terkait script (67/67 PASS)
forge test --match-contract "DeployScriptTest|DeploymentArtifactTest|ProposeGrantVerifierTest|SafeValidationTest"

# Bukti empiris F01: dry-run menulis file (§0, §10)
anvil --port 8545 &
forge script script/DeployLocalTestStack.s.sol:DeployLocalTestStack --rpc-url http://127.0.0.1:8545
# → .anvil-deployment.json TERTULIS dengan alamat simulasi (tanpa --broadcast)
# Artefak percobaan dibersihkan (file + cache/DeployLocalTestStack.s.sol).

# Konfirmasi OZ (vendored)
grep -n "CANCELLER_ROLE\|_grantRole\|onlyRole" \
  packages/contracts/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol
# ctor: :117 self-admin, :126-127 proposer+canceller, :132 executor;
# schedule :273 onlyRole(PROPOSER_ROLE); cancel :334 onlyRole(CANCELLER_ROLE).
```

**Batasan audit:** (1) konstanta kanonis Safe (singleton + codehash)
mengandalkan verifikasi dua-arah Phase 1 — tidak diulang on-chain
karena tidak ada alamat Safe testnet yang diketahui untuk
dibandingkan (§5); (2) perilaku forge yang dirujuk (probe I,
penulisan cheatcode saat simulasi) diverifikasi dari dokumentasi
Phase 9 + satu eksperimen dry-run dalam audit ini, bukan dari
audit atas kode forge sendiri; (3) tidak ada broadcast live yang
dilakukan — semua kesimpulan soal perilaku broadcast berasal dari
source + eksperimen lokal.
