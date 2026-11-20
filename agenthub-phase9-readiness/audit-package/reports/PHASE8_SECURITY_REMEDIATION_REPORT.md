# AGENTHUB — Phase 8: Critical Security Remediation Report

**Tanggal:** 20 November 2026.
**Baseline:** `5723ff3` (Phase 6 + Phase 7 review).
**HEAD akhir:** _(diisi setelah commit — lihat §12)_.
**Laporan acuan:** `agenthub-phase7-review/PHASE7_INDEPENDENT_SECURITY_REVIEW.md`
(59 temuan), `agenthub-phase6-threshold/PHASE6_THRESHOLD_IMPLEMENTATION_REPORT.md`,
`agenthub-next-phase-validation/THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md`.
**Metode:** 5 workstream (4 implementasi paralel + 1 battery regresi),
ditambah perbaikan koordinator atas 1 regresi build yang ditemukan battery
(TS2589 — lihat §9). Tidak ada deploy, tidak ada broadcast, tidak ada
private key yang dipakai. Tidak ada tes yang dihapus; tidak ada assertion
yang dilemahkan (bukti §5.7).

## 1. Keputusan

**CONDITIONAL GO untuk validasi live BNB Testnet. NO-GO untuk mainnet.**

**Alasan GO testnet (bersyarat):** seluruh blocker testnet dari Phase 7
§11 sudah ditutup dengan bukti — PH7-M05, M06, M04 (syarat testnet
eksplisit), ditambah seluruh blocker mainnet berkode P0/P1 dalam ruang
lingkup fase ini (H01, M01, M02, M03, M07, M08, M09, L05, L07, L10,
L13, M10). Seluruh battery regresi hijau pada state final, termasuk
suite yang sempat gagal selama fase ini (typecheck/build — §9) dan
difokuskan ulang sampai hijau. Yang tersisa sebelum broadcast hanyalah
faktor eksternal: 8 input deployment dari user + persetujuan broadcast
eksplisit (§11).

**Alasan NO-GO mainnet:** external review (R-012) belum dikomisikan;
wallet-app nyata belum pernah diuji (O4); ≥ 3 verifier belum di-grant;
keputusan review-window / alur dua langkah untuk quest bernilai besar
(PH7-M03, bagian prosedural) belum diambil; PH7-L01 diterima dengan
bukti tetapi tanpa cap on-chain; temuan Low/Info sisanya (§3) belum
didiposisi formal untuk mainnet.

**R-010: IMPLEMENTED, belum CLOSED.** Tidak berubah oleh fase ini —
penutupan membutuhkan live testnet smoke test yang belum terjadi
(§11).

## 2. Temuan yang ditutup

**14 temuan Phase 7 ditutup dengan bukti** (1 High, 9 Medium, 4 Low),
plus 1 Info (bonus) dan 1 temuan diterima dengan bukti (L01). Setiap
penutupan merujuk ke test atau artefak yang dapat dijalankan ulang.

