# Gas Benchmark — AGENTHUB Phase 8 (final)

**Tanggal:** 20 November 2026.
**Metode:** sama dengan Phase 6/7 — pengukuran `gasleft()` di
`test/ThresholdAttestation.t.sol`, perintah `forge test --match-test testGas -vv`.
Angka headline diambil dari test individual (bukan test marginal — lihat catatan).
Log mentah: `logs/16-gas-benchmark.log`.

## Hasil

| Pengukuran                            | Phase 6 baseline (0.8.24, kode lama) | Worker A: kode Phase 8 @ 0.8.24 | **Phase 8 final (kode Phase 8 @ 0.8.39)** |    Δ vs Phase 6 |
| ------------------------------------- | -----------------------------------: | ------------------------------: | ----------------------------------------: | --------------: |
| Threshold-1 completion                |                              242.735 |                         244.966 |                               **244.840** | +2.105 (+0,87%) |
| Threshold-2 completion                |                              253.867 |                         256.098 |                               **255.766** | +1.899 (+0,75%) |
| Threshold-3 completion                |                              265.221 |                         267.452 |                               **266.911** | +1.690 (+0,64%) |
| Marginal per signature ekstra (T2−T1) |                               11.132 |                          11.132 |                                **10.926** |            −206 |
| Marginal per signature ekstra (T3−T2) |                               11.354 |                          11.354 |                                **11.145** |            −209 |

Test marginal pada run yang sama: t1 244.840 / t2 255.767 / t3 266.919,
marginal t1→t2 10.927, t2→t3 11.152. Selisih +0/+1/+8 vs test individual
adalah artefak setup yang sama seperti Phase 7 (253.868 vs 253.867,
265.229 vs 265.221) — bukan anomali.

## Dekomposisi delta

| Komponen                                                      |     T1 |     T2 |     T3 | Keterangan                       |
| ------------------------------------------------------------- | -----: | -----: | -----: | -------------------------------- |
| **Efek kode Phase 8** (Worker A − Phase 6, solc tetap 0.8.24) | +2.231 | +2.231 | +2.231 | **Konstan di semua threshold**   |
| **Efek solc** (final − Worker A, kode tetap Phase 8)          |   −126 |   −332 |   −541 | Membesar dengan jumlah signature |
| **Net vs Phase 6**                                            | +2.105 | +1.899 | +1.690 |                                  |

### Efek kode (+2.231, konstan): SLOAD L07

Kenaikan kode persis sama (+2.231) di T1/T2/T3 membuktikan biaya
tetap per completion, independen dari jumlah signature. Sumbernya
adalah perbaikan **PH7-L07** di `QuestManager._completeQuest`
(`src/QuestManager.sol:418-428`): guard anti-klaim-ganda
deactivate+recreate membaca `_supersedes[questId]` — **satu SLOAD
ekstra per completion**, cold ~2.100 gas pada completion pertama
(komentar di kode). Rinciannya: 2.100 (cold SLOAD) + ~131 (perbandingan
`supersededQuestId != 0`, branch, dan stack ops). SLOAD kedua
(`_completed[msg.sender][supersededQuestId]`) tidak terbayar dalam
pengukuran ini karena short-circuit: `supersededQuestId == 0` pada
quest gas test, sehingga guard berhenti setelah SLOAD pertama.

Perbaikan H01/M01/M02 tidak menyentuh jalur completion yang diukur:
H01/M02 adalah cek di `createQuest`, M01 di `revokeVerifier` — tidak
ada biaya gas completion dari ketiganya.

### Efek solc (−126 / −332 / −541): MCOPY + dispatcher IR

Upgrade 0.8.24 → 0.8.39 **menurunkan** gas pada kode yang sama, dan
penurunannya membesar dengan jumlah signature — konsisten dengan dua
perubahan codegen yang didokumentasikan Worker D
(`solc-evaluation.md` §5.1): (1) codegen ≥0.8.25 memakai **MCOPY**
untuk helper penyalin memori, menggantikan loop MLOAD/MSTORE saat
menyalin array `bytes[] signatures` (array lebih besar → penghematan
lebih besar); (2) dispatcher IR memakai satu instruksi lebih sedikit
per panggilan eksternal. Besaran efek ini (−0,05% / −0,13% / −0,20%)
sejalan dengan pengukuran murni-solc Worker D pada kode lama
(−161 / −385 / −612); selisih kecil wajar karena tata letak kode
berbeda setelah guard L07 ditambahkan. Biaya marginal per signature
ekstra turun ~200 gas (11.132 → 10.926) — jejak MCOPY yang sama.

### Kesimpulan

Kenaikan gas bersih Phase 8 (+0,64–0,87%) seluruhnya berasal dari
satu SLOAD dingin guard L07 — biaya keamanan yang disengaja dan
terdokumentasi di kode. Efek solc 0.8.39 justru menghemat gas dan
menutupi sebagian kenaikan itu. Tidak ada regresi gas tak terduga.
