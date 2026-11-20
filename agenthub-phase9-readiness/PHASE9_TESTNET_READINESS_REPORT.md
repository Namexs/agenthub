# AGENTHUB — Phase 9: Testnet Readiness Report

**Tanggal:** 20 November 2026.
**Baseline tugas:** `d2ab86d` (konten Phase 8).
**HEAD yang dinilai:** `7dff852` (`7dff852d0a303411e060772747fcbafa5c9dd820`).
**Solidity:** 0.8.39, `via_ir = true`, `evm_version = "cancun"`.
**Target:** BNB Smart Chain Testnet (chain 97).
**Laporan acuan:** `agenthub-phase8-remediation/PHASE8_SECURITY_REMEDIATION_REPORT.md`,
`agenthub-phase7-review/PHASE7_INDEPENDENT_SECURITY_REVIEW.md`.
**Metode:** 5 workstream spesialis + 1 battery regresi penuh, dikoordinasikan
dengan pemisahan bukti yang tegas: lokal / CI / fork / live.
**Tidak ada broadcast, tidak ada deployment, tidak ada private key yang
dipakai dalam fase ini.**

## 1. Keputusan

**CONDITIONAL GO untuk deployment live BNB Testnet. NO-GO untuk mainnet.**

**Alasan CONDITIONAL GO testnet:**

- Seluruh blocker testnet dari Phase 7 §11 sudah ditutup dengan bukti,
  ditambah dua cacat deployment baru yang ditemukan dan diperbaiki fase
  ini (PH9-D01, PH9-D02).
- Kebijakan reward yang diperselisihkan (CheckIn 10.000 poin threshold 1)
  diputuskan secara formal sebagai pengecualian desain yang sah, dengan
  analisis ancaman per jenis quest (§2).
- Prosedur live testnet (14 skenario) sudah ditulis lengkap dan divalidasi
  ujung-ke-ujung dua kali di fork chain-97 lokal: **90/90 cek lulus** di
  kedua run (§5).
- Battery regresi penuh hijau di HEAD final: Foundry **323/323**,
  fuzz 10k **323/323**, gas benchmark identik Phase 8 (§7).
- Paket auditor independen siap (28 file, manifest 26/26 terverifikasi).

**Syarat sebelum broadcast (kondisi GO):**

1. Kedelapan input deployment dari user (§6) — termasuk dua Safe testnet
   yang berbeda dan persetujuan broadcast eksplisit.
2. Lima item pra-smoke dari Workstream 2 sebaiknya ditutup dulu atau
   diterima eksplisit: L17 (cek CANCELLER di `_verifyWiring`), L18
   (artefak JSON deploy), L19 (helper proposal timelock — dibutuhkan
   smoke threshold-2), L22 (tabel constructor args BscScan), L23
   (prasyarat operasional ke checklist). Semuanya kecil; tidak satu pun
   memblokir keamanan deploy itu sendiri, tetapi L19 memblokir kelancaran
   smoke test.
3. Dry-run fork sudah membuktikan prosedurnya; **bukti live tetap nol**
   sampai broadcast pertama terjadi (§8 — bagian itu sengaja kosong).

**Alasan NO-GO mainnet:** external review (R-012) belum dikomisikan;
wallet-app nyata belum pernah diuji (O4); live testnet validation belum
terjadi (R-010 belum CLOSED); keputusan review-window quest bernilai
besar (PH7-M03 prosedural) belum diambil; temuan Low/Info sisa belum
didiposisi formal untuk mainnet (§10).

**R-010: IMPLEMENTED, belum CLOSED.** Tidak berubah oleh fase ini —
penutupan membutuhkan live testnet smoke test yang belum terjadi.

## 2. Workstream 1 — Review kebijakan reward: KEPUTUSAN A

**Keputusan: pengecualian desain SAH — kebijakan threshold hanya berlaku
untuk quest Attested. Tidak ada perubahan kode.**

Dokumen lengkap: `workstreams/01-reward-policy-review.md`.

### 2.1 Pertanyaan yang harus diselesaikan

Phase 8 mengizinkan quest CheckIn 10.000 poin dengan threshold 1
(PH7-L08/I07 — keputusan desain Phase 8: kebijakan hanya bermakna
untuk Attested). Phase 9 harus menentukan: pengecualian desain yang sah
atau celah kebijakan?

### 2.2 Bukti struktural yang menentukan

Nilai `attestationThreshold` yang tersimpan hanya pernah ditegakkan di
**satu titik** di seluruh codebase — `QuestManager.sol:336`
(`provided < threshold` di `_verifyAttestations`), yang hanya tercapai
lewat `completeQuestWithAttestation`, yang menolak quest non-Attested
di gerbang kind (`QuestNotAttested`). Jalur `completeQuest`
(CheckIn/OnChain) tidak pernah membaca nilai itu (dibuktikan grep
menyeluruh).