| ID      | Severity | Perbaikan                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Bukti penutupan                                                                                                                                                                                           |
| ------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PH7-H01 | High     | Validasi on-chain di `createQuest`: quest Attested dengan `rewardPoints > 1.000` wajib `attestationThreshold ≥ 2`. Kode persis dari user, diterapkan kata-per-kata (konstanta ditulis `1_000` sesuai konvensi literal file — nilai sama; didokumentasikan di NatSpec). Error memakai ulang `InsufficientAttestations(threshold, 2)`.                                                                                                                                                                                                                             | `test/PolicyEnforcement.t.sol`: 1.001/T1 revert; 1.001/T2 sukses; 1.000/T1 sukses; 10.000/T1 revert; 10.000/T3 sukses                                                                                     |
| PH7-M01 | Medium   | Guardrail revoke verifier on-chain: override `_grantRole`/`_revokeRole` memelihara `verifierCount`; counter quest Attested aktif per level threshold; `highestLiveThreshold()` diturunkan dari counter; revoke (termasuk `renounceRole`) ditolak bila `verifierCount − 1 < highestLiveThreshold` (`RevocationWouldBrickQuest`); `createQuest` Attested ditolak bila `verifierCount < threshold` (`InsufficientVerifiers`). Quest kedaluwarsa-tetapi-aktif tetap terhitung (fail-safe, terdokumentasi + ditest).                                                  | `test/VerifierGuardrail.t.sol` (11 test): revoke terblokir saat quest T2 live; revoke sukses setelah deactivate; create T3 ditolak saat verifier hanya 1; re-grant memulihkan; renounce tunduk pada guard |
| PH7-M02 | Medium   | Kategori high-value badge di kode: `Badge.highValue` (bool) + `setBadgeHighValue(badgeId, bool)` (BADGE_MANAGER_ROLE, hanya badge defined) + `isBadgeHighValue` (false untuk 0/tidak defined, tidak pernah revert). `createQuest` menolak threshold 1 bila badge high-value. Desain: setter mutable, bukan parameter `defineBadge` — klasifikasi nilai badge dapat berubah sepanjang hidupnya dan badge lama harus bisa diklasifikasi tanpa redefinisi; flag hanya dibaca saat creation, jadi re-flagging tidak mengubah threshold quest live (dibuktikan test). | `test/PolicyEnforcement.t.sol`: badge high-value + T1 revert; + T2 sukses; badge biasa + T1 sukses; re-flagging tidak mengubah quest live                                                                 |
| PH7-M03 | Medium   | `QUEST_CREATOR` wajib Safe multisig tervalidasi: `DeployAgentHub` memvalidasi `params.questCreator` dengan helper `SafeValidation.validate` yang SAMA dengan `adminMultisig` (kanonis di 56/97, eksplisit di 31337), fail-closed sebelum CREATE apa pun. Checklist §1 item 4 + §3 + `DEPLOYMENT_PLAN.md` + `ROLE_MATRIX.md` diperbarui (creator Safe threshold ≥ 2, distinct dari admin). Bagian review-window / alur dua langkah TETAP TERBUKA (§3).                                                                                                            | `test/DeployScript.t.sol`: EOA creator revert; kontrak non-Safe revert; Safe threshold-1 revert; Safe 2-of-3/3-of-3 sukses (testnet + local)                                                              |
| PH7-M04 | Medium   | Ownership MockAgentId ditransfer ke adminMultisig di akhir `deploy()` (script tidak pernah mint, jadi transfer langsung); `_verifyWiring` memeriksa `mock.owner() == adminMultisig` (cek ke-30). Klaim "deployer ends with ZERO privileges" kini benar harfiah. Checklist §5.1: mint test Agent ID lewat Safe.                                                                                                                                                                                                                                                   | Assert `mock.owner() == multisig` di `DeployScriptTest` + `PauserRoleTest`                                                                                                                                |
| PH7-M05 | Medium   | Guard `CONFIRM_TESTNET_DEPLOY=true` wajib di chain 97, simetris persis dengan guard mainnet (`TestnetDeployNotConfirmed`). Berlaku juga untuk dry-run (guard tidak bisa membedakan simulasi dari broadcast — sama seperti guard mainnet; didokumentasikan). `.env.example` + checklist §4.2 + `DEPLOYMENT_PLAN.md` §3 diperbarui.                                                                                                                                                                                                                                | Skenario `run()` testnet: tanpa env → revert; dengan env=true → deploy                                                                                                                                    |
| PH7-M06 | Medium   | `DeployLocalTestStack.run()` diawali `require(block.chainid == 31337, "DeployLocalTestStack: local Anvil only")`. Diverifikasi juga: script sudah meng-grant kedua verifier SEBELUM membuat quest threshold-2 (syarat guard M01) — tidak perlu perbaikan urutan.                                                                                                                                                                                                                                                                                                 | `test_LocalTestStackRejectsTestnetChain` + `test_LocalTestStackRejectsMainnetChain` (keduanya revert)                                                                                                     |
| PH7-M07 | Medium   | Deep-equal ABI parity kini BERJALAN di CI: job `web` mendapat `foundry-toolchain` + `forge build` sebelum vitest (checkout + `submodules: recursive`); timeout job 15 → 20 menit (build via-IR ~5 menit + setup ~1 menit). Dipilih atas pendekatan artefak antar-job agar job tetap independen dan pipeline tidak terserialisasi (trade-off didokumentasikan di ci.yml).                                                                                                                                                                                         | `ci.yml` terverifikasi (YAML valid); deep-equal 4/4 berjalan lokal dengan `out/` tersedia (log 04b); CI run §8                                                                                            |
| PH7-M08 | Medium   | `abi-parity.test.ts` diperluas dari hanya QuestManager ke KEEMPAT kontrak (satu deep-equal per kontrak, skip independen per kontrak).                                                                                                                                                                                                                                                                                                                                                                                                                            | 8/8 test parity lulus (4 structural + 4 deep-equal)                                                                                                                                                       |
| PH7-M09 | Medium   | Test vitest membandingkan kelima string `EVENT_SIGNATURES` dengan tanda tangan kanonis yang dibangun dari ABI yang di-commit (tanpa perlu `out/`); gagal bila ada drift nama/type/urutan/`indexed`. Pendekatan test-based (bukan derive runtime) agar modul `events.ts` tidak menarik ABI penuh dan bentuk publiknya tidak berubah.                                                                                                                                                                                                                              | 6 test paritas event lulus; kontrol negatif: hapus `indexed` dari `questId` → persis 1 test gagal, lalu dikembalikan                                                                                      |
| PH7-M10 | Medium   | Errata ditambahkan ke laporan Phase 6 (§Errata, E1/E2/E4/E6) + catatan koreksi di `NEXT_PHASE_VALIDATION.md`; teks asli tidak diubah. Koreksi utama: MCOPY baseline adalah false positive hash metadata IPFS; 0 opcode Cancun-only di kedua build.                                                                                                                                                                                                                                                                                                               | File errata di-commit; klaim opcode kini dibuktikan ulang dengan scanner metadata-aware (§7)                                                                                                              |
| PH7-L05 | Low      | Cek `provided < threshold` dipindah ke segera setelah cek batas array/deadline, SEBELUM digest dan loop recovery. Nuansa (didokumentasikan di kode): untuk array under-threshold yang berisi signature junk, revert berubah dari recovery error menjadi `InsufficientAttestations` (diagnosis lebih akurat); hasil tidak berubah.                                                                                                                                                                                                                                | Seluruh suite attestation hijau tanpa perubahan assertion                                                                                                                                                 |
| PH7-L07 | Low      | Mekanisme `supersedes` diimplementasikan: `setSupersedes(newQuestId, oldQuestId)` (admin-only, keduanya harus ada, tanpa self-link), getter `supersedes()`, event `QuestSuperseded`, guard completion `AlreadyCompletedSupersededQuest`. Single-hop by design (untuk rantai recreate, tautkan ke quest yang punya completion); tanpa fungsi clear (fail-safe).                                                                                                                                                                                                   | Skenario PoC Phase 7 direproduksi sebagai test: Alice terblokir di 100 poin, Bob tetap bisa menyelesaikan                                                                                                 |
| PH7-L10 | Low      | Test kebijakan threshold kini ada (lihat PH7-H01/M02 di atas) dan menjadi bagian gate CI.                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | `test/PolicyEnforcement.t.sol` (16 test)                                                                                                                                                                  |
| PH7-L13 | Low      | Upgrade solc 0.8.24 → **0.8.39** (bukan 0.8.38 — 0.8.38 masih terpapar bug medium SOL-2026-8; 0.8.39 nol bug diketahui di daftar resmi). Menutup `YulOptimizerKnowledgeBaseStaleBookkeeping` + 5 bug lain yang memengaruhi 0.8.24. Regresi penuh pada 0.8.39 (§5).                                                                                                                                                                                                                                                                                               | `agenthub-phase8-remediation/solc-evaluation.md` (482 baris): build/test/fuzz hijau di 0.8.39, analisis bug compiler, perbandingan bytecode                                                               |
| PH7-L15 | Low      | `.env.example` dilengkapi (`CONFIRM_TESTNET_DEPLOY`, `CONFIRM_MAINNET_DEPLOY`, `AGENT_ID_ADDRESS`, `SAFE_SINGLETON`, `SAFE_PROXY_CODEHASH`); instruksi header diperbaiki (forge hanya memuat `.env` di `packages/contracts/`, bukan `.env.local`).                                                                                                                                                                                                                                                                                                               | File di-commit                                                                                                                                                                                            |
| PH7-L16 | Low      | Hitungan wiring diperbaiki di dokumen: 12 wiring CALL (13 dengan `VERIFIER`) karena transferOwnership M04; 18 transaksi total dengan verifier.                                                                                                                                                                                                                                                                                                                                                                                                                   | Checklist §4.1 + `DEPLOYMENT_PLAN.md` §5                                                                                                                                                                  |
| PH7-I09 | Info     | Mode `export-abis.mjs --check` (regenerasi di memori, exit non-zero + pesan jelas bila drift, tanpa menulis) + assert versi solc dari metadata artefak vs pin `foundry.toml` (dibaca runtime, tanpa duplikasi konstanta). `--check` berjalan di CI setelah `forge build`.                                                                                                                                                                                                                                                                                        | Uji positif (tree bersih → exit 0) + negatif (utak-atik ABI → exit 1 menyebut file); mode default byte-identik                                                                                            |

