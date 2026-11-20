# AGENTHUB — Phase 8: Evaluasi Upgrade Solidity (0.8.24 → 0.8.39)

**Tanggal:** 20 November 2026.
**HEAD yang dievaluasi:** `5723ff3` (`5723ff377de3d2cd79854b877124a802fb2c23eb`).
**Evaluator:** Worker D (evaluasi saja — tidak ada file repo yang diubah
kecuali laporan ini; tidak ada deploy, broadcast, atau private key).
**Acuan:** temuan Phase 7 PH7-L13 (§5), PH7-I10–I12 (§6), §8 caveat,
§10 butir 6, dan `agenthub-phase7-review/findings/06-via-ir-bytecode.md`
(metode audit bytecode + opcode scan yang benar).

## 1. Rekomendasi

**UPGRADE ke solc 0.8.39.**

Alasan singkat:

1. **Menutup PH7-L13** — `YulOptimizerKnowledgeBaseStaleBookkeeping`
   (low, "any code may be affected" via-IR, tidak dapat disingkirkan
   secara statis di 0.8.24) diperbaiki di 0.8.38; 0.8.39 juga memperbaiki
   bug medium SOL-2026-8 (`OverlappingRecursiveStorageStructCopyCorruption`).
2. **0.8.39 memiliki NOL bug yang diketahui** dalam daftar resmi
   Solidity (entri terbaru daftar itu diperbaiki di 0.8.39; tidak ada
   entri yang diperbaiki di versi lebih baru atau tanpa perbaikan).
3. **Seluruh baterai validasi hijau pada 0.8.39:** `forge test` 287/287,
   fuzz 10.000 run seed 42 (perintah persis CI) 287/287, gas completion
   TURUN 0,07–0,23%, ukuran runtime QuestManager TURUN 4,79%, ABI
   identik 201/201 entri.
4. **Biaya upgrade minimal:** satu baris `foundry.toml` + pembaruan
   komentar dan dokumen hidup. Tanpa perubahan kode kontrak, pragma,
   remapping, versi Foundry, atau CI.