### 2.3 Analisis ancaman per jenis quest

| Jenis    | Siapa yang mengesahkan                                     | Apakah threshold 2 mengurangi kemampuan penyerang?                                                                                                                                                                                   |
| -------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Attested | M verifier berbeda (EIP-712)                               | **Ya, nyata.** Satu verifier kompromi tidak cukup; butuh M kunci independen. Inilah skenario yang dicegah R-010 dan H01.                                                                                                             |
| CheckIn  | Tidak ada — completer sendiri ("the call IS the activity") | **Tidak.** Creator nakal tinggal menulis angka 2 (ia yang memilih threshold); user self-farming dibatasi aturan anti-farming yang ortogonal; verifier tidak berperan.                                                                |
| OnChain  | Kontrak validator via STATICCALL                           | **Tidak.** Ancamannya validator longgar/berubah (kontrol: approval per-instance + revocasi live) dan gaming kondisi (desain validator). M-of-N yang bermakna di sini adalah fitur baru (multi-validator), bukan penegakan kebijakan. |

Argumen penentu: threshold adalah kontrol atas **pihak ketiga yang
mengesahkan**, dan hanya jalur Attested yang punya pihak ketiga untuk
dikontrol. Floor atas parameter pilihan creator hanya bermakna bila
mengikat pihak lain; pada CheckIn/OnChain tidak ada pihak lain di jalur
completion. Memaksakan T2 di sana hanya mengubah satu byte metadata
yang tidak pernah dibaca — dan menciptakan kesan keamanan palsu (false
confidence), persis mode kegagalan yang dikritik Phase 7 pada H01.

**Badge high-value:** aturan Attested-only konsisten dengan alasan yang
sama — badge diterbitkan di `_completeQuest` apa pun kind-nya, jadi
floor T2 tidak melindungi badge di CheckIn. Pertanyaan sahnya adalah
pembatasan kind ("bolehkah badge high-value di quest CheckIn?"),
dicatat sebagai rekomendasi SOP R-9-WS1-1, bukan alasan memilih
enforcement universal.

**Konsisten dengan threat model:** risiko CheckIn/OnChain 10.000 poin
adalah tepat residual AR-3/T4 yang sudah diterima (cap per-quest,
creator multisig, monitoring, rem deactivate/pause). Kebijakan threshold
tidak pernah menjadi kontrol creator — ia kontrol kompromi verifier
(T-ATT-01).

### 2.4 Penutupan

PH7-L08 dan PH7-I07 **ditutup sebagai keputusan desain formal**
(D-9-WS1-1 s.d. D-9-WS1-4, plus 6 syarat yang harus tetap dipenuhi).
Test yang mengunci keputusan sudah ada
(`PolicyEnforcement.t.sol:300, 313, 320`). Tiga rekomendasi tindak
lanjut dicatat di dokumen workstream (termasuk R-9-WS1-1 dan pertanyaan
kebijakan besaran reward per-kind — terpisah dari kebijakan attestation).

## 3. Workstream 2 — Review deployment: 2 cacat ditemukan dan diperbaiki

Dokumen lengkap: `workstreams/02-deployment-review.md`.
Kode berubah: commit `7dff852` (3 file, +92/−7, tidak di-push oleh
workstream — koordinator yang push).

### 3.1 Temuan baru

| ID      | Cacat                                                                                                                                                                                                                                                                                                                                                                                                                        | Status                                                                                                                                                                                                                                                                                                                                   |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PH9-D01 | **Dua Safe harus berbeda — tidak ditegakkan.** `deploy()` memvalidasi kedua Safe tetapi tidak pernah memeriksa `adminMultisig != questCreator`; Safe yang sama lolos kedua validasi dan deploy sukses, meruntuhkan separation of duties yang dimaksud M03. Dokumen mewajibkan distinct, kode tidak. Dibuktikan pra-perbaikan: probe test `test_GAP_SameSafeForAdminAndCreatorDeploys` PASS (deploy sukses dengan Safe sama). | **DIPERBAIKI** — error `AdminAndCreatorMustDiffer` + cek di `deploy()` sebelum validasi/CREATE apa pun, di semua chain + 2 test baru (31337 + jalur kanonis 97)                                                                                                                                                                          |
| PH9-D02 | **`DeployMock` tanpa guard konfirmasi.** Jalur broadcast ke chain 97 yang tidak memeriksa `CONFIRM_TESTNET_DEPLOY` sama sekali (dry-run pra-perbaikan tanpa env apa pun: `SIMULATION COMPLETE`).                                                                                                                                                                                                                             | **DIPERBAIKI** — guard simetris PH7-M05 + 3 skenario test (97 tanpa konfirmasi revert, 97 dengan konfirmasi deploy, 31337 dikecualikan). Diverifikasi CLI pasca-perbaikan di anvil chain 97/1 + fork testnet live                                                                                                                        |
| PH9-D03 | **Guard hidup di `run()`, bukan `deploy()`.** `deploy()` publik dan tanpa guard — wrapper baru yang disengaja memanggil `deploy()` + `startBroadcast` akan melewati guard.                                                                                                                                                                                                                                                   | **Risiko residual, didokumentasikan.** Memerlukan kode baru yang disengaja, bukan kecelakaan operator (dibuktikan probe: `forge script --broadcast` tanpa `startBroadcast` → `No transactions to broadcast`, nonce tidak berubah). Mitigasi: `run()` satu-satunya entry point terdokumentasi; rekomendasi SOP di laporan workstream §7.3 |