### Diterima dengan bukti (bukan ditutup oleh kode)

| ID      | Keputusan + bukti                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PH7-L01 | **DITERIMA.** Angka cap berapa pun adalah kebijakan arbitrer, bukan keamanan, dan membutuhkan jalur reset governance plus risiko memblokir kampanye sah. Bukti penerimaan: role creator tepercaya (multisig kampanye di produksi — kini ditegakkan PH7-M03); seluruh emisi bersifat publik dan lonjakan completion sudah menjadi sinyal monitoring (SOP §8); deactivate + pause membatasi jendela kerusakan. Justifikasi AR-3 diperbaiki di threat model (cap per-quest ≠ cap total) dan didokumentasikan di `QUEST_VALIDATION_DESIGN.md` §5. |

## 3. Temuan yang masih terbuka

Tidak ada lagi temuan High atau Medium yang terbuka dari daftar P0/P1
fase ini. Sisa terbuka di bawah ini adalah temuan Low/Info yang
disengaja ditunda (di luar ruang lingkup Phase 8) atau bagian
prosedural/operasional yang membutuhkan keputusan manusia, external
review, atau chain live.

| ID                               | Status / alasan                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PH7-M03 (bagian prosedural)      | Review window / alur dua langkah untuk quest bernilai besar belum diputuskan. Penegakan Safe (bagian kode) SUDAH ditutup (§2). Keputusan ada di tim: terima risiko dengan rem deactivate+pause, atau implementasikan review window sebelum mainnet.                                                                                                                                                                                                                       |
| PH7-L02                          | Kopling pause asimetris — dokumentasi runbook belum ditulis. Perilaku terbukti benar; hanya dokumentasi yang kurang.                                                                                                                                                                                                                                                                                                                                                      |
| PH7-L03                          | TOCTOU sisi grant — mitigasi SOP (jeda re-grant 7 hari) belum ditulis ke SOP.                                                                                                                                                                                                                                                                                                                                                                                             |
| PH7-L04                          | Perilaku validator berubah pasca-approval — SOP approval + pencatatan codehash belum diterapkan.                                                                                                                                                                                                                                                                                                                                                                          |
| PH7-L06                          | Nonce global per akun — batasan UX yang didokumentasikan; perbaikan (nonce per quest) adalah perubahan desain, ditunda ke diskusi desain.                                                                                                                                                                                                                                                                                                                                 |
| PH7-L08 / PH7-I07                | Threshold disimpan tapi tidak ditegakkan untuk quest non-Attested — KEPUTUSAN DESAIN eksplisit Phase 8 (kebijakan hanya bermakna untuk Attested; memaksakan threshold 2 pada CheckIn/OnChain adalah teater karena tidak pernah ditegakkan saat completion). Ditest (CheckIn 10.000 poin T1 sukses). Dokumentasi `IQuestManager.Quest` mencatat ruang lingkup ini.                                                                                                         |
| PH7-L09                          | Tanpa UI pembuatan quest — tidak ada lapisan pertahanan sisi manusia sampai UI dibangun; pemeriksaan kebijakan fail-closed pada skrip pembuatan quest tim belum ditambahkan.                                                                                                                                                                                                                                                                                              |
| PH7-L11                          | `anvil-integration.mjs` membaca ABI dari `out/`, bukan `lib/abis/` — drift pada ABI yang di-commit tidak tertangkap anvil (ditangkap parity test + `--check`). Perbaikan skrip ditunda.                                                                                                                                                                                                                                                                                   |
| PH7-L12                          | ABI inline + konstanta EIP-712 tersebar di 6 tempat — sentralisasi belum dilakukan (status saat ini: semua cocok).                                                                                                                                                                                                                                                                                                                                                        |
| PH7-L14                          | Tanpa `[rpc_endpoints]` di `foundry.toml` — perbaikan kenyamanan operator, ditunda.                                                                                                                                                                                                                                                                                                                                                                                       |
| PH7-L17                          | `_verifyWiring` tidak memeriksa `CANCELLER_ROLE` — asersi hilang (state on-chain benar). Satu baris; ditunda ke fase berikutnya.                                                                                                                                                                                                                                                                                                                                          |
| PH7-L18                          | Deploy script tidak menulis artefak JSON — pencatatan alamat masih manual.                                                                                                                                                                                                                                                                                                                                                                                                |
| PH7-L19                          | Tanpa helper proposal timelock pasca-deploy — grant verifier ke-2/ke-3 masih manual via Safe UI/`cast`. Relevan untuk smoke test (verifier ke-2 via timelock).                                                                                                                                                                                                                                                                                                            |
| PH7-L20                          | Artefak broadcast fork chain 97 yang basi — belum dibersihkan/dilabeli.                                                                                                                                                                                                                                                                                                                                                                                                   |
| PH7-L21                          | `AGENT_ID_ADDRESS` di-supply di chain 97 tidak divalidasi — jalur default (mock) aman; validasi variabel opsional belum ditambahkan.                                                                                                                                                                                                                                                                                                                                      |
| PH7-L22                          | Verifikasi BscScan manual kekurangan tabel constructor args — jalur otomatis sudah benar; tabel manual belum ditulis.                                                                                                                                                                                                                                                                                                                                                     |
| PH7-L23                          | 3 prasyarat operasional tersembunyi (URL RPC teruji, Safe sudah dibuat, dompet uji didanai) belum ditambahkan ke checklist §1.                                                                                                                                                                                                                                                                                                                                            |
| PH7-L24, L26, L28, L29, L30, L31 | Akurasi bukti/dokumentasi historis Phase 6 (warning lint, provenance JSON, path log, log duplikat). Errata Phase 8 mencakup E1/E2/E4/E6; sisanya (E3/E7/E8 + L30/L31) tetap sebagai catatan — tidak satu pun memengaruhi keamanan material. Catatan: run OSV Phase 8 masih menulis JSON ke path hardcoded lama (PH7-L30) — salinan benar ada di `test-results/osv-audit-phase8.json`.                                                                                     |
| PH7-I01–I08, I10–I17             | Informational — tidak ada tindakan wajib; dicatat: I02 (komentar NatSpec), I03 (deactivate permanen), I04 (event tanpa threshold), I05 (Slither app-only sudah ditelaah), I06 (replay fork chainId sama — accepted risk), I08 (AGENT_ID_ABI), I10 (angka opcode — bukti Phase 8 memakai angka kanonik), I11 (waktu build legacy — dikoreksi via errata E4), I12 (QuestManager kini 53,32% batas — pemeriksaan ukuran di CI belum ditambahkan), I13–I16 (deployment Info). |
| O4                               | Wallet-app nyata belum pernah diuji (wagmi hanya `injected()`, tanpa WalletConnect) — ditutup saat validasi testnet live.                                                                                                                                                                                                                                                                                                                                                 |
| R-012                            | External security review belum dikomisikan — wajib sebelum mainnet.                                                                                                                                                                                                                                                                                                                                                                                                       |
| —                                | ≥ 3 verifier sebelum quest threshold-2 pertama di mainnet — operasional, saat deploy.                                                                                                                                                                                                                                                                                                                                                                                     |