5. **0.8.39 kemungkinan rilis terakhir seri 0.8.x** (per pengumuman
   rilis: "This is likely the last release of the 0.8 series, and the
   next release will be 0.9.0") — target pin yang stabil sebelum 0.9.0.

Satu-satunya perubahan perilaku yang material: build 0.8.39 kini
**benar-benar memakai opcode MCOPY** (1× di QuestManager, 1× di
Achievement, di helper penyalin memori hasil codegen) — bukan blocker,
karena Cancun sudah terbukti aktif di BSC testnet+mainnet dan seluruh
test suite (Anvil Cancun) mengeksekusi jalur tersebut dan lolos. Tetapi
komentar `foundry.toml` yang mengklaim "no Cancun-only opcodes" menjadi
salah dan WAJIB diperbarui, dan smoke test testnet wajib mencakup jalur
completion (sudah direncanakan — jalur itu melewati helper MCOPY).
Lihat §7.

Alternatif yang dipertimbangkan dan ditolak: **0.8.38** (rilis 22 Okt 2026) menutup PH7-L13 tetapi masih terpapar bug medium SOL-2026-8
(meski bug itu sendiri tidak berlaku untuk kode AGENTHUB — tidak ada
struct rekursif, lihat §8). Karena 0.8.39 tidak menambah biaya apa pun
dan sudah divalidasi penuh dalam evaluasi ini, tidak ada alasan
memilih 0.8.38. Bila tim merasa tidak nyaman dengan rilis berusia
1 hari, 0.8.38 adalah fallback yang dapat diterima — tetapi rekomendasi
tegas laporan ini adalah 0.8.39.

## 2. Kandidat yang dievaluasi

| Item                                             | Nilai                                                                          |
| ------------------------------------------------ | ------------------------------------------------------------------------------ |
| Versi stabil terbaru saat evaluasi (20 Nov 2026) | **0.8.39**                                                                     |
| Tanggal rilis 0.8.39                             | 19 November 2026                                                               |
| Commit compiler (dari metadata artefak)          | `0.8.39+commit.ce47f2c8`                                                       |
| Rilis sebelumnya                                 | 0.8.38 (22 Okt 2026) — memperbaiki `YulOptimizerKnowledgeBaseStaleBookkeeping` |
| Rilis berikutnya                                 | 0.9.0 (belum ada tanggal; pre-release direncanakan)                            |

Sumber: pengumuman rilis resmi soliditylang.org (0.8.38 dan 0.8.39),
daftar bug resmi docs.soliditylang.org (`bugs.html`, dokumen
0.8.40-develop, diperiksa 20 Nov 2026). Tidak ada rilis stabil setelah
0.8.39 pada tanggal evaluasi; dokumentasi develop sudah berada di
0.8.40-develop tetapi 0.8.40 belum dirilis.

Catatan "baru rilis": 0.8.39 berusia 1 hari saat evaluasi ini. Risiko
"soak time" komunitas yang singkat dimitigasi langsung oleh evaluasi
ini sendiri — build + test penuh + fuzz 10k + audit bytecode + audit
bug compiler, semuanya dijalankan terhadap 0.8.39 dan semuanya hijau
(§4–§8). Changelog 0.8.39 juga kecil dan didominasi perbaikan bug
(§8.3): tidak ada fitur bahasa baru yang menyentuh kode AGENTHUB.

## 3. Metode & lingkungan

- **Salinan kerja:** `git worktree` dari HEAD `5723ff3` di
  `~/workspace/.tmp/phase8-solc-eval/` (detached HEAD, submodule
  di-init). Semua eksperimen solc dilakukan di sana; repo utama hanya
  dibaca (kecuali laporan ini).
- **Satu-satunya perubahan di salinan kerja:**
  `packages/contracts/foundry.toml` baris 5:
  `solc_version = "0.8.24"` → `solc_version = "0.8.39"`.
  Tidak ada perubahan kode, pragma, remapping, atau pengaturan lain.
- **Baseline 0.8.24:** artefak build Phase 7 di worktree
  `~/workspace/.tmp/phase7-bytecode/` (HEAD `5723ff3`, tanpa perubahan)
  — dipakai ulang setelah verifikasi hash SHA-256 runtime keempat
  kontrak cocok PERSIS dengan hash yang diterbitkan laporan Phase 7
  (§6 findings/06). Baseline tidak perlu di-build ulang; ini juga
  menghindari build via-IR paralel kedua di VM 1,5 CPU.
- **Toolchain:** forge 1.9.0 (sama dengan pin CI), cast 1.9.0,
  Python 3.12. Build dijalankan berurutan, tanpa build paralel lain
  yang berjalan bersamaan (dicek via `ps` sebelum build).
- **Scanner opcode:** `phase8-bytecode-audit.py` (salinan
  `~/workspace/.tmp/phase7-bytecode-audit.py` dengan label diperbarui)
  — memotong metadata CBOR sebelum disassembly linear yang melewati
  data PUSH; angka opcode kanonik (MCOPY `0x5e`, TSTORE `0x5d`,
  TLOAD `0x5c`, BLOBHASH `0x49`, BLOBBASEFEE `0x4a`). Cross-check
  independen dengan `cast disassemble` atas bagian kode saja.
- **Pemeriksaan bug compiler:** daftar resmi
  docs.soliditylang.org/en/latest/bugs.html (67 entri, dibaca
  seluruhnya untuk rentang fixed 0.8.25–0.8.39) + pengumuman rilis
  0.8.38/0.8.39 + basis data bug Etherscan sebagai cross-check.

## 4. Hasil build

|                       | Baseline 0.8.24 (Phase 7)                                                                                                                | Kandidat 0.8.39                                                           |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `forge build`         | exit 0                                                                                                                                   | **exit 0**                                                                |
| Durasi solc (94 file) | ~303–313 dtk (klaim Phase 6 303 dtk; ukur Phase 7 5 mnt 13 dtk CPU)                                                                      | **184,56 dtk**                                                            |
| Durasi wall total     | 12 mnt 27 dtk (di bawah beban 3 build paralel)                                                                                           | **198 dtk** (3 mnt 18 dtk, tanpa beban paralel)                           |
| Warning lint forge    | 23 (7 `block-timestamp`, 8 `environment-read-across-mutation`, 3 `reentrancy-events`, 2 `reentrancy-no-eth`, 3 `require-revert-in-loop`) | **23 — identik, jumlah maupun jenisnya**                                  |
| Warning solc baru     | —                                                                                                                                        | **9× `Warning (8506)`: "Experimental pragma ABIEncoderV2 is deprecated"** |

**Build ~37% lebih cepat** pada 0.8.39 (184,56 dtk vs ~303–313 dtk
waktu solc) — konsisten dengan perbaikan performa DataFlowAnalyzer di
0.8.38 ("compilation with the Yul optimizer enabled is faster").
Perbandingan wall time tidak apple-to-apple karena beban paralel Phase 7,
tetapi waktu solc adalah perbandingan yang adil dan menunjukkan
percepatan nyata. Timeout CI (20 menit job `contracts`, 30 menit job
`fuzz`) mendapat margin yang lebih besar.

**Satu-satunya warning baru (8506)** berasal SEMATA-MATA dari
`lib/forge-std` (9 file: `StdAssertions`, `StdCheats`,
`StdInvariant`, `StdJson`, `StdToml`, `StdUtils`, `Test`, `Vm`,
`IMulticall3` + salinan di bawah `lib/openzeppelin-contracts/lib/`).
Grep `pragma experimental ABIEncoderV2` di `src/`, `test/`, dan
`script/` AGENTHUB: **nol**. Pragma itu redundan sejak ABI coder v2
menjadi default (0.8.0); deprecation warning-nya ditambahkan solc
0.8.31 sebagai bagian dari batch deprecation menuju 0.9.0. Dampak:
kosmetik saja — kompilasi berhasil, tidak ada perubahan perilaku.
Tidak ada tindakan yang diperlukan (warning akan hilang saat forge-std
menghapus pragma itu; bukan alasan menahan upgrade).

**Metadata artefak kandidat terverifikasi:** compiler
`0.8.39+commit.ce47f2c8`, `evmVersion: cancun`, `viaIR: true`,
optimizer enabled runs 200 — semua pengaturan identik dengan baseline
kecuali versi solc.

## 5. Hasil test & fuzz & gas

Perintah persis CI (`contracts` dan `fuzz` jobs), dijalankan di
salinan kerja 0.8.39:

| Suite                                         | Baseline 0.8.24 (Phase 7, §8)                    | Kandidat 0.8.39                                                |
| --------------------------------------------- | ------------------------------------------------ | -------------------------------------------------------------- |
| `forge test`                                  | 287 lulus, 0 gagal, 0 skip (20 suite, 77,88 dtk) | **287 lulus, 0 gagal, 0 skip (20 suite, 124,96 dtk)** — exit 0 |
| `forge test --fuzz-runs 10000 --fuzz-seed 42` | 287 lulus, 0 gagal, 0 skip                       | **287 lulus, 0 gagal, 0 skip (20 suite, 154,71 dtk)** — exit 0 |

Selisih durasi test (124,96 dtk vs 77,88 dtk) adalah varians beban VM
(1,5 CPU bersama), bukan regresi: jumlah test dan hasilnya identik,
dan tidak ada satu pun test yang gagal atau di-skip di kedua run.
Fuzz 10k dengan seed 42 yang di-pin CI lolos penuh — tidak ada
kegagalan transien seperti yang pernah didokumentasikan
(`REGRESSION_RESULTS.md` §4.4).

### 5.1 Gas completion (pengukuran `gasleft()`, metodologi sama dengan log 16 Phase 7)

| Pengukuran                                  | Baseline 0.8.24 | Kandidat 0.8.39 |         Delta |
| ------------------------------------------- | --------------: | --------------: | ------------: |
| Threshold-1 completion                      |         242.735 |     **242.574** | −161 (−0,07%) |
| Threshold-2 completion                      |         253.867 |     **253.482** | −385 (−0,15%) |
| Threshold-3 completion                      |         265.221 |     **264.609** | −612 (−0,23%) |
| Biaya marginal per signature ekstra (T2−T1) |          11.132 |      **10.908** |          −224 |

Gas TURUN di semua threshold — konsisten dengan dua perubahan codegen
0.8.38: dispatcher IR memakai satu instruksi lebih sedikit per panggilan
eksternal (`gt(calldatasize(), 3)` menggantikan
`iszero(lt(calldatasize(), 4))`), dan MCOPY lebih murah daripada loop
MLOAD/MSTORE yang digantikannya. Angka gas headline Phase 6/7
(242.735 / 253.867 / 265.221) harus diperbarui ke angka baru bila
upgrade diterapkan (lihat §9).

## 6. Perbandingan bytecode

Sumber tidak berubah satu baris pun antara kedua build — seluruh delta
di bawah ini adalah efek murni codegen solc 0.8.39 vs 0.8.24.

### 6.1 Runtime bytecode vs batas EIP-170 (24.576 byte)

| Kontrak      | Baseline 0.8.24 | % batas | Kandidat 0.8.39 | % batas |             Delta |
| ------------ | --------------: | ------: | --------------: | ------: | ----------------: |
| AgentGate    |           1.069 |   4,35% |           1.058 |   4,31% |      −11 (−1,03%) |
| QuestManager |          12.272 |  49,93% |          11.684 |  47,54% | **−588 (−4,79%)** |
| Reputation   |           2.218 |   9,03% |           2.255 |   9,18% |      +37 (+1,67%) |
| Achievement  |           6.010 |  24,45% |           5.980 |  24,33% |      −30 (−0,50%) |

Semua kontrak tetap jauh di bawah batas. QuestManager — kontrak
terbesar dan satu-satunya yang dipantau pertumbuhannya (PH7-I12) —
justru MENGECIL 588 byte; headroom naik dari 12.304 menjadi 12.892
byte.

### 6.2 Creation bytecode (initcode) vs batas EIP-3860 (49.152 byte)

| Kontrak      | Baseline 0.8.24 | % batas | Kandidat 0.8.39 | % batas |         Delta |
| ------------ | --------------: | ------: | --------------: | ------: | ------------: |
| AgentGate    |           1.499 |   3,05% |           1.457 |   2,96% |  −42 (−2,80%) |
| QuestManager |          14.155 |  28,80% |          13.404 |  27,27% | −751 (−5,31%) |
| Reputation   |           2.540 |   5,17% |           2.584 |   5,26% |  +44 (+1,73%) |
| Achievement  |           7.072 |  14,39% |           7.093 |  14,43% |  +21 (+0,30%) |

Semua aman, jauh di bawah batas.

### 6.3 Hash SHA-256 runtime (perubahan kode vs metadata)

| Kontrak      | SHA-256 baseline 0.8.24                                            | SHA-256 kandidat 0.8.39                                            | Identik? |
| ------------ | ------------------------------------------------------------------ | ------------------------------------------------------------------ | -------- |
| AgentGate    | `e990c4fc2653f624a5638c593ce1d263158229e9abbdb1ddb5f2d1670b3d82a6` | `adb2e727d223a34f9a81ea9f886cee76d9020c939ef43f29ea81b974dffb32d8` | Tidak    |
| QuestManager | `ce2e7168128e93c28b1a86b33cd06a0e89cd87f2004b43bad888703f2a3501a3` | `1d3bc4a022355aec209250fbb4a1fe7c60f6c6ae8350b00083ddc7bdce96d838` | Tidak    |
| Reputation   | `f75326eb3f94b187f0b93be4099465bdd2df37ec4bd948b308e94fde1e3a4b4d` | `2444f4eacd0b2dd28081021be417f9dea1f637ad98e2eb1d0202a3c9619c0258` | Tidak    |
| Achievement  | `1beab180e8cc2801a2b868150b39e974a16fa08219ae06fb3e8973dd951cba0f` | `573798624966597e98924058912ddb84f42efd41566a4e843eb2de291dcfa905` | Tidak    |

Bytecode keempat kontrak berubah — sudah diduga (upgrade solc mengubah
seluruh bytecode, seperti via-IR di Phase 6). Pemisahan kode vs
metadata:

- **Metadata CBOR:** 51 byte di kedua build, struktur identik
  (`a2 64 "ipfs" 58 22 1220 <hash> 64 "solc" 43 <versi>` + sufiks
  `0033`). Byte versi berubah `000818` (0.8.24) → `000827` (0.8.39)
  — sesuai harapan. Hash IPFS berbeda (mencakup pengaturan kompilasi).
- **Bagian kode saja juga berubah** (bukan hanya metadata): jumlah
  instruksi berubah di semua kontrak (AgentGate 530→521, QuestManager
  7.728→7.211, Reputation 1.343→1.303, Achievement 3.804→3.746) dan
  histogram opcode bergeser substansial (mis. QuestManager:
  `SWAP1 0x90` +101, `DUP2 0x81` +97, `ADD 0x01` +76, `PUSH0 0x5f`
  −73 — tanda codegen yang benar-benar berbeda, bukan tambalan kecil).
- **Linking:** `linkReferences` kosong di semua artefak kandidat;
  tidak ada placeholder library (cek regex placeholder sungguhan:
  nol hit — flag `__` pada skrip audit adalah false positive dari
  byte `PUSH0 PUSH0`, sudah dikonfirmasi).

### 6.4 ABI: identik

ABI hasil kompilasi kandidat vs baseline: **identik field-per-field
untuk keempat kontrak** (AgentGate 18 entri, QuestManager 89,
Reputation 33, Achievement 61 — total 201, sama dengan hitungan
Phase 7). Konsekuensi: ABI frontend yang di-commit di
`apps/web/lib/abis/*.ts` tetap valid tanpa regenerasi; paritas ABI
0 drift yang dibuktikan Phase 7 tetap berlaku di bawah 0.8.39.
(Catatan: `export-abis.mjs` mengekspor ABI saja, jadi output-nya akan
byte-identik; yang berubah hanya metadata artefak `out/`.)

## 7. Opcode scan Cancun-only — TEMUAN: MCOPY kini NYATA di kode

Metode yang benar (seperti Phase 7, bukan metode Phase 5/6):
disassembly linear bagian KODE saja (metadata CBOR dipotong dulu),
melewati data immediat PUSH1–PUSH32; cross-check independen dengan
`cast disassemble` atas bagian kode saja. Angka kanonik: MCOPY `0x5e`,
TSTORE `0x5d`, TLOAD `0x5c`, BLOBHASH `0x49`, BLOBBASEFEE `0x4a`
(PH7-I10 — angka `0x27` dalam brief lama adalah salah).

| Kontrak                                 |    Baseline 0.8.24 |                   Kandidat 0.8.39 |
| --------------------------------------- | -----------------: | --------------------------------: |
| AgentGate                               |                  0 |                                 0 |
| QuestManager                            |                  0 |  **1× MCOPY (PC 1723 / `0x6bb`)** |
| Reputation                              |                  0 |                                 0 |
| Achievement                             |                  0 | **1× MCOPY (PC 4292 / `0x10c4`)** |
| TSTORE / TLOAD / BLOBHASH / BLOBBASEFEE | 0 di semua kontrak |                0 di semua kontrak |

**Verifikasi bahwa kedua MCOPY ini instruksi nyata, bukan false
positive metadata (kesalahan Phase 5/6):**

1. Keduanya ditemukan SETELAH metadata dipotong (kode QuestManager
   berakhir di offset 11.631; PC 1723 jauh di dalam kode. Kode
   Achievement berakhir di offset 5.927; PC 4292 di dalam kode).
2. `cast disassemble` atas bagian kode saja mengonfirmasi:
   QuestManager `000006bb: MCOPY`, Achievement `000010c4: MCOPY`.
3. Konteks disassembly di kedua kontrak IDENTIK — pola helper
   penyalin memori hasil codegen: `MLOAD` panjang → `MSTORE` panjang
   → hitung alamat → `MCOPY` → `MSTORE` padding nol → bulatkan ke
   32 byte. Ini adalah fungsi utilitas Yul `copy_memory_to_memory`
   yang dipakai codegen IR untuk menyalin data dinamis di memori
   (mis. parameter `string`/`bytes[]` dan nilai kembalian dinamis).
   sourceMap menempatkannya di kode compiler-generated (entri
   `-1:-1:-1` di sebelahnya; tidak ada pemetaan ke satu baris sumber).
4. Raw-hex grep (metode yang SALAH) memberi angka yang menyesatkan
   seperti biasa (mis. QuestManager kandidat: MCOPY=9, TSTORE=8 —
   semuanya byte di dalam data PUSH/metadata); hanya disassembly
   bagian kode yang dipakai untuk kesimpulan.

**Mengapa MCOPY muncul sekarang:** sejak solc 0.8.25 ("MCOPY in code
generator", pengumuman rilis 0.8.25), codegen memakai MCOPY untuk
helper penyalin memori bila `evm_version` mengizinkannya
(Cancun+). Build 0.8.24 tidak memakainya; build 0.8.39 memakainya.
Ini perubahan codegen yang disengaja dan didokumentasikan upstream,
bukan anomali.

**Penilaian dampak — BUKAN blocker:**

- MCOPY (EIP-5656) adalah opcode Cancun. **Cancun sudah TERBUKTI
  aktif di BSC testnet dan mainnet** (validasi sebelumnya; dicatat di
  memori proyek). Kontrak yang memakai MCOPY dapat di-deploy dan
  dijalankan di BSC.
- Seluruh test suite (287 test + fuzz 10k) berjalan di Anvil dengan
  Cancun aktif dan lolos — jalur yang melewati helper MCOPY
  (completion dengan `bytes[] signatures`, pembacaan quest dengan
  `string`, dsb.) sudah dieksekusi dalam test.
- Gas completion TURUN (§5.1), sebagian karena MCOPY lebih murah
  daripada loop yang digantikannya.

**Tetapi dua tindak lanjut WAJIB bila upgrade diterapkan:**

1. **Perbarui komentar `foundry.toml`** (baris 11–12): klaim "Our
   contracts use no transient storage and no Cancun-only opcodes"
   menjadi SALAH di bawah 0.8.39. Komentar harus menyatakan bahwa
   kontrak kini memakai MCOPY (1× QuestManager, 1× Achievement) dan
   bergantung pada dukungan Cancun BSC.
2. **Smoke test testnet harus mencakup jalur completion** (sudah
   direncanakan sebagai syarat penutupan R-010) — jalur itu melewati
   helper MCOPY, sehingga smoke test sekaligus membuktikan dukungan
   MCOPY di BSC testnet live. Catatan Phase 7 bahwa "tes dukungan
   opcode Cancun tidak lagi esensial" (karena 0 opcode) TIDAK LAGI
   BERLAKU di bawah 0.8.39.

## 8. Analisis bug compiler

Sumber: daftar resmi docs.soliditylang.org (`bugs.html`,
0.8.40-develop) + pengumuman rilis 0.8.36/0.8.37/0.8.38/0.8.39 +
basis data bug Etherscan (cross-check). Seluruh entri dengan
`fixed` di 0.8.25–0.8.39 diperiksa; entri dengan `fixed` ≤ 0.8.23
sudah diperbaiki di 0.8.24 sehingga tidak relevan.

### 8.1 Bug yang memengaruhi 0.8.24 dan diperbaiki oleh 0.8.39

| Bug (UID)                                                                     | Severity   |  Diperkenalkan | Diperbaiki | Berlaku untuk AGENTHUB?                                                                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------- | ---------- | -------------: | ---------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `YulOptimizerKnowledgeBaseStaleBookkeeping` (SOL-2026-7)                      | low        |         0.8.19 | **0.8.38** | **TIDAK DAPAT DISINGKIRKAN (PH7-L13).** Kondisi: `yulOptimizer: true`. "In optimized IR code generation, any code may be affected, including code without inline assembly." AGENTHUB memakai via-IR + optimizer → terpapar secara teori. Ini satu-satunya bug 0.8.24 yang tidak bisa disingkirkan statis.                 |
| `OverlappingRecursiveStorageStructCopyCorruption` + varian ViaIR (SOL-2026-8) | medium     | 0.4.9 / 0.8.13 | **0.8.39** | TIDAK BERLAKU. Membutuhkan struct rekursif (struct yang memuat tipenya sendiri via array dinamis/mapping) + copy storage-ke-storage yang tumpang tindih. Struct AGENTHUB (`Badge`, `Quest`, `ValidatorInfo`) semuanya flat — diverifikasi dari sumber; struct OZ yang terkompilasi (mis. `RoleData`) juga tidak rekursif. |
| `UnsoundSpillInMutualRecursion` (SOL-2026-2)                                  | medium     |          0.7.2 |     0.8.36 | TIDAK BERLAKU. Membutuhkan fungsi internal yang saling rekursif; graf panggilan AGENTHUB adalah DAG tanpa rekursi (diverifikasi Phase 7, findings/06 F2).                                                                                                                                                                 |
| `SpillSlotCollisionAcrossMutualRecursion` (SOL-2026-4)                        | low/medium |          0.7.2 |     0.8.37 | TIDAK BERLAKU. Alasan sama (rekursi timbal balik).                                                                                                                                                                                                                                                                        |
| `LostStorageArrayWriteOnSlotOverflow` (SOL-2025-1)                            | low        |          0.1.0 |     0.8.32 | TIDAK BERLAKU praktis. Membutuhkan array yang melintasi ujung storage (slot 2²⁵⁶) — "extremely unlikely to be triggered accidentally".                                                                                                                                                                                    |
| `MemoryByteArrayElementDeleteClearsWholeWord` (SOL-2026-5)                    | low/medium |      pra-0.1.0 |     0.8.37 | TIDAK BERLAKU. Hanya pipeline evmasm (`viaIR: false`); AGENTHUB memakai via-IR. Juga: 0 kemunculan `delete` di `src/`.                                                                                                                                                                                                    |

Tiga bug lain yang diperbaiki di rentang ini TIDAK PERNAH memengaruhi
0.8.24 karena diperkenalkan setelahnya, tetapi relevan sebagai bukti
bahwa upgrade melewati versi-versi itu aman: `TransientStorageClearingHelperCollision`
(high, diperkenalkan 0.8.28, diperbaiki 0.8.34 — membutuhkan
`transient` + `delete`, keduanya 0 di `src/`);
`InheritanceOrderReversalOnStorageEndWarning` (medium, diperkenalkan
0.8.29, diperbaiki 0.8.36 — membutuhkan layout storage kustom di
2⁶⁴ slot terakhir); `MisorderedNamedParametersInRequireWithCustomErrors`
(very low, diperkenalkan 0.8.26, diperbaiki 0.8.37 — membutuhkan
`require(cond, Error({...}))`; grep `require(` di `src/`: nol).

### 8.2 Bug yang memengaruhi 0.8.39: TIDAK ADA

Pemeriksaan daftar resmi (diakses 20 Nov 2026, dokumen
0.8.40-develop):

- Entri terbaru adalah SOL-2026-8, `fixed: 0.8.39`.
- **Tidak ada satu pun entri** dengan `fixed` 0.8.40 atau lebih baru,
  dan tidak ada entri tanpa versi perbaikan.
- **Tidak ada bug yang diperkenalkan di 0.8.38 atau 0.8.39** dalam
  daftar (versi `introduced` terbaru adalah 0.8.29 untuk SOL-2026-3).

Jadi 0.8.39 — pada tanggal evaluasi — adalah versi dengan NOL bug
yang diketahui dalam daftar resmi Solidity. (Kualifikasi yang jujur:
daftar ini hanya mencakup bug yang sudah diketahui; bug yang belum
ditemukan tidak bisa disingkirkan untuk versi mana pun, termasuk
0.8.39 yang baru berusia 1 hari. Mitigasi: pin versi + baterai test
penuh + pemantauan pengumuman Solidity sebelum deploy mainnet.)

### 8.3 Perubahan lain di changelog 0.8.38/0.8.39 yang relevan

- **0.8.38:** perbaikan bug Yul optimizer (§8.1); performa
  DataFlowAnalyzer (build lebih cepat, §4); dispatcher IR satu
  instruksi lebih hemat (gas turun, §5.1); warning untuk identifier
  Yul `swapn`/`dupn`/`exchange` (tidak dipakai AGENTHUB — tidak ada
  inline assembly/Yul di `src/`).
- **0.8.39:** perbaikan SOL-2026-8 — fix ini menambahkan runtime
  overlap check pada SETIAP copy storage-ke-storage struct rekursif
  (biaya gas tambahan + pemakaian stack). **Tidak berpengaruh pada
  AGENTHUB** karena tidak ada struct rekursif — tidak ada copy yang
  dikenai check itu. Perbaikan miscompilation tuple bersarang
  (evmasm only — AGENTHUB via-IR, tidak berlaku). Warning ukuran kode
  64 KiB/128 KiB hanya untuk `--evm-version amsterdam` (AGENTHUB
  mem-pin `cancun` — tidak berlaku). Fitur ethdebug eksperimental
  (tidak dipakai).
- **Catatan non-daftar-bug:** sebuah artikel pihak ketiga
  (rya-sge.github.io, 4 Nov 2026) melaporkan kombinasi
  `--optimize --no-optimize-yul` berhenti dengan internal compiler
  error pada 0.8.23–0.8.38. Tidak relevan: AGENTHUB tidak memakai
  kombinasi flag itu (optimizer default Foundry), dan ICE menghentikan
  kompilasi — tidak menghasilkan bytecode yang salah.

## 9. Perubahan lain yang diperlukan bila upgrade diterapkan

| #   | Perubahan                                                                                     | Wajib?          | Keterangan                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --- | --------------------------------------------------------------------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `packages/contracts/foundry.toml`: `solc_version = "0.8.39"`                                  | **Ya**          | Satu baris. Satu-satunya perubahan fungsional.                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 2   | `foundry.toml`: perbarui komentar baris 11–12 ("no Cancun-only opcodes")                      | **Ya**          | Klaim itu menjadi salah (§7). Nyatakan MCOPY 1× QuestManager + 1× Achievement + ketergantungan pada Cancun BSC.                                                                                                                                                                                                                                                                                                                                                     |
| 3   | Versi Foundry di CI (`FOUNDRY_VERSION: 1.9.0`)                                                | Tidak           | CI tidak mem-pin solc secara terpisah — `foundry-toolchain` hanya mem-pin Foundry; solc diambil dari `foundry.toml`. Foundry 1.9.0 sudah terbukti mengunduh dan memakai solc 0.8.39 (build evaluasi ini). Tidak ada perubahan `.github/workflows/ci.yml`.                                                                                                                                                                                                           |
| 4   | Pragma di file kontrak (`pragma solidity ^0.8.24`, 43 file: 11 `src/` + 32 `test/`/`script/`) | Tidak           | Rentang caret `^0.8.24` mengizinkan 0.8.39 (< 0.9.0) — build membuktikan. Opsional: naikkan floor ke `^0.8.39` sebagai dokumentasi "compiler minimum yang aman" (43 file, perubahan kosmetik; bukan persyaratan fungsional karena `solc_version` sudah mem-pin).                                                                                                                                                                                                    |
| 5   | Remapping                                                                                     | Tidak           | Tidak berubah (`@openzeppelin/`, `@agenthub/`).                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 6   | ABI frontend (`apps/web/lib/abis/*.ts`)                                                       | Tidak           | ABI identik (§6.4) — tidak perlu regenerasi.                                                                                                                                                                                                                                                                                                                                                                                                                        |
| 7   | Dokumen hidup yang menyebut 0.8.24                                                            | Ya (ringan)     | `docs/SECURITY_THREAT_MODEL.md:262`, `docs/SECURITY_TEST_PLAN.md:35,50`, `docs/SECURITY_FINDINGS.md:209-210,221`, `docs/REGRESSION_RESULTS.md:188`, komentar `packages/contracts/script/export-abis.mjs:63`. Perbarui ke 0.8.39 + angka gas baru (§5.1) + MCOPY (§7). Dokumen historis (`PHASE1_AUDIT.md`, `security-review-package/`, `security-retest-report/`, `agenthub-final-*/`, `NEXT_PHASE_VALIDATION.md`) adalah catatan keadaan saat itu — JANGAN diubah. |
| 8   | Checklist deploy (`FINAL_DEPLOYMENT_CHECKLIST.md` dkk.)                                       | Ya (ringan)     | Verifikasi BscScan harus memakai settings baru (solc 0.8.39, via-IR, optimizer 200, evm cancun) — settings harus identik atau verifikasi gagal "bytecode mismatch" (PH7-L22).                                                                                                                                                                                                                                                                                       |
| 9   | Re-run Slither + vitest parity + E2E pada build 0.8.39 sebelum merge                          | **Ya**          | Di luar cakupan evaluasi ini (hanya build/test/fuzz/bytecode). Slither 0.11.6 + crytic-compile memakai artefak forge; vitest parity membandingkan ABI yang identik (§6.4) sehingga diharapkan tetap 5/5; wallet E2E + anvil integration memakai build baru. Semua harus hijau sebelum merge — tugas worker remediasi, bukan evaluasi ini.                                                                                                                           |
| 10  | Regenerasi `PACKAGE_MANIFEST.md`                                                              | Ya (prosedural) | Perubahan `foundry.toml` + dokumen mengubah manifest; regenerasi mengikuti prosedur commit yang berlaku.                                                                                                                                                                                                                                                                                                                                                            |
| 11  | Smoke test testnet mencakup jalur completion (MCOPY)                                          | **Ya**          | Syarat R-010 yang sudah ada; kini sekaligus membuktikan dukungan MCOPY di BSC testnet live (§7).                                                                                                                                                                                                                                                                                                                                                                    |

Tidak diperlukan: perubahan dependensi (OZ 5.0.2 pragma `^0.8.20`
kompatibel), perubahan script deploy, perubahan konfigurasi
optimizer/`evm_version`/`via_ir`.

## 10. Risiko sisa setelah upgrade

1. **Usia rilis 1 hari.** 0.8.39 dirilis 19 Nov 2026; belum ada soak
   time komunitas. Bug yang ditemukan kemudian (seperti pola
   0.8.32→0.8.33 hotfix) akan ditangani dengan upgrade pin berikutnya.
   Mitigasi yang sudah ada: baterai penuh + fuzz + audit bytecode
   dalam evaluasi ini; pin versi membuat rollback ke 0.8.38 trivial
   bila diperlukan (dengan catatan 0.8.38 masih terpapar SOL-2026-8
   medium — yang tidak berlaku untuk kode ini).
2. **Ketergantungan MCOPY pada Cancun BSC.** Kini kontrak benar-benar
   mengeksekusi opcode Cancun. Dukungan Cancun di BSC sudah terbukti
   aktif (testnet + mainnet), dan smoke test testnet akan membuktikannya
   lagi di jalur live sebelum mainnet. Bila — bertentangan dengan bukti
   — sebuah chain target ternyata tidak mendukung Cancun, deployment di
   chain itu akan gagal; mitigasi: `evm_version` tetap `cancun` secara
   eksplisit dan chain target adalah BSC saja.
3. **Bytecode berubah total.** Semua hash bytecode Phase 6/7 menjadi
   historis; bukti audit yang mengutip hash 0.8.24 harus dibaca sebagai
   bukti untuk build lama. Tidak ada deployment mainnet yang ada
   sehingga tidak ada masalah migrasi (sesuai catatan Phase 6).
4. **Bug compiler yang belum diketahui.** Berlaku untuk versi mana pun,
   termasuk 0.8.39. Daftar resmi hanya mencatat yang diketahui.
   Mitigasi: pantau pengumuman Solidity sebelum deploy mainnet;
   pertahankan pin + re-validasi pada setiap perubahan pin.
5. **Warning 8506 baru (kosmetik).** 9 warning dari forge-std; tidak
   memengaruhi build. Bila CI di masa depan memberlakukan
   warnings-as-errors, warning ini harus ditangani di sisi dependensi.

## 11. Langkah penerapan yang disarankan

1. Terapkan perubahan #1, #2, #7, #8, #10 dari §9 dalam satu commit
   ("chore(contracts): upgrade solc 0.8.24 → 0.8.39").
2. Jalankan baterai penuh di commit itu: `forge build`, `forge test`,
   `forge test --fuzz-runs 10000 --fuzz-seed 42`, Slither, vitest
   (web + shared), E2E smoke + wallet, anvil integration — semua harus
   hijau (item #9 §9).
3. Dorong ke GitHub; CI harus hijau 10/10 (job `contracts` dan `fuzz`
   akan mengunduh solc 0.8.39 otomatis dari `foundry.toml`).
4. Perbarui angka gas headline (242.574 / 253.482 / 264.609) di dokumen
   yang mengutip angka lama.
5. Tutup PH7-L13 sebagai FIXED (dengan referensi laporan ini); catat
   MCOPY sebagai perubahan perilaku codegen di
   `SECURITY_DEPLOYMENT_GATE.md` / checklist smoke test.
6. Jangan deploy testnet dari build 0.8.24 setelah upgrade di-merge —
   semua deployment memakai build 0.8.39 yang terverifikasi.

## 12. Artefak & jejak audit

- Salinan kerja (worktree, HEAD `5723ff3` + `solc_version` 0.8.39):
  `~/workspace/.tmp/phase8-solc-eval/`
- Log build kandidat: `~/workspace/.tmp/phase8-solc-eval/build-0.8.39.log`
  (exit 0, wall 198 dtk, solc 184,56 dtk, 94 file)
- Log test: `~/workspace/.tmp/phase8-solc-eval/test-0.8.39.log`
  (287/287, 124,96 dtk)
- Log fuzz: `~/workspace/.tmp/phase8-solc-eval/fuzz-0.8.39.log`
  (287/287, 10.000 run, seed 42, 154,71 dtk)
- Log gas: `~/workspace/.tmp/phase8-solc-eval/gas-0.8.39.log`
  (242.574 / 253.482 / 264.609)
- Output audit bytecode: `~/workspace/.tmp/phase8-solc-eval/bytecode-compare-0.8.39.txt`
- Skrip audit: `~/workspace/.tmp/phase8-solc-eval/phase8-bytecode-audit.py`
  (salinan `~/workspace/.tmp/phase7-bytecode-audit.py`, label diperbarui)
- Baseline 0.8.24: `~/workspace/.tmp/phase7-bytecode/packages/contracts/out/`
  (hash terverifikasi cocok dengan laporan Phase 7)
- Referensi bug compiler:
  - https://docs.soliditylang.org/en/latest/bugs.html
    (0.8.40-develop, diakses 20 Nov 2026)
  - https://www.soliditylang.org/blog/2026/10/22/solidity-0.8.38-release-announcement/
  - https://www.soliditylang.org/blog/2026/11/19/solidity-0.8.39-release-announcement/
  - https://www.soliditylang.org/blog/2026/10/22/yul-optimizer-knowledge-base-stale-bookkeeping-bug/
  - https://etherscan.io/solcbuginfo (cross-check)

---

_Evaluasi selesai 20 November 2026. Rekomendasi: UPGRADE ke solc 0.8.39.
PH7-L13 dapat ditutup sebagai FIXED setelah penerapan + re-validasi §11._