### 3.2 Verdict 6 poin audit (pasca-perbaikan)

| Poin                                                               | Verdict                                                                                                                                                                                                                        |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1. Quest creator memakai Safe tervalidasi (sama kuat dengan admin) | **LOLOS** — helper + nilai ekspektasi persis sama dengan admin; 5 test lulus; CLI fork live: EOA → `NotASafe("no code")`                                                                                                       |
| 2. Admin memakai Safe tervalidasi                                  | **LOLOS** — 7 test (EOA, non-Safe, threshold 1, threshold > owner, 3-of-3, tolak nilai eksplisit di 97, wajib nilai eksplisit di 31337)                                                                                        |
| 3. Kedua Safe BERBEDA                                              | **LOLOS (pasca-perbaikan)** — GAGAL pada baseline (PH9-D01)                                                                                                                                                                    |
| 4. Deployer tanpa privilege pasca-deploy                           | **LOLOS** — inventaris lengkap 15 peran/kepemilikan (timelock self-admin, CANCELLER → multisig via OZ, mock → multisig); 12+13 assert negatif lulus; `_verifyWiring` punya 10 cek negatif deployer                             |
| 5. Tidak ada private key hardcoded                                 | **LOLOS** — gitleaks riwayat git 107 commit: 0 leak; 4 temuan working-tree semuanya false positive di `out/`+`.next/` (gitignored); grep: hanya kunci publik Anvil (allowlist), codehash Safe, `SECP256K1_N`; tidak ada `.env` |
| 6. Tidak ada jalur deployment melewati guard                       | **LOLOS (pasca-perbaikan)** — matriks 10 kasus CLI (anvil chain 97/1 + fork testnet live blok 143.737.179): semua jalur fail-closed                                                                                            |

### 3.3 Klasifikasi temuan terbuka L17–L23

| ID  | Klasifikasi             | Alasan                                                                                                               |
| --- | ----------------------- | -------------------------------------------------------------------------------------------------------------------- |
| L17 | **Tutup sebelum smoke** | Cek CANCELLER di `_verifyWiring` + 3 assert negatif deployer (1 baris + test)                                        |
| L18 | **Tutup sebelum smoke** | Artefak JSON deploy + `fs_permissions` (pencatatan alamat masih manual)                                              |
| L19 | **Tutup sebelum smoke** | Helper proposal timelock — dibutuhkan smoke threshold-2 (grant verifier ke-2 via timelock)                           |
| L20 | **Sudah tertutup**      | Artefak broadcast fork 97 tidak ada lagi di disk (terverifikasi hilang selama jendela audit)                         |
| L21 | **Bisa ditunda**        | Jalur default aman; validasi codehash berisiko false positive — perkuat dokumentasi saja                             |
| L22 | **Tutup sebelum smoke** | Tabel constructor args untuk verifikasi BscScan manual                                                               |
| L23 | **Tutup sebelum smoke** | 3 prasyarat operasional (URL RPC teruji — sudah tertutup WS3, Safe sudah dibuat, dompet uji didanai) ke checklist §1 |

Kelima item "tutup sebelum smoke" direkomendasikan dikerjakan sebagai
pekerjaan kecil sebelum deployment-day (§1 syarat 2). Tidak satu pun
memblokir keamanan deploy itu sendiri.

## 4. Workstream 3 — Testnet preflight: gate BELUM LOLOS (8 input user)

Dokumen lengkap: `workstreams/03-testnet-preflight.md`.
Semua pengecekan read-only (`eth_chainId`, `eth_blockNumber`,
`eth_gasPrice`, `eth_getCode`); tidak ada broadcast.

### 4.1 Ringkasan status — 25 item