## 4. File yang berubah

**37 file berubah + 2 file test baru + direktori `agenthub-phase8-remediation/`
baru** (laporan ini, evaluasi solc, 25 file log/skrip, 3 test-results).
Diff: **+1.946 / −197** (belum termasuk laporan ini dan manifest).
`agenthub-phase7-review/` tetap untracked (keputusan parent agent —
bukan bagian commit fase ini).

| Kelompok                    | File                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Kontrak                     | `packages/contracts/src/QuestManager.sol` (+175), `src/Achievement.sol` (+23), `src/interfaces/IQuestManager.sol` (+78), `src/interfaces/IAchievement.sol` (+26)                                                                                                                                                                                                                                                                                                                                                                                     |
| Test Foundry (baru)         | `test/PolicyEnforcement.t.sol` (16 test), `test/VerifierGuardrail.t.sol` (11 test)                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Test Foundry (diperbarui)   | `test/Attestation.t.sol`, `test/ThresholdAttestation.t.sol`, `test/QuestManager.t.sol` (setup grant verifier; tidak ada assertion dilemahkan), `test/DeployScript.t.sol` (+7 test), `test/PauserRole.t.sol`                                                                                                                                                                                                                                                                                                                                          |
| Deploy script               | `script/DeployAgentHub.s.sol` (M03/M04/M05), `script/DeployLocalTestStack.s.sol` (M06), `script/export-abis.mjs` (`--check` + assert solc)                                                                                                                                                                                                                                                                                                                                                                                                           |
| Konfigurasi                 | `packages/contracts/foundry.toml` (solc 0.8.39 + komentar MCOPY), `.env.example`, `.github/workflows/ci.yml` (forge build di job web, timeout 20 menit)                                                                                                                                                                                                                                                                                                                                                                                              |
| Frontend                    | `apps/web/lib/abis/QuestManager.ts` + `Achievement.ts` (regen, +13 entri, 0 dihapus/diubah), `lib/contracts.ts` (`QUEST_MANAGER_READ_ABI` — §9), `hooks/useQuests.ts` (memakai ABI minimal), `hooks/hooks.test.tsx` (mock +1 ekspor), `lib/abis/abi-parity.test.ts` (4 kontrak + subset test), `lib/events.test.ts` (paritas event)                                                                                                                                                                                                                  |
| Dokumen                     | `docs/VERIFIER_ROLE_SOP.md`, `docs/QUEST_VALIDATION_DESIGN.md`, `docs/SECURITY_THREAT_MODEL.md` (AR-3 + versi solc), `docs/SECURITY_TEST_PLAN.md`, `docs/SECURITY_FINDINGS.md`, `docs/DEPLOYMENT.md`, `docs/DEPLOYMENT_PLAN.md`, `docs/ROLE_MATRIX.md`, `agenthub-final-pretestnet/VERIFIER_SECURITY_SOP.md`, `agenthub-final-pretestnet/FINAL_DEPLOYMENT_CHECKLIST.md` (§1/§3/§4/§5.1/§7), `agenthub-phase6-threshold/PHASE6_THRESHOLD_IMPLEMENTATION_REPORT.md` (errata), `agenthub-next-phase-validation/NEXT_PHASE_VALIDATION.md` (errata MCOPY) |
| Log E2E (di-refresh runner) | `agenthub-final-pretestnet/logs/phase8-e2e-smoke.log`, `agenthub-final-release/logs/phase-f-wallet-e2e.log` (run hijau terbaru — praktik yang sama seperti Phase 6)                                                                                                                                                                                                                                                                                                                                                                                  |
| Bukti Phase 8               | `agenthub-phase8-remediation/` (laporan ini, `solc-evaluation.md`, `logs/` 01–21 + `phase8-bytecode-audit.py`, `test-results/`)                                                                                                                                                                                                                                                                                                                                                                                                                      |

## 5. Bukti pengujian

Battery dijalankan 20 November 2026, 06:40–07:10 WIB, pada working
tree final (kode Phase 8 + solc 0.8.39), berurutan. Log mentah di
`agenthub-phase8-remediation/logs/`. Worker battery (E) sempat
terhenti oleh restart runtime di tengah langkah terakhir
(perbandingan bytecode) — seluruh suite 01–17 sudah selesai dan
log-nya utuh; koordinator menyelesaikan perbandingan bytecode,
memperbaiki 1 regresi build yang ditemukan battery (TS2589, §9),
dan menjalankan ulang typecheck/vitest/build/E2E sampai hijau
(log 08b, 09, 10, 19, 20, 21).

| Suite                               |             Baseline (5723ff3) |                                         Phase 8 final | Verdict        |
| ----------------------------------- | -----------------------------: | ----------------------------------------------------: | -------------- |
| `forge build` (via-IR, solc 0.8.39) |                         exit 0 |          **exit 0** (artefak: 0.8.39+commit.ce47f2c8) | HIJAU          |
| Foundry tests                       |             287/287 (20 suite) |                                **321/321 (22 suite)** | +34            |
| Fuzz 10.000 runs, seed 42           |                        287/287 |                                           **321/321** | +34            |
| Vitest web                          |             159 + 5 skip (164) |                                **173 + 5 skip (178)** | +14            |
| Vitest shared                       |                            8/8 |                                               **8/8** | SAMA           |
| TypeScript (web + shared)           |                         exit 0 |                     **exit 0** (setelah perbaikan §9) | HIJAU          |
| Lint (web + shared)                 |                         exit 0 |                                            **exit 0** | HIJAU          |
| Production build Next.js            | exit 0, 8 route + `_not-found` |      **exit 0, 8 route + `_not-found`, semua statis** | HIJAU          |
| Prettier + `forge fmt`              |                         exit 0 |                                            **exit 0** | HIJAU          |
| E2E smoke                           |                          23/23 |                            **23/23**, 0 console error | SAMA           |
| Wallet E2E                          |                          26/26 |                            **26/26**, 0 console error | SAMA           |
| Anvil integration                   |                    30/30 + 5/5 |                                       **30/30 + 5/5** | SAMA           |
| Slither app-only                    |               exit 0, 12 hasil | **exit 0, 13 hasil: 0 High, 0 Medium, 4 Low, 9 Info** | +1 Info (§5.6) |
| OSV audit                           |                7 (0C/0H/6M/1L) |                      **7 (0C/0H/6M/1L)**, set identik | SAMA           |
| Gitleaks full history               |            0 leak (100 commit) |                               **0 leak (100 commit)** | SAMA           |
| `export-abis --check`               |                       — (baru) |      **exit 0** — keempat ABI cocok dengan regenerasi | BARU           |
| ABI parity deep-equal               |         1 kontrak (skip di CI) |             **4/4 kontrak, berjalan** + 5 test subset | BARU           |

### 5.1 Foundry — 321/321 (22 suite)

Total = 287 baseline + 27 test kontrak baru (16 PolicyEnforcement +
11 VerifierGuardrail) + 7 test deploy baru (DeployScript/PauserRole).
Fuzz dengan perintah persis CI (`--fuzz-runs 10000 --fuzz-seed 42`):
321/321, 0 gagal, 0 skip. Log: `02-forge-test.log`,
`03-forge-fuzz.log`.

### 5.2 Policy enforcement — skenario kunci (semua hijau)

Reward 1.001/T1 revert; 1.001/T2 sukses; 1.000/T1 sukses; 10.000/T1
revert; 10.000/T3 sukses; badge high-value + T1 revert; badge
high-value + T2 sukses; badge biasa + T1 sukses; CheckIn 10.000 poin
T1 sukses (kebijakan hanya Attested — keputusan desain §3);
threshold 0/4 tetap revert. Threshold 1/2/3 completion, duplicate
signer, replay, deadline, dan revocation/recovery semuanya hijau
(suite ThresholdAttestation + Attestation + VerifierGuardrail).

### 5.3 Vitest web — 173 + 5 skip (178)

+14 test baru: +3 deep-equal ABI (M08), +6 paritas event (M09), +5
subset ABI minimal (§9). 5 skip adalah test anvil-integration (butuh
`ANVIL_DEPLOYMENT`), sama seperti baseline. Log: `20-vitest-rerun.log`.

### 5.4 E2E + Anvil

E2E smoke 23/23, wallet E2E 26/26 (threshold-2 end-to-end, poin bob
150), anvil 30/30 cek node + 5/5 vitest — semuanya 0 console error.
Log: `09-e2e-smoke.log`, `10-wallet-e2e.log`,
`11-anvil-integration.log`.

### 5.5 OSV + Gitleaks

OSV: 7 temuan (6 Moderate, 1 Low), 0 High/Critical; set identik
persis dengan Phase 6/7 (960 paket). Gitleaks: 0 leak, 100 commit
dipindai. Log: `13-osv.log`, `14-gitleaks.log`,
`test-results/osv-audit-phase8.json`.

### 5.6 Slither — 13 hasil, 0 High/Medium (gate exit 0)

Rincian: 4 Low (`timestamp` — perbandingan `block.timestamp` untuk
jendela berskala hari/menit, sudah ditelaah Phase 7) + 9 Info
(`assembly` ×3, `low-level-calls` ×3, `cyclomatic-complexity` ×2,
`pragma` ×1). Satu Info BARU vs Phase 7: `cyclomatic-complexity`
pada `createQuest` — guard H01/M01/M02 yang ditambahkan mendorong
kompleksitasnya melewati ambang detektor. Ini benign (rangkaian
linear guard clause yang masing-masing ditest — pola yang sama
dengan `completeQuest` yang sudah dicatat di `SECURITY_FINDINGS.md`).
Dua temuan lama hanya berpindah nomor baris karena kode bertambah.
Log: `12-slither.log`, `test-results/slither-phase8.json`.

### 5.7 Tidak ada tes yang dihapus, tidak ada assertion yang dilemahkan

Jumlah test per suite lama sama atau lebih besar dari baseline;
total Foundry naik 287 → 321 dan Vitest web naik 164 → 178 semata
dari penambahan. Tiga test lama diperbarui ke semantik baru TANPA
melemahkan assertion: (a) test revoke di `ThresholdAttestation.t.sol`
kini deactivate-dulu — assertion lama (verifier tercabut
menginvalidasi pasangan) tetap terbukti lewat jalur itu; (b) test
rotasi di `Attestation.t.sol` kini grant-dulu; (c) `setUp`
`QuestManager.t.sol` meng-grant 1 verifier (syarat guard M01).

## 6. Gas benchmark

Metode: sama dengan Phase 6/7 — pengukuran `gasleft()` di
`test/ThresholdAttestation.t.sol`, perintah
`forge test --match-test testGas -vv`. Log mentah:
`logs/16-gas-benchmark.log`; analisis lengkap:
`test-results/gas-benchmark-phase8.md`.

| Pengukuran                          | Phase 6 (0.8.24, kode lama) | Kode Phase 8 @ 0.8.24 | **Phase 8 final (kode Phase 8 @ 0.8.39)** |    Δ vs Phase 6 |
| ----------------------------------- | --------------------------: | --------------------: | ----------------------------------------: | --------------: |
| Threshold-1 completion              |                     242.735 |               244.966 |                               **244.840** | +2.105 (+0,87%) |
| Threshold-2 completion              |                     253.867 |               256.098 |                               **255.766** | +1.899 (+0,75%) |
| Threshold-3 completion              |                     265.221 |               267.452 |                               **266.911** | +1.690 (+0,64%) |
| Marginal / signature ekstra (T2−T1) |                      11.132 |                11.132 |                                **10.926** |            −206 |
| Marginal / signature ekstra (T3−T2) |                      11.354 |                11.354 |                                **11.145** |            −209 |