| Status                      | Jumlah |
| --------------------------- | -----: |
| ✅ TERVERIFIKASI            |     11 |
| ⏳ MENUNGGU INPUT USER      |      8 |
| ❓ BELUM DAPAT DIVERIFIKASI |      6 |

**Gate preflight: BELUM LOLOS** — semua yang bisa dicek tanpa input
user sudah hijau; tidak ada satu pun item read-only yang gagal. Blocker
murni 8 input user.

### 4.2 Hasil cek RPC live (2026-11-20 07:44 WIB)

- RPC primer `data-seed-prebsc-1-s1`: chainId `0x61` = **97**,
  blok 143.736.674, gas price **0,1 gwei**.
- RPC fallback `data-seed-prebsc-2-s1`: chainId **97**, blok 143.736.704,
  gas 0,1 gwei — siap siaga.
- Kontrak Agent ID resmi `0x60B926…022F` di chain 97: `eth_getCode` =
  `0x` — **tidak ada**. MockAgentId adalah jalur yang benar untuk
  testnet (sesuai `lib/env.ts`); implikasinya: test Agent ID di-mint
  lewat MockAgentId oleh admin multisig, dan smoke test membuktikan
  logika kontrak, BUKAN integrasi dengan kontrak Agent ID resmi
  (integrasi resmi hanya teruji di mainnet; fork test
  `AgentGateMainnet.t.sol` menutup sebagian celah ini secara lokal).
- Safe singleton v1.4.1 + v1.3.0 dan kedua factory kanonis: semua punya
  kode di chain 97 — Safe testnet bisa dibuat sekarang. Ini menutup
  prasyarat PH7-L23 "URL RPC teruji".

### 4.3 Kebutuhan tBNB (direkonsiliasi dengan dry-run WS4)

Workstream 3 mengestimasi deploy 11–12 jt gas dari pengukuran fork lama
(10.294.857 gas, kode pra-Phase 6). Workstream 4 mengukur langsung di
kode Phase 8: deploy **8.307.890 gas** (dua run fork, identik).
Rekonsiliasi koordinator:

| Item                                                         | Gas        | tBNB @ 0,1 gwei                                                            |
| ------------------------------------------------------------ | ---------- | -------------------------------------------------------------------------- |
| Deploy penuh (terukur, 2 run)                                | 8.307.890  | 0,000831                                                                   |
| Smoke test (completion T1/T2 terukur + estimasi konservatif) | ~2.560.000 | 0,000256                                                                   |
| **Minimal mutlak**                                           |            | **0,002**                                                                  |
| **Direkomendasikan**                                         |            | **≥ 0,05** (menutup deploy + smoke + 1× redeploy bahkan bila gas naik 10×) |

Dompet uji: ~0,005 tBNB masing-masing.

### 4.4 Input user yang ditunggu (semua "belum diterima")

tBNB ≥ 0,05; deployer key khusus testnet; Safe admin (threshold ≥ 2);
Safe quest creator (threshold ≥ 2, distinct dari admin); verifier
pertama (opsional); pauser (opsional); BscScan API key; persetujuan
broadcast eksplisit. Checklist memuat peringatan tebal: **private key
TIDAK PERNAH dikirim ke chat/laporan** — hanya dipakai lokal oleh user
saat broadcast yang disetujui; Asta hanya perlu alamat deployer (publik)
untuk verifikasi saldo.

Catatan waktu terpanjang (longest pole): proposal timelock grant
verifier ke-2 + approve validator harus diajukan segera setelah deploy
karena jeda 2 hari memblokir quest threshold-2 dan OnChain.

## 5. Workstream 4 — Live testnet test plan + fork dry-run 90/90

Dokumen lengkap: `workstreams/04-live-testnet-test-plan.md` (1.328 baris)
dan `workstreams/04-live-testnet-test-plan-fork-dryrun.md`.
Driver reproduksi: `workstreams/fork-dryrun/run-fork-dryrun.sh`.

### 5.1 Rencana (14 skenario, kolom hasil dikosongkan)

S1 deploy (urutan nyata script: MockAgentId → AgentGate → Timelock →
Reputation → Achievement → QuestManager) · S2 verifikasi alamat · S3
ownership + role (termasuk deployer zero-privilege) · S4 timelock
(delay 2 hari, proposer/executor/canceller) · S5 buat quest Attested
threshold 1 · S6 selesaikan T1 (1 verifier) · S7 buat quest Attested
threshold 2 · S8 selesaikan T2 (2 verifier, digest sama) · S9
signature duplikat ditolak · S10 signature tidak mencukupi ditolak ·
S11 H01 — quest 1.001 poin T1 ditolak (+ kontrol positif 1.001/T2 dan
1.000/T1) · S12 M01 — revoke diblokir di eksekusi timelock, lalu
pemulihan deactivate-first · S13 L07 supersedes (Alice terblokir, Bob
menyelesaikan) · S14 audit event/transaksi di BscScan (hitungan eksak

- ledger 26 baris).