Cross-check dalam test marginal pada run yang sama: 244.840 /
255.767 / 266.919 (selisih ≤ 8 gas vs test individual — artefak
setup yang sama seperti Phase 7, bukan anomali).

### Dekomposisi delta

| Komponen                              |     T1 |     T2 |     T3 | Keterangan                       |
| ------------------------------------- | -----: | -----: | -----: | -------------------------------- |
| Efek kode Phase 8 (solc tetap 0.8.24) | +2.231 | +2.231 | +2.231 | Konstan di semua threshold       |
| Efek solc 0.8.39 (kode tetap Phase 8) |   −126 |   −332 |   −541 | Membesar dengan jumlah signature |
| Net vs Phase 6                        | +2.105 | +1.899 | +1.690 |                                  |

**Efek kode (+2.231, konstan):** satu SLOAD dingin guard L07 di
`_completeQuest` (baca `_supersedes[questId]`) — biaya keamanan yang
disengaja dan terdokumentasi di kode. Perbaikan H01/M01/M02 tidak
menyentuh jalur completion (cek di `createQuest` / revoke), jadi
tidak ada biaya gas completion dari ketiganya. **Efek solc
(negatif):** codegen ≥0.8.25 memakai MCOPY untuk penyalinan array
`bytes[]` (penghematan membesar dengan array) + dispatcher IR yang
lebih pendek — sejalan dengan pengukuran murni-solc Worker D
(−161/−385/−612 pada kode lama). **Kesimpulan:** kenaikan bersih
+0,64–0,87% seluruhnya berasal dari guard L07; tidak ada regresi gas
tak terduga; seluruh completion tetap jauh di bawah batas 300.000
gas yang di-assert test.

## 7. Perbandingan bytecode + opcode scan

Metode: scanner metadata-aware (`logs/phase8-bytecode-audit.py`) —
metadata CBOR dipotong sebelum disassembly; byte di dalam PUSH tidak
dihitung sebagai opcode (metode ini yang membuktikan klaim MCOPY
Phase 5/6 adalah false positive). Baseline dibangun ulang dari
worktree bersih HEAD 5723ff3; keempat hash SHA-256 baseline COCOK
dengan hash yang diterbitkan Phase 7 (reproduksi terverifikasi).
Log: `logs/17-baseline-build.log`, `logs/18-bytecode-audit.log`.

### 7.1 Ukuran bytecode

| Kontrak      | Runtime baseline (0.8.24) | Runtime final (0.8.39) |             Δ | % batas EIP-170 | Creation final | % batas EIP-3860 |
| ------------ | ------------------------: | ---------------------: | ------------: | --------------: | -------------: | ---------------: |
| AgentGate    |                     1.069 |                  1.058 |  −11 (−1,03%) |           4,31% |          1.457 |            2,96% |
| QuestManager |                    12.272 |                 13.104 | +832 (+6,78%) |          53,32% |         14.890 |           30,29% |
| Reputation   |                     2.218 |                  2.255 |  +37 (+1,67%) |           9,18% |          2.584 |            5,26% |
| Achievement  |                     6.010 |                  6.246 | +236 (+3,93%) |          25,42% |          7.359 |           14,97% |

Dekomposisi QuestManager (+832): efek solc −588 byte, efek kode
+1.420 byte (guard H01/M01/M02/L07). Achievement (+236): efek solc
−30, efek kode +266 (flag high-value). AgentGate/Reputation: efek
kode 0 (tidak diubah). Hash SHA-256 keempat kontrak berubah (sudah
diduga — solc + kode berubah); metadata CBOR tetap 51 byte, byte
versi `000818` → `000827`. Tidak ada library linking.

### 7.2 Opcode Cancun-only (disassembly bagian kode saja)

| Kontrak      | Baseline | Final | Detail                       |
| ------------ | -------: | ----: | ---------------------------- |
| AgentGate    |        0 |     0 | —                            |
| QuestManager |        0 | **1** | MCOPY 1× di PC 1933 (0x78d)  |
| Reputation   |        0 |     0 | —                            |
| Achievement  |        0 | **1** | MCOPY 1× di PC 4432 (0x1150) |

Kedua MCOPY adalah hasil codegen solc ≥0.8.25 (helper penyalin
memori) — NYATA di kode, bukan false positive metadata (keduanya
berada jauh sebelum akhir bagian kode). TSTORE/TLOAD/BLOBHASH/
BLOBBASEFEE: 0 di semua kontrak. **Bukan blocker:** Cancun terbukti
aktif di BSC testnet dan mainnet (validasi Phase 5), seluruh test
suite (Anvil Cancun) mengeksekusi jalur itu dan lolos, dan smoke
test testnet wajib mencakup jalur completion. Konsekuensinya:
`evm_version = "cancun"` kini adalah dependensi fitur NYATA (bukan
lagi sekadar pin reproduksibilitas) — komentar `foundry.toml`
diperbarui sesuai itu, dan `evm_version` tidak boleh diturunkan di
bawah Cancun. Raw-hex grep (tanpa disassembly) menunjukkan banyak
hit palsu (mis. MCOPY=4 di QuestManager) — bukti lanjutan bahwa
metode scan lama tidak dapat dipercaya.

## 8. Hasil CI

**Run #44644411279 — SUCCESS, 10/10 job hijau.**
Trigger: push ke `main`, HEAD `d2ab86d` (commit konten Phase 8),
20 November 2026, 07:15:39–07:19:09 WIB (3 menit 30 detik).
Run hijau ke-5 berturut-turut (run #1–#4 Phase 6 juga hijau).
URL: https://github.com/Namexs/agenthub/actions/runs/44644411279

| Job                                                | Hasil      |
| -------------------------------------------------- | ---------- |
| Contracts (forge build + test)                     | ✅ success |
| Contracts fuzz + invariant (10k runs, pinned seed) | ✅ success |
| Slither static analysis (fail on Medium+)          | ✅ success |
| Secret scanning (gitleaks)                         | ✅ success |
| Dependency audit                                   | ✅ success |
| Web (lint, typecheck, vitest, build)               | ✅ success |
| Shared (lint, typecheck, vitest)                   | ✅ success |
| Format check (prettier + forge fmt)                | ✅ success |
| E2E (smoke + wallet, real build + anvil)           | ✅ success |
| Package manifest check                             | ✅ success |

Job Web kini menjalankan `forge build` sebelum vitest (M07) —
deep-equal parity keempat kontrak (M08) dan `export-abis --check`
(I09) berjalan di CI untuk pertama kalinya dan hijau. Anotasi
non-blocking: peringatan deprecasi Node.js 20 pada beberapa action
(pre-existing, dipaksa berjalan di Node.js 24) — tidak ada
kegagalan.

**Catatan:** run ini memvalidasi commit konten `d2ab86d`. Commit
pemutakhiran laporan ini (§8) dan commit manifest terpisah menyusul
setelahnya (hanya perubahan dokumen); CI pada HEAD final dipantau
terpisah dan hasilnya dilaporkan ke parent agent.

## 9. Temuan baru selama Phase 8

### PH8-1 — Regresi build: TS2589 pada `useQuests` (ditemukan battery, diperbaiki dalam fase ini)

**Severity: build-breaking (CI web job akan gagal).** Setelah regen
ABI Phase 8, `QUEST_MANAGER_ABI` tumbuh dari 89 menjadi 99 entri,
dan inferensi tipe wagmi `useReadContracts` di `hooks/useQuests.ts`
melewati batas kedalaman instansiasi TypeScript
(`TS2589: Type instantiation is excessively deep and possibly
infinite`, `useQuests.ts:74`). Dampak: `tsc --noEmit` exit 2,
`next build` gagal, E2E smoke + wallet E2E gagal start (server
tidak menyala karena build gagal). Battery Phase 8 menangkapnya
pada run pertama (log 06/07/09/10 versi awal).

**Perbaikan (koordinator):** ABI baca minimal `QUEST_MANAGER_READ_ABI`
(4 fungsi: `questCount`, `getQuest`, `hasCompleted`,
`nextCompletionAt`) di `lib/contracts.ts` — entri disalin VERBATIM
dari ABI yang di-commit — dipakai `useQuests` untuk ketiga read-nya
(satu `useReadContract` + dua `useReadContracts`). Type safety
penuh dipertahankan (bukan pelebaran ke `Abi` generik). Drift
ditutup oleh 5 test baru di `abi-parity.test.ts` yang meng-assert
setiap entri minimal deep-equal dengan entri ABI penuh (gagal bila
ada drift). Mock `@/lib/contracts` di `hooks.test.tsx` ditambah
ekspor baru (7 test hook sempat gagal karena mock belum mengekspor
`QUEST_MANAGER_READ_ABI` — diperbaiki, bukan assertion yang
dilemahkan).

**Verifikasi:** typecheck exit 0, Vitest web 173 + 5 skip (178),
production build exit 0 (8 route + `_not-found`), E2E smoke 23/23,
wallet E2E 26/26 — log 08b, 09, 10, 19, 20, 21. `useCompleteQuest`
tetap memakai ABI penuh untuk write (lolos typecheck; tidak diubah).

### PH8-2 — Slither: `cyclomatic-complexity` baru pada `createQuest` (Info)

Guard H01/M01/M02 mendorong kompleksitas `createQuest` melewati
ambang detektor Slither. Benign: rangkaian linear guard clause yang
masing-masing ditest (pola yang sama dengan `completeQuest`, sudah
dicatat di `SECURITY_FINDINGS.md`). Gate tetap exit 0 (0
High/Medium). Lihat §5.6.

### PH8-3 — Artefak tree lokal yang TIDAK di-commit

`next build` lokal (Next 14 terinstal vs Next 15 yang di-pin)
menulis ulang `apps/web/next-env.d.ts` ke bentuk Next 14
(menghapus referensi `./.next/types/routes.d.ts`). Perubahan itu
DIKEMBALIKAN (revert) dan tidak di-commit — CI memakai Next 15 dan
akan meregenerasi file itu dengan benar. Catatan ini juga berlaku
sebagai caveat battery lokal (§10 butir 4).

### Prettier — kegagalan format awal adalah artefak versi

Run format pertama battery melaporkan 6 file bermasalah, tetapi
Prettier 3.3.3 yang di-pin repo (yang dipakai CI) menyatakan
keenam file itu sudah bersih — perbedaan versi Prettier yang
dipakai worker battery. Yang benar-benar perlu diformat hanyalah 3
artefak test-results Phase 8; setelah `prettier --write`, format
check penuh exit 0 (log 08b).

## 10. Keterbatasan (baca sebelum mengutip "aman")

Fase ini **tidak** menyatakan sistem aman. Yang diklaim hanyalah:
temuan Phase 7 dalam ruang lingkup fase ini ditutup dengan bukti
test, dan seluruh battery regresi hijau pada HEAD ini.
Keterbatasan yang berlaku:

1. **Bukan external review.** Remediasi ini dilakukan oleh
   agen-agen dalam lingkungan yang sama dengan implementasi
   (R-012 belum dikomisikan). Review independen eksternal tetap
   diperlukan sebelum mainnet.
2. **Tidak ada pengujian di chain live.** Semua bukti berasal dari
   Foundry lokal, Anvil, dan fork kering. Perilaku di BSC testnet
   — termasuk interaksi dengan Safe nyata, timelock 2 hari, dan
   RPC publik — belum terbukti. Itulah fungsi smoke test testnet.
3. **Hasil tes internal bukan bukti keamanan.** 321 test + fuzz +
   E2E hijau membuktikan kode berperilaku sesuai spesifikasi yang
   diuji — bukan bahwa spesifikasinya lengkap atau tidak ada kelas
   bug di luar cakupan test.
4. **Verifikasi JS berjalan di tree basi** (Next 14.2.35 + React
   18.3.1 terinstal vs Next 15.5.29 + React 19.3.1 yang di-pin —
   caveat yang sama dengan Phase 7; `pnpm install` tidak mungkin
   di VM ini). Otoritas untuk tree yang di-pin adalah CI (§8),
   bukan battery lokal ini. Perbaikan TS2589 (§9) diverifikasi
   pada TS 5.6.3 lokal (versi yang sama dengan yang di-pin).
5. **Asumsi kepercayaan yang tidak diuji:** kejujuran admin/timelock
   dan creator multisig, keamanan kunci verifier, kebenaran
   kontrak Agent ID resmi, dan keamanan dependensi OpenZeppelin.
6. **Solc 0.8.39 baru berusia 1 hari** saat evaluasi (rilis 19 Nov
   2026). Risiko rilis-baru dimitigasi oleh validasi penuh dalam
   fase ini (build + test + fuzz + E2E + audit bytecode hijau),
   tetapi paparan terhadap bug compiler yang belum ditemukan secara
   prinsip lebih tinggi daripada versi yang sudah lama beredar.
7. **Cakupan:** fase ini menutup temuan Phase 7 dalam ruang
   lingkup P0/P1 yang ditetapkan user. Audit penuh dari nol,
   audit frontend menyeluruh, dan audit dependensi JS di luar OSV
   bukan bagian dari fase ini.

## 11. Status R-010 + input deployment

**R-010: IMPLEMENTED, belum CLOSED.** Kriteria penutupan yang masih
terbuka: (1) testnet smoke — quest threshold-1 dan threshold-2
dibuat dan diselesaikan di live testnet, revert duplikat/insufficient
teramati on-chain, DITAMBAH verifikasi kebijakan on-chain baru
(checklist §5.1 langkah 9–11: createQuest 1.001/T1 revert,
guardrail revoke, prosedur supersedes); (2) diff termasuk dalam
external review yang dikomisikan (R-012, belum dikomisikan); (3)
≥ 3 verifier di-grant sebelum quest threshold-2 pertama di mainnet.

**Input deployment dari user (tidak berubah):** tBNB (≥ 0,05),
deployer key khusus testnet, alamat Safe testnet (threshold ≥ 2),
quest creator (kini HARUS alamat Safe, threshold ≥ 2, distinct dari
admin — PH7-M03), verifier pertama (opsional), pauser (opsional),
BscScan API key, persetujuan broadcast eksplisit — ditambah 3
prasyarat operasional PH7-L23 (URL RPC teruji, Safe sudah dibuat,
dompet uji didanai). **Catatan urutan baru (Phase 8):**
`DeployAgentHub` meng-grant paling banyak 1 verifier, jadi quest
threshold-2 tidak bisa dibuat di stack baru sampai verifier ke-2
di-grant via timelock (jeda 2 hari — mulai lebih awal).

## 12. Manifest verifikasi & indeks bukti

- **Baseline:** `5723ff377de3d2cd79854b877124a802fb2c23eb` (`5723ff3`).
- **HEAD konten Phase 8:** `d2ab86debb4f5f8d909db53c3e3eba4a6a2a99e8`
  (`d2ab86d`) — divalidasi CI run #44644411279 (10/10 sukses, §8).
  Commit pemutakhiran laporan ini dan commit manifest terpisah
  menyusul setelahnya dan menjadi HEAD repo final (lihat git log).
- **Hash SHA-256 laporan ini** tidak dapat tercantum di dalam
  laporan itu sendiri (self-referential); hash laporan beserta hash
  seluruh file bukti tercatat di
  `agenthub-phase8-remediation/VERIFICATION.md` yang dihasilkan
  setelah penulisan final laporan ini.
- **PACKAGE_MANIFEST.md** diregenerasi untuk commit final dan
  di-commit terpisah (pola yang sama seperti Phase 6).

### Laporan pendukung (`agenthub-phase8-remediation/`)

| File                                    | Isi                                                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `PHASE8_SECURITY_REMEDIATION_REPORT.md` | Laporan ini                                                                                                          |
| `solc-evaluation.md`                    | Evaluasi upgrade solc 0.8.39 (482 baris): build/test/fuzz, analisis bug compiler, perbandingan bytecode, rekomendasi |
| `test-results/gas-benchmark-phase8.md`  | Metodologi + angka gas + dekomposisi delta                                                                           |
| `test-results/osv-audit-phase8.json`    | Hasil OSV audit (7 temuan)                                                                                           |
| `test-results/slither-phase8.json`      | Hasil Slither lengkap (13 temuan app-only)                                                                           |

### Log (`agenthub-phase8-remediation/logs/`)

`01-forge-build.log` (forge build 0.8.39), `02-forge-test.log`
(321/321), `03-forge-fuzz.log` (321/321, 10k runs),
`04-vitest-web.log` + `04b-abi-parity-verbose.log` (deep-equal 4/4),
`05-vitest-shared.log` (8/8), `06-typecheck-lint.log` (run awal —
typecheck gagal TS2589, lihat §9; rerun hijau di log 19),
`07-next-build.log` (run awal — build gagal TS2589; rerun hijau di
log 21), `08-format.log` (run awal — lihat §9; final hijau di log
08b), `08b-format-final.log` (prettier exit 0),
`09-e2e-smoke.log` (23/23) + `09-e2e-smoke-runner.log`,
`10-wallet-e2e.log` (26/26) + `10-wallet-e2e-runner.log`,
`11-anvil-integration.log` (30/30 + 5/5) +
`11-anvil-integration-runner.log`, `12-slither.log` +
`12b-slither-json.log` (exit 0, 13 hasil), `13-osv.log` (7 temuan),
`14-gitleaks.log` (0 leak), `15-export-abis-check.log` (exit 0),
`16-gas-benchmark.log`, `17-baseline-build.log` (build baseline
5723ff3), `18-bytecode-audit.log` (perbandingan + opcode scan),
`19-typecheck-rerun.log` (exit 0), `20-vitest-rerun.log` (173 + 5
skip), `21-next-build-rerun.log` (exit 0),
`phase8-bytecode-audit.py` (scanner metadata-aware).

### Commit

| Hash         | Subjek                                                                                                                     |
| ------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `969f30d`    | feat(phase-8): on-chain threshold policy + verifier guardrail + high-value badge (PH7-H01/M01/M02/L05/L07/L10)             |
| `a9d93fe`    | feat(phase-8): deploy guards + Safe creator + MockAgentId ownership (PH7-M03/M04/M05/M06/M10)                              |
| `1a8e8bf`    | feat(phase-8): ABI parity in CI + export-abis --check + minimal read ABI (PH7-M07/M08/M09/I09, PH8-1)                      |
| `c380537`    | chore(phase-8): upgrade solc 0.8.24 -> 0.8.39 (PH7-L13)                                                                    |
| `d2ab86d`    | docs(phase-8): security remediation report + regression evidence — CONDITIONAL GO testnet, R-010 implemented pending smoke |
| _(menyusul)_ | docs(phase-8): isi §8 hasil CI run #44644411279 + VERIFICATION.md                                                          |
| _(menyusul)_ | chore(phase-8): regenerate PACKAGE_MANIFEST.md for final commit                                                            |

---

_Phase 8 selesai 20 November 2026. Keputusan: CONDITIONAL GO
testnet, NO-GO mainnet. R-010: IMPLEMENTED, belum CLOSED._