Tiap skenario: tujuan, prasyarat, perintah persis (`forge script` /
`cast` / langkah Safe UI / template signing EIP-712), nilai yang
diharapkan, dan kolom HASIL AKTUAL + TX HASH yang dibiarkan **kosong**
— tidak ada hasil live yang dikarang.

**Durasi: ~6 hari kalender sekuensial** (Hari 0 deploy + schedule
grant-V2 → Hari 2 execute + S5–S11 → Hari 4 bukti revoke + setup →
Hari 6 supersedes + audit akhir), ~3–3,5 jam waktu aktif operator;
sisanya menunggu timelock. Opsi terkompresi 4 hari didokumentasikan
dengan dua peringatan eksplisit.

**Koreksi urutan deploy:** singkatan brief ("AgentGate → QuestManager →
Reputation → Achievement") bukan yang dilakukan script — QuestManager
di-deploy _terakhir_ (menerima alamat lain di constructor-nya). Rencana
mendokumentasikan urutan nyata dan menandai perbedaan ini secara
eksplisit.

### 5.2 Fork dry-run — BUKAN bukti live

| Item                  | Run 1                     | Run 2 (koordinator)       |
| --------------------- | ------------------------- | ------------------------- |
| HEAD                  | `e1b316b`                 | `7dff852`                 |
| Waktu                 | 2026-11-20 ~00:51 WIB     | 2026-11-20 ~08:14 WIB     |
| Hasil                 | **90/90 PASS, 0 FAIL**    | **90/90 PASS, 0 FAIL**    |
| Deploy gas            | 8.307.890                 | 8.307.890                 |
| S6 (T1) / S8 (T2) gas | 235.990 / 195.351         | 235.990 / 195.351         |
| Log                   | `fork-dryrun-e1b316b.log` | `fork-dryrun-7dff852.log` |

Dry-run membuktikan: script deploy berjalan terhadap state chain-97
nyata (factory + singleton Safe kanonis); setiap perintah di rencana
live berjalan seperti tertulis; semua nilai yang diharapkan cocok
dengan perilaku on-chain; kelima bukti revert menghasilkan custom
error yang didokumentasikan dengan transaksi gagal on-chain
(status `0x0`); alur timelock (schedule → tunggu → execute)
berperilaku seperti asumsi rencana; hitungan event S14 cocok persis.

Run 2 mengonfirmasi guard baru `7dff852` tidak merusak alur deploy
(konfigurasi dry-run valid: dua Safe berbeda, env set — guard hanya
menambah revert fail-closed untuk konfigurasi tidak valid).

**Penyimpangan yang didokumentasikan (D1–D5):** aksi Safe via
impersonasi anvil (bukan Safe UI + kuorum owner); jeda timelock 2 hari
dilewati time-warp; tanpa BscScan di fork (verifikasi event/revert via
`cast logs`/`receipt` — `--verify` tidak diuji); Safe dibuat segar di
fork (bukan Safe tim yang sebenarnya); state fork adalah snapshot.
Dry-run membuktikan prosedurnya, BUKAN chain live-nya (§8).

## 6. Workstream 5 — Paket auditor independen: SIAP

Lokasi: `agenthub-phase9-readiness/audit-package/` (28 file, 456 KB).
Dokumen README paket menyatakan dengan jelas di atas: **external audit
BELUM dilakukan — paket ini hanya persiapan.**

| Isi                           | Keterangan                                                                                                                                                                                                                                            |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| README.md                     | Cara pakai, audit commit `7dff852`, instruksi checkout + verifikasi                                                                                                                                                                                   |
| ARCHITECTURE_OVERVIEW.md      | Dari `docs/ARCHITECTURE.md` + README + plan threshold (dengan sitasi)                                                                                                                                                                                 |
| THREAT_MODEL.md               | Kondensasi `docs/SECURITY_THREAT_MODEL.md`: aset, aktor A1–A7, attack tree T1–T8, accepted risk AR-1–AR-7                                                                                                                                             |
| FINDINGS.md                   | Tabel gabungan 59 temuan Phase 7 + status Phase 8 tiap temuan + 3 temuan Phase 8 (PH8-1/2/3) + 3 temuan Phase 9 (PH9-D01/D02/D03). Tally: 17 CLOSED + 1 PARTIAL (M03) + 1 ACCEPTED (L01) + 2 DESIGN (L08/I07) + 1 CLOSED-P7 (L27) + 22 OPEN + 15 INFO |
| TEST_RESULTS.md               | Angka Phase 8 + §9 re-run Phase 9 di `7dff852`                                                                                                                                                                                                        |
| BUILD_REPRODUCTION.md         | solc 0.8.39, via_ir=true (wajib), evm cancun, optimizer 200 runs, forge 1.9.0 + langkah reproduksi                                                                                                                                                    |
| BYTECODE.md                   | Hash + ukuran + opcode scan dari build fresh                                                                                                                                                                                                          |
| KNOWN_LIMITATIONS.md          | Temuan terbuka, M03 prosedural, O4, R-012, R-010 belum CLOSED, checklist pra-mainnet                                                                                                                                                                  |
| MANIFEST.md + MANIFEST.sha256 | SHA-256 26 file konten — **terverifikasi `sha256sum -c` 26/26 OK** (diregenerasi koordinator setelah refresh ke `7dff852`)                                                                                                                            |
| `abis/`                       | Keempat ABI ter-commit (18 + 99 + 33 + 64 = 214 entri; 201 Phase 7 + 13 Phase 8) + `abi-parity.test.ts`, salinan verbatim                                                                                                                             |
| `bytecode/`                   | `bytecode-audit.py` (scanner metadata-aware + hash) + log                                                                                                                                                                                             |
| `deployment/`                 | 7 script + `foundry.toml`, salinan verbatim dari HEAD `7dff852` (terverifikasi `cmp` identik)                                                                                                                                                         |
| `reports/`                    | Laporan Phase 7, Phase 8, solc-evaluation, salinan verbatim                                                                                                                                                                                           |

**Bytecode** (build fresh, forge 1.9.0, solc 0.8.39, via-IR): SHA-256
runtime **cocok 4/4 dengan hash Phase 8** (build reproduksibel).
Keccak256 creation/deployed per kontrak ada di `BYTECODE.md`.
Opcode scan diukur ulang: **MCOPY 1× QuestManager @ PC 1933, 1×
Achievement @ PC 4432** (cocok Phase 8); TSTORE/TLOAD/BLOBHASH/
BLOBBASEFEE 0 di semua kontrak. QuestManager 13.104 byte (53,32%
batas EIP-170). Bytecode tidak berubah antara `e1b316b` dan `7dff852`
(tidak ada perubahan source kontrak) — hash tetap berlaku.

**Tidak ada secret di paket:** gitleaks 8.24.3 `no leaks found`
(dijalankan 2×); grep berpola hanya menemukan hash publik, nama env
var tanpa nilai, dan 2 kunci default publik Anvil di
`DeployLocalTestStack.s.sol` (PH7-I16: bukan kebocoran; script
di-chain-guard ke 31337). Tidak ada file `.env`/`.pem`/`.key`.

Catatan rekonsiliasi: headline Phase 8 "14 ditutup" vs 17 baris tabel
§2 — selisihnya M03 parsial + L15/L16 dok-only (dicatat di FINDINGS.md).

## 7. Battery regresi — 13/13 HIJAU di HEAD `7dff852`

Dijalankan 20 November 2026 ~08:00–08:15 WIB pada HEAD final (setelah
perubahan Workstream 2). Log: `agenthub-phase9-readiness/logs/` (24 file).

| #   | Suite                               | Hasil                                            | vs Phase 8           |
| --- | ----------------------------------- | ------------------------------------------------ | -------------------- |
| 1   | `forge build` (via-IR, solc 0.8.39) | exit 0 (82 dtk)                                  | sama                 |
| 2   | `forge test`                        | **323/323** (22 suite, 0 gagal, 0 skip)          | +2 (test guard baru) |
| 3   | Fuzz 10.000 runs, seed 42           | **323/323**                                      | +2                   |
| 4   | Vitest web / shared                 | **173 + 5 skip (178)** / **8/8**                 | sama                 |
| 5   | TypeScript + lint                   | exit 0                                           | sama                 |
| 6   | Production build Next.js            | exit 0, 11 halaman statis                        | sama                 |
| 7   | E2E smoke / wallet E2E              | **23/23** / **26/26**, 0 console error           | sama                 |
| 8   | Anvil integration                   | **30/30 + 5/5**                                  | sama                 |
| 9   | Slither app-only (`--fail-medium`)  | exit 0, 13 hasil: 0 High, 0 Medium (set identik) | sama                 |
| 10  | OSV audit                           | 7 (0C/0H), set identik                           | sama                 |
| 11  | Gitleaks full history               | 0 leak (108 commit)                              | sama                 |
| 12  | ABI parity + `export-abis --check`  | vitest abi-parity 13/13, deep-equal 4/4, exit 0  | sama                 |
| 13  | Gas benchmark (threshold)           | T1 244.840 / T2 255.766 / T3 266.911             | **identik persis**   |

Tidak ada test dihapus; tidak ada assertion dilemahkan. Caveat battery
(dicatat jujur di log): Node lokal v24.22.1 vs pin CI 20.20.2; pnpm
tidak ada di PATH VM sehingga perintah pnpm diganti biner identik dari
`node_modules/.bin`; log fase lain yang sempat tertimpa runner
disalin dulu ke folder Phase 9, diverifikasi identik via `diff`, lalu
file asli di-restore dengan `git checkout`.

## 8. Pemisahan bukti — baca bagian ini sebelum mempercayai apa pun

### 8.1 Sudah diverifikasi secara lokal

- Seluruh battery §7 di HEAD `7dff852` (forge, fuzz, Vitest, build,
  E2E, Anvil, Slither, OSV, Gitleaks, ABI parity, gas).
- Kriptografi threshold M-of-N (39 PoC Foundry, Phase 7) + policy
  enforcement on-chain (Phase 8, `PolicyEnforcement.t.sol` 16 test).
- Guardrail revoke verifier, mekanisme supersedes, guard deploy
  (PH9-D01/D02) — semuanya dengan test negatif + positif.
- Konektivitas RPC testnet live (read-only): chainId 97, gas 0,1 gwei,
  singleton/factory Safe kanonis punya kode di chain 97 (§4.2).
- Bytecode reproduksibel: hash build fresh cocok 4/4 dengan Phase 8.

### 8.2 Sudah diverifikasi melalui fork (BUKAN live)

- Prosedur live test plan 14 skenario: **90/90 cek lulus, dua run**
  (HEAD `e1b316b` dan `7dff852`) di fork anvil chain-97 lokal (§5.2).
  Ini membuktikan prosedurnya dapat dijalankan — bukan bahwa chain live
  akan berperilaku sama (penyimpangan D1–D5 didokumentasikan).

### 8.3 Sudah diverifikasi melalui CI

_(Diisi setelah push — lihat §12. Pola yang sama dengan Phase 8:
laporan ini di-commit, di-push, CI di-watch, lalu §8.3 dan §12
diperbarui dengan run id + hasil pada commit lanjutan.)_

### 8.4 Sudah diverifikasi di live testnet

**BELUM ADA APA PUN.** Bagian ini sengaja kosong. Tidak ada satu pun
transaksi yang pernah di-broadcast ke chain 97 (atau chain mana pun)
oleh proyek ini. Tidak ada alamat kontrak live, tidak ada tx hash live,
tidak ada verifikasi BscScan, tidak ada Safe tim yang terverifikasi
on-chain. Semua klaim tentang perilaku live adalah prediksi dari bukti
lokal/fork sampai smoke test S1–S14 dijalankan dan hasilnya dicatat di
rencana live (§5.1).

### 8.5 Belum diverifikasi

- Perilaku kontrak di chain 97 live (semua skenario S1–S14).
- Safe tim yang sebenarnya (alamat belum diterima; validasi Safe hanya
  terbukti terhadap Safe kanonis di fork + test).
- Kuorum owner Safe via Safe web app + Safe Transaction Service
  (dry-run memakai impersonasi anvil).
- Dekode event/revert di BscScan + verifikasi source `--verify`
  (tidak dapat berjalan di fork).
- Frontend terhadap kontrak live (checklist §5.2 di luar fase ini).
- Wallet-app nyata (O4) — wagmi hanya `injected()`, tanpa WalletConnect.
- Faucet tBNB (tidak diuji — butuh interaksi web).
- Gas deploy final di chain live (8.307.890 gas terukur di fork; harga
  gas live saat broadcast bisa berbeda dari 0,1 gwei).

## 9. Risiko yang diterima (dengan bukti + alasan)

| ID                       | Risiko                                                          | Alasan penerimaan                                                                                |
| ------------------------ | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| PH7-L01 / AR-3           | Tanpa cap total emisi reputasi                                  | Cap arbitrer; creator multisig + monitoring + pause/deactivate (Phase 8 §2)                      |
| PH7-L08 / I07            | Threshold policy Attested-only (CheckIn/OnChain 10.000 poin T1) | Keputusan desain formal Phase 9 §2: threshold tidak bermakna tanpa pihak ketiga yang mengesahkan |
| PH7-I06                  | Replay pada fork chainId sama                                   | Accepted risk (fork lokal bukan ancaman live)                                                    |
| PH9-D03                  | Guard di `run()`, bukan `deploy()`                              | Memerlukan kode wrapper baru yang disengaja; `run()` satu-satunya entry point terdokumentasi     |
| PH7-L06                  | Nonce global per akun                                           | Batasan UX yang didokumentasikan; perbaikan adalah perubahan desain                              |
| T-ATT-01                 | M verifier berkolusi                                            | Tidak ada threshold yang membuat verifier jujur; backstop adalah pause + monitoring SOP          |
| Integrasi Agent ID resmi | Hanya teruji via fork mainnet + MockAgentId di testnet          | Kontrak resmi tidak ada di chain 97; integrasi penuh hanya teruji di mainnet                     |

## 10. Risiko yang belum diselesaikan

| ID                                            | Risiko                                                                 | Status / langkah berikutnya                                                         |
| --------------------------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| R-010                                         | Threshold attestation belum CLOSED                                     | Butuh live testnet smoke (S5–S10)                                                   |
| R-012                                         | External review belum dikomisikan                                      | Paket audit siap (§6); komisioning adalah keputusan user                            |
| O4                                            | Wallet-app nyata belum diuji                                           | Uji saat smoke test frontend (checklist §5.2)                                       |
| PH7-M03 prosedural                            | Review window / alur dua langkah quest bernilai besar belum diputuskan | Keputusan tim sebelum mainnet                                                       |
| L17/L18/L19/L22/L23                           | Item pra-smoke (§3.3)                                                  | Tutup sebelum deployment-day atau terima eksplisit                                  |
| L02/L03/L04/L09/L11/L12/L14 + L24/L26/L28–L31 | Temuan Low/Info sisa Phase 7                                           | Didokumentasikan di FINDINGS.md paket audit; disposisi formal mainnet masih terbuka |
| PH7-L21                                       | `AGENT_ID_ADDRESS` di-supply di 97 tidak divalidasi                    | Jalur default (unset) aman; biarkan unset saat deploy testnet                       |

## 11. File yang berubah

| Perubahan                                          | File                                                                                                                                                                                                                                      |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PH9-D01 + PH9-D02 (commit `7dff852`)               | `packages/contracts/script/DeployAgentHub.s.sol` (+16), `packages/contracts/script/DeployMock.s.sol` (+15/−1), `packages/contracts/test/DeployScript.t.sol` (+68/−6)                                                                      |
| Prettier ignore untuk salinan verbatim paket audit | `.prettierignore` (+4)                                                                                                                                                                                                                    |
| Laporan ini + VERIFICATION.md                      | `agenthub-phase9-readiness/PHASE9_TESTNET_READINESS_REPORT.md`, `agenthub-phase9-readiness/VERIFICATION.md`                                                                                                                               |
| Dokumen workstream                                 | `agenthub-phase9-readiness/workstreams/01-reward-policy-review.md`, `02-deployment-review.md`, `03-testnet-preflight.md`, `04-live-testnet-test-plan.md`, `04-live-testnet-test-plan-fork-dryrun.md`, `fork-dryrun/` (driver + 2 log run) |
| Paket audit                                        | `agenthub-phase9-readiness/audit-package/` (28 file)                                                                                                                                                                                      |
| Log battery                                        | `agenthub-phase9-readiness/logs/` (24 file)                                                                                                                                                                                               |
| Manifest                                           | `PACKAGE_MANIFEST.md` (regenerasi)                                                                                                                                                                                                        |

**Tidak ada perubahan kontrak, frontend, atau ABI dalam fase ini**
(`git diff e1b316b 7dff852 -- packages/contracts/src/ apps/` kosong).
Baseline tugas `d2ab86d` vs HEAD `e1b316b` hanya berbeda dokumentasi +
manifest (tanpa perubahan kode); `7dff852` menambah guard script deploy

- test di atasnya.

## 12. Indeks bukti + commit + CI

**Laporan workstream:** `agenthub-phase9-readiness/workstreams/` (01–04

- fork-dryrun). **Paket audit:** `agenthub-phase9-readiness/audit-package/`
  (manifest 26/26 OK). **Log battery:** `agenthub-phase9-readiness/logs/`
  (24 file). **Log dry-run fork:** `workstreams/fork-dryrun/`
  (`fork-dryrun-e1b316b.log`, `fork-dryrun-7dff852.log`).

**Commit:**

- `7dff852` feat(phase-9): enforce distinct admin/creator Safes +
  guard DeployMock testnet (PH9-D01/D02)
- _(commit dokumen Phase 9 + manifest diisi koordinator setelah finalisasi)_

**CI:** _(diisi setelah push — run id + hasil tiap job.)_

**Keputusan akhir: CONDITIONAL GO untuk deployment live BNB Testnet
(setelah 8 input user + persetujuan broadcast + disposisi 5 item
pra-smoke). NO-GO untuk mainnet.**

Tidak ada deployment yang diotorisasi oleh laporan ini — hanya
persetujuan eksplisit user untuk broadcast tertentu yang
mengotorisasi satu.
