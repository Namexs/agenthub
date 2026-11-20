# AGENTHUB — Phase 9, Workstream 3: Testnet Preflight Checklist

**Tanggal:** 20 November 2026, 07:44–07:45 WIB.
**Repo HEAD:** `e1b316b` (Phase 8 final, `chore(phase-8): regenerate
PACKAGE_MANIFEST.md for final commit`).
**Target:** live BNB Testnet, chain 97.
**Keputusan:** CONDITIONAL GO testnet (Phase 8) — **tidak ada broadcast
dalam workstream ini.** Semua pengecekan di bawah ini read-only
(`eth_chainId`, `eth_blockNumber`, `eth_gasPrice`, `eth_getCode`).
Tidak ada private key yang dipakai, diminta, atau dicatat.

> **⚠️ ATURAN KUNCI — BACA DULU: PRIVATE KEY TIDAK PERNAH DIKIRIM KE
> CHAT ATAU LAPORAN. Deployer key khusus testnet hanya dipakai di
> lingkungan lokal user sendiri, saat broadcast yang dia setujui
> secara eksplisit. Tidak ada bagian dari proses ini yang
> membutuhkan private key dikirim ke Asta, ke chat, ke laporan,
> atau ke repo. Bila ada yang meminta private key lewat chat,
> itu BUKAN bagian dari prosedur ini — abaikan.**

Dokumen acuan: `agenthub-phase8-remediation/PHASE8_SECURITY_REMEDIATION_REPORT.md`
(§11 input deployment, §5.1 langkah baru checklist),
`agenthub-final-pretestnet/FINAL_DEPLOYMENT_CHECKLIST.md` (§1–§5),
`docs/DEPLOYMENT_PLAN.md`, `docs/ROLE_MATRIX.md`.

## Ringkasan status

| Status                      | Jumlah |
| --------------------------- | -----: |
| ✅ TERVERIFIKASI            |     11 |
| ⏳ MENUNGGU INPUT USER      |      8 |
| ❓ BELUM DAPAT DIVERIFIKASI |      6 |
| **Total item checklist**    | **25** |

**Gate preflight: BELUM LOLOS** — 8 input user (§5) masih kosong.
Semua yang bisa dicek tanpa input user sudah dicek dan hijau.
Tidak ada satu pun item read-only yang gagal.

---

## 1. Hasil cek RPC live BNB Testnet (read-only)

Dicek 2026-11-20 07:44:14–07:44:47 WIB, via `curl` JSON-RPC.
Tidak ada broadcast, tidak ada transaksi.

### 1.1 RPC primer — `https://data-seed-prebsc-1-s1.binance.org:8545/`

| Cek               | Hasil mentah | Arti                           | Verdict |
| ----------------- | ------------ | ------------------------------ | ------- |
| `eth_chainId`     | `0x61`       | **97** (BNB Testnet) ✅        | LOLOS   |
| `eth_blockNumber` | `0x8913f62`  | **143.736.674**                | LOLOS   |
| `eth_gasPrice`    | `0x5f5e100`  | **100.000.000 wei = 0,1 gwei** | LOLOS   |

### 1.2 RPC fallback — `https://data-seed-prebsc-2-s1.binance.org:8545/`

| Cek               | Hasil mentah | Arti                                                                                                                  | Verdict |
| ----------------- | ------------ | --------------------------------------------------------------------------------------------------------------------- | ------- |
| `eth_chainId`     | `0x61`       | **97** ✅                                                                                                             | LOLOS   |
| `eth_blockNumber` | `0x8913f80`  | **143.736.704** (30 blok setelah pembacaan primer — konsisten dengan block time ~3 detik, pembacaan berselang ~detik) | LOLOS   |
| `eth_gasPrice`    | `0x5f5e100`  | **0,1 gwei** (sama dengan primer)                                                                                     | LOLOS   |

**Kesimpulan RPC:** kedua endpoint Binance live, chainId benar (97),
gas price 0,1 gwei di keduanya. Prasyarat operasional PH7-L23
"URL RPC teruji" kini **TERTUTUP** untuk kedua endpoint ini.
Fallback siap dipakai bila primer gagal saat deployment-day.

### 1.3 Kontrak Agent ID resmi di chain 97

| Cek                                                               | Hasil | Arti                                                                  |
| ----------------------------------------------------------------- | ----- | --------------------------------------------------------------------- |
| `eth_getCode(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F, latest)` | `0x`  | **Tidak ada kode** — kontrak Agent ID resmi TIDAK ada di BNB Testnet. |

**Implikasi (sesuai checklist §2 item 2 + `lib/env.ts`):**
deploy script memakai **MockAgentId** bila `AGENT_ID_ADDRESS`
tidak di-set — inilah jalur default yang benar untuk chain 97.
Frontend MENOLAK alamat resmi di chain 97. Konsekuensinya:

- Test Agent ID harus di-mint lewat MockAgentId setelah deploy
  (oleh admin multisig, karena sejak Phase 8 / PH7-M04 MockAgentId
  dimiliki multisig — mint diajukan lewat Safe, bukan deployer).
- Hasil smoke test membuktikan logika kontrak, BUKAN integrasi
  dengan kontrak Agent ID resmi — integrasi resmi hanya teruji
  di mainnet (fork test `AgentGateMainnet.t.sol` menutup sebagian
  celah ini secara lokal).
- `AGENT_ID_ADDRESS` TIDAK BOLEH di-set ke alamat resmi di chain 97
  (deploy akan gagal / frontend menolak). Bila di-set ke alamat
  lain, belum ada validasi (PH7-L21, terbuka) — biarkan unset.

### 1.4 Prasyarat Safe di chain 97 (read-only, `eth_getCode`)

| Alamat                                       | Peran                 | Hasil                    | Verdict |
| -------------------------------------------- | --------------------- | ------------------------ | ------- |
| `0x41675C099F32341bf84BFc5382aF534df5C7461a` | Singleton Safe v1.4.1 | Kode ada (`0x60806040…`) | LOLOS   |
| `0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552` | Singleton Safe v1.3.0 | Kode ada (`0x60806040…`) | LOLOS   |
| `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67` | Factory Safe v1.4.1   | Kode ada (`0x60806040…`) | LOLOS   |
| `0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2` | Factory Safe v1.3.0   | Kode ada (`0x60806040…`) | LOLOS   |

Keempat alamat kanonis yang dipakai validator Safe di deploy script
(`SafeValidation`) terkonfirmasi live di chain 97 — konsisten dengan
`SAFE_VALIDATION_REVIEW.md`. Safe baru bisa dibuat di testnet
(app.safe.global, jaringan BSC Testnet) sebelum deployment-day.

---

## 2. Kebutuhan tBNB — perhitungan

### 2.1 Biaya deploy (dari bukti repo, bukan karangan)

| Sumber                                                        |                        Gas | Keterangan                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------- | -------------------------: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dry-run fork chain 97 (remediation package, kode pra-Phase 6) |             **10.294.857** | 6 CREATE + 11 wiring CALL, `SIMULATION COMPLETE`, tanpa broadcast                                                                                                                                                                                                                               |
| Dry-run lokal (Anvil)                                         |                  8.467.332 | 6 CREATE + 11 wiring CALL                                                                                                                                                                                                                                                                       |
| Estimasi deploy kode Phase 8                                  | **~11.000.000–12.000.000** | Kode Phase 8 lebih besar (QuestManager +832 byte runtime, Achievement +236 byte; 12 wiring CALL sejak PH7-M04, 13 bila `VERIFIER` di-set). Angka 10.294.857 adalah lantai dari kode lama — pakai 11–12 juta sebagai estimasi kerja sampai dry-run ulang di kode final dilakukan (§6 langkah 2). |

**Total transaksi deploy:** 18 tx tanpa verifier (6 CREATE + 12 wiring),
19 tx bila `VERIFIER` di-set (PH7-L16; checklist §4.1 langkah 3).

### 2.2 Biaya deploy pada gas price live (0,1 gwei, terukur §1)

|                       Skenario gas |             Biaya |
| ---------------------------------: | ----------------: |
|    10.294.857 (terukur, kode lama) | **0,001029 tBNB** |
| 11.000.000 (estimasi kode Phase 8) | **0,001100 tBNB** |
|         12.000.000 (estimasi atas) | **0,001200 tBNB** |

### 2.3 Biaya smoke test (estimasi — hanya completion yang terukur)

| Aktivitas smoke (§5.1 checklist)                               |           Gas |  Biaya @ 0,1 gwei | Dasar angka                                   |
| -------------------------------------------------------------- | ------------: | ----------------: | --------------------------------------------- |
| `createQuest` × 3 (CheckIn, OnChain, Attested)                 |       600.000 |          0,000060 | Estimasi ~200k/tx — **belum terukur di repo** |
| Completion threshold-1                                         |       244.840 |          0,000024 | **Terukur** Phase 8 (§6 laporan)              |
| Completion threshold-2                                         |       255.766 |          0,000026 | **Terukur** Phase 8 (§6 laporan)              |
| Mint test Agent ID × 2 (via Safe)                              |       200.000 |          0,000020 | Estimasi ~100k/tx                             |
| Grant verifier ke-2 (propose + execute timelock)               |       300.000 |          0,000030 | Estimasi                                      |
| Pause + unpause                                                |       160.000 |          0,000016 | Estimasi                                      |
| Approve validator OnChain (propose + execute)                  |       300.000 |          0,000030 | Estimasi                                      |
| Lainnya (define badge, set high-value, supersedes, deactivate) |       500.000 |          0,000050 | Estimasi                                      |
| **Total smoke**                                                | **2.560.606** | **0,000256 tBNB** |                                               |
| Completion threshold-3 (bila diuji)                            |       266.911 |          0,000027 | Terukur Phase 8                               |

Catatan: biaya Safe (multisig) per eksekusi belum termasuk secara
terpisah — estimasi di atas sudah memberi ruang (angka per-tx
dibulatkan ke atas). Verifikasi kebijakan on-chain (§5.1 langkah 9–11:
revert 1.001/T1, guardrail revoke, supersedes) termasuk dalam baris
"lainnya" dan revert tetap membayar gas — sudah diperhitungkan
secara kasar di sana.

### 2.4 Total + stress test

| Skenario                                                                                                                 | Total tBNB @ 0,1 gwei |
| ------------------------------------------------------------------------------------------------------------------------ | --------------------: |
| Deploy (11 jt gas) + smoke                                                                                               |          **0,001356** |
| Deploy + smoke + **1× redeploy penuh** (kontrak immutable — redeploy adalah satu-satunya perbaikan wiring, checklist §6) |          **0,002456** |
| Skenario sama @ **1 gwei** (lonjakan gas 10×)                                                                            |          **0,024561** |
| Skenario sama @ **5 gwei** (lonjakan 50×, ekstrem)                                                                       |                ~0,123 |

### 2.5 Rekomendasi — ANGKA MINIMAL

| Kebutuhan                                                                                 |         Jumlah |
| ----------------------------------------------------------------------------------------- | -------------: |
| **Minimal mutlak** (deploy + smoke, gas 0,1 gwei)                                         | **0,002 tBNB** |
| **Minimal yang direkomendasikan** (deploy + smoke + 1 redeploy + margin lonjakan gas 10×) |  **0,05 tBNB** |
| **Ideal** (bila faucet mengizinkan — menutup lonjakan 50× + smoke tambahan)               |       0,1 tBNB |

**Keputusan: siapkan ≥ 0,05 tBNB di deployer** — sama dengan
rekomendasi checklist §1 item 1, dan kini dibuktikan cukup:
0,05 tBNB menutup deploy + smoke + 1 redeploy bahkan bila gas
naik 10× lipat (0,0246 tBNB) — dengan sisa ~2× lipat. Dompet uji
(smoke test) perlu dana terpisah yang kecil: ~0,005 tBNB per dompet
uji sudah lebih dari cukup (completion ~0,000025 tBNB per tx).

Faucet: https://testnet.bnbchain.org/faucet-smart
(Jumlah drip faucet tidak diverifikasi dalam workstream ini —
lihat item P-24.)

---

## 3. Checklist preflight

Status: ✅ TERVERIFIKASI | ⏳ MENUNGGU INPUT USER |
❓ BELUM DAPAT DIVERIFIKASI. Kriteria lolos/gagal tercantum per item.

### A. Konektivitas & chain (read-only — dikerjakan workstream ini)

| #    | Item                                                       | Status           | Bukti                                                                              | Kriteria lolos / gagal                                                                                                        | Aksi berikutnya                                                                |
| ---- | ---------------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| P-01 | RPC primer BNB Testnet live, chainId 97                    | ✅ TERVERIFIKASI | §1.1: `eth_chainId` = `0x61`, blok 143.736.674, gas 0,1 gwei, 2026-11-20 07:44 WIB | Lolos: chainId = 97 dan blok maju. Gagal: timeout / chainId ≠ 97 / blok macet                                                 | Pakai sebagai `--fork-url` utama deployment-day; cek ulang blok maju di hari-H |
| P-02 | RPC fallback live, chainId 97                              | ✅ TERVERIFIKASI | §1.2: `eth_chainId` = `0x61`, blok 143.736.704, gas 0,1 gwei                       | Lolos: chainId = 97. Gagal: tidak merespons                                                                                   | Siaga sebagai fallback bila primer gagal                                       |
| P-03 | Gas price testnet terukur                                  | ✅ TERVERIFIKASI | §1.1–1.2: 0,1 gwei di kedua RPC                                                    | Lolos: nilai terbaca dan dipakai dalam perhitungan §2. Gagal: tidak terbaca                                                   | Cek ulang tepat sebelum broadcast (gas bisa berubah)                           |
| P-04 | Kontrak Agent ID resmi TIDAK ada di chain 97 → MockAgentId | ✅ TERVERIFIKASI | §1.3: `eth_getCode(0x60B9…022F)` = `0x`                                            | Lolos: `0x` (jalur mock benar). Gagal: ada kode — berarti asumsi deploy berubah dan `AGENT_ID_ADDRESS` perlu diputuskan ulang | Deploy dengan `AGENT_ID_ADDRESS` unset; mint test ID via Safe pasca-deploy     |
| P-05 | Singleton Safe v1.4.1 + v1.3.0 live di chain 97            | ✅ TERVERIFIKASI | §1.4: kedua alamat punya kode                                                      | Lolos: kode ada di keduanya. Gagal: `0x` di keduanya — Safe tidak bisa dibuat/divalidasi                                      | Tidak ada — prasyarat terpenuhi                                                |
| P-06 | Factory Safe v1.4.1 + v1.3.0 live di chain 97              | ✅ TERVERIFIKASI | §1.4: kedua alamat punya kode                                                      | Lolos: kode ada. Gagal: `0x` — Safe baru tidak bisa dibuat via factory kanonis                                                | Tidak ada — Safe testnet bisa dibuat sekarang                                  |

### B. Kode & artefak (dari bukti Phase 8 — tidak perlu input user)

| #    | Item                                       | Status           | Bukti                                                                                                                                         | Kriteria lolos / gagal                                                                    | Aksi berikutnya                                                     |
| ---- | ------------------------------------------ | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| P-07 | Battery regresi hijau di HEAD e1b316b      | ✅ TERVERIFIKASI | Laporan Phase 8 §5: forge 321/321, fuzz 10k 321/321, Vitest 173+5 skip, E2E 23/23, wallet E2E 26/26, Slither 0H/0M, OSV 7 (0C/0H), gitleaks 0 | Lolos: semua suite hijau. Gagal: satu pun merah → perbaiki sebelum deploy                 | Tidak ada (CI run #44644411279 + #44645056350 hijau 10/10)          |
| P-08 | Guard deploy testnet aktif (PH7-M05)       | ✅ TERVERIFIKASI | `CONFIRM_TESTNET_DEPLOY=true` wajib di chain 97; test skenario revert tanpa env                                                               | Lolos: deploy tanpa env revert. Gagal: deploy jalan tanpa konfirmasi                      | Set env di hari-H (di lingkungan lokal user)                        |
| P-09 | Validasi Safe creator + admin (PH7-M03)    | ✅ TERVERIFIKASI | `DeployScript.t.sol`: EOA / non-Safe / threshold-1 revert; Safe 2-of-3 sukses                                                                 | Lolos: ketujuh test deploy hijau. Gagal: validasi lolos untuk EOA                         | Sediakan alamat Safe asli (§5)                                      |
| P-10 | MockAgentId ownership → multisig (PH7-M04) | ✅ TERVERIFIKASI | Assert `mock.owner() == multisig`; deployer berakhir dengan NOL privilege                                                                     | Lolos: assert hijau. Gagal: owner masih deployer                                          | Mint test ID via Safe pasca-deploy (§6 langkah 9)                   |
| P-11 | Estimasi gas deploy tersedia               | ✅ TERVERIFIKASI | §2.1: 10.294.857 gas terukur (kode lama); estimasi 11–12 jt untuk kode Phase 8                                                                | Lolos: ada angka dasar + margin. Gagal: tidak ada angka → dry-run wajib sebelum broadcast | Dry-run ulang di kode final hari-H (§6 langkah 2) untuk angka pasti |

### C. Input user — BLOCKING (belum satu pun diterima)

| #    | Item                                                          | Status                 | Bukti                                                          | Kriteria lolos / gagal                                                                                                                                                                                           | Aksi berikutnya                                                                                                                                                                                                  |
| ---- | ------------------------------------------------------------- | ---------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P-12 | tBNB ≥ 0,05 di deployer                                       | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 1)                           | Lolos: saldo on-chain deployer ≥ 0,05 tBNB terverifikasi via `eth_getBalance`. Gagal: < 0,002 tBNB (di bawah minimal mutlak §2.5)                                                                                | User mendanai deployer dari faucet; Asta verifikasi saldo on-chain setelah alamat deployer diketahui                                                                                                             |
| P-13 | Deployer key khusus testnet (fresh, single-use)               | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 2)                           | Lolos: key fresh, hanya didanai untuk deploy ini, bukan dompet Agent ID / dana riil. Gagal: key lama / memegang dana riil                                                                                        | **User membuat key sendiri di mesinnya. PRIVATE KEY TIDAK PERNAH DIKIRIM KE CHAT/LAPORAN — hanya dipakai lokal saat broadcast yang disetujui.** Asta hanya perlu ALAMAT deployer (publik) untuk verifikasi saldo |
| P-14 | Alamat Safe admin testnet, threshold ≥ 2                      | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 3)                           | Lolos: Safe asli chain 97, threshold ≥ 2, lolos verifikasi §3 checklist (Safe app + konfirmasi owner out-of-band + creation trace + `ValidateSafe.s.sol` + test-sign). Gagal: EOA / threshold 1 / bukan Safe tim | User membuat Safe (2-of-3 direkomendasikan) di app.safe.global jaringan BSC Testnet, lalu kirim ALAMATNYA (bukan key)                                                                                            |
| P-15 | Alamat Safe quest creator, threshold ≥ 2, distinct dari admin | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 4; wajib Safe sejak PH7-M03) | Lolos: Safe asli, threshold ≥ 2, ≠ admin Safe. Gagal: EOA / sama dengan admin / threshold 1 → deploy script revert                                                                                               | Sama seperti P-14, Safe kedua yang berbeda                                                                                                                                                                       |
| P-16 | Verifier pertama (opsional)                                   | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 5)                           | Lolos: alamat EOA valid. Bila kosong: tetap lolos — grant belakangan via timelock (tambah jeda 2 hari sebelum quest threshold-2)                                                                                 | User putuskan: beri alamat sekarang, atau grant belakangan (implikasi jeda dicatat di §6)                                                                                                                        |
| P-17 | Pauser (opsional)                                             | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 6)                           | Lolos: alamat valid, atau kosong → default admin multisig                                                                                                                                                        | User putuskan bila pauser berbeda dari admin dimaksudkan                                                                                                                                                         |
| P-18 | BscScan API key (testnet)                                     | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 7)                           | Lolos: key valid untuk verifikasi kontrak testnet. Gagal: key tidak valid → `--verify` gagal (fallback: verifikasi manual `forge verify-contract`)                                                               | User sediakan via secret manager/env — **tidak pernah di chat atau repo**                                                                                                                                        |
| P-19 | Persetujuan broadcast eksplisit                               | ⏳ MENUNGGU INPUT USER | Belum diterima (checklist §1 item 8)                           | Lolos: user menyetujui deploy testnet spesifik ini setelah memeriksa laporan + source. Gagal: tidak ada persetujuan → TIDAK ADA broadcast, tanpa kecuali                                                         | Minta setelah seluruh item lain hijau                                                                                                                                                                            |

### D. Belum dapat diverifikasi (butuh input user / chain live / deploy)

| #    | Item                                                         | Status                      | Bukti                                                                                     | Kriteria lolos / gagal                                                                                                                                                                     | Aksi berikutnya                                              |
| ---- | ------------------------------------------------------------ | --------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------ |
| P-20 | Safe yang diserahkan adalah Safe TIM (bukan hanya Safe asli) | ❓ BELUM DAPAT DIVERIFIKASI | Butuh alamat (P-14/P-15)                                                                  | Lolos: 5 langkah §3 checklist (Safe app, konfirmasi owner out-of-band, creation trace, `ValidateSafe.s.sol`, test-sign). Gagal: satu langkah gagal → STOP                                  | Jalankan §3 checklist segera setelah alamat diterima         |
| P-21 | Saldo deployer on-chain                                      | ❓ BELUM DAPAT DIVERIFIKASI | Butuh alamat deployer (P-13)                                                              | Lolos: ≥ 0,05 tBNB. Gagal: < 0,002 tBNB                                                                                                                                                    | `eth_getBalance` setelah alamat diketahui                    |
| P-22 | Dompet uji didanai (prasyarat PH7-L23)                       | ❓ BELUM DAPAT DIVERIFIKASI | Butuh alamat dompet uji                                                                   | Lolos: tiap dompet uji ≥ 0,005 tBNB. Gagal: 0 — smoke tidak bisa jalan                                                                                                                     | Danai 2 dompet uji dari faucet                               |
| P-23 | Verifikasi BscScan pasca-deploy                              | ❓ BELUM DAPAT DIVERIFIKASI | Butuh key (P-18) + kontrak ter-deploy                                                     | Lolos: 6/6 kontrak terverifikasi. Gagal: < 6 → verifikasi manual sebelum lanjut                                                                                                            | `--verify` saat broadcast; fallback manual                   |
| P-24 | Faucet testnet berfungsi + jumlah drip                       | ❓ BELUM DAPAT DIVERIFIKASI | URL diketahui (testnet.bnbchain.org/faucet-smart); drip tidak diuji (butuh interaksi web) | Lolos: deployer menerima ≥ 0,05 tBNB. Gagal: faucet kering / drip < kebutuhan → cari faucet alternatif atau minta dari tim                                                                 | User mencoba faucet; laporkan hasil drip                     |
| P-25 | Alur timelock 2 hari + wallet-app nyata (O4)                 | ❓ BELUM DAPAT DIVERIFIKASI | Hanya bisa diuji di chain live pasca-deploy                                               | Lolos: smoke §5 checklist hijau penuh termasuk approve validator + unpause via timelock, dan wallet-app nyata terhubung. Gagal: satu langkah smoke gagal → diagnosis + redeploy bila perlu | Dijalankan sebagai smoke test pasca-deploy (§6 langkah 9–12) |

---

## 4. Keputusan preflight

**Status: BELUM LOLOS — menunggu 8 input user (§3C).**

Semua 11 item yang bisa diverifikasi tanpa input user sudah
TERVERIFIKASI, termasuk konektivitas RPC live (primer + fallback),
ketiadaan Agent ID resmi di chain 97, prasyarat Safe, battery
regresi, guard deploy, dan perhitungan tBNB. Tidak ada temuan
baru yang memblokir dari sisi kode atau infrastruktur.

Gate menuju deployment-day:

1. Terima P-12 s.d. P-15 (tBNB, alamat deployer, kedua alamat Safe)
   → verifikasi P-20/P-21/P-22 on-chain.
2. Terima P-16/P-17 bila ada (opsional, boleh kosong).
3. Terima P-18 (BscScan key via jalur aman).
4. Terima P-19 (persetujuan broadcast eksplisit) — terakhir,
   setelah semua di atas hijau.
5. Jalankan urutan §5.

---

## 5. Urutan eksekusi deployment-day (chain 97)

Jangan mulai tanpa P-19 (persetujuan broadcast). Urutan ini
mengikuti checklist §4–§5 dengan catatan urutan baru Phase 8.

### Fase 0 — Sehari sebelum / pagi hari-H (tanpa broadcast)

| Langkah | Aksi                                                                                                                                                                                                                   | Kriteria lolos                           |
| ------: | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
|     0.1 | Cek ulang RPC primer + gas price live                                                                                                                                                                                  | chainId 97, gas terbaca                  |
|     0.2 | Verifikasi saldo deployer ≥ 0,05 tBNB on-chain                                                                                                                                                                         | `eth_getBalance`                         |
|     0.3 | Verifikasi kedua Safe (§3 checklist, 5 langkah)                                                                                                                                                                        | Semua langkah lolos                      |
|     0.4 | Danai 2 dompet uji (≥ 0,005 tBNB masing-masing)                                                                                                                                                                        | Saldo terverifikasi                      |
|     0.5 | **Mulai lebih awal (longest pole):** siapkan draf proposal timelock untuk (a) grant verifier ke-2 dan (b) approve `TokenBalanceValidator` — keduanya butuh jeda 2 hari dan memblokir quest threshold-2 + quest OnChain | Draf siap diajukan segera setelah deploy |

### Fase 1 — Dry run (tanpa broadcast)

| Langkah | Aksi                                                                                                                                                                                                                                    | Kriteria lolos                                      |
| ------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
|     1.1 | Set env lokal (deployer key, `ADMIN_MULTISIG`, `QUEST_CREATOR`, opsional `PAUSER`/`VERIFIER`, `CONFIRM_TESTNET_DEPLOY=true`) — dari sumber aman, tidak pernah diketik ke log bersama                                                    | Env lengkap                                         |
|     1.2 | `forge script script/DeployAgentHub.s.sol --fork-url <testnet-rpc>` (tanpa `--broadcast`)                                                                                                                                               | `SIMULATION COMPLETE`                               |
|     1.3 | Baca output penuh: 6 CREATE (MockAgentId, AgentGate, Timelock, Reputation, Achievement, QuestManager), 12 wiring CALL (13 bila `VERIFIER` di-set), tanpa `WiringCheckFailed` / `NotASafe` / `UnknownSingleton` / `UnknownProxyCodehash` | Semua cocok; catat gas aktual (ganti estimasi §2.1) |
|     1.4 | Konfirmasi gas aktual ≤ saldo deployer dengan margin                                                                                                                                                                                    | Gas aktual + buffer < saldo                         |

### Fase 2 — Broadcast

| Langkah | Aksi                                                                                                                           | Kriteria lolos    |
| ------: | ------------------------------------------------------------------------------------------------------------------------------ | ----------------- |
|     2.1 | Perintah sama + `--broadcast --verify` (BscScan key via env)                                                                   | 18/19 tx sukses   |
|     2.2 | Catat semua alamat + tx hash ke `docs/DEPLOYMENT_RECORD.md` (buat baru); salin alamat ke `apps/web/.env.local` (nilai testnet) | Record lengkap    |
|     2.3 | Verifikasi 6/6 kontrak di BscScan testnet (fallback manual `forge verify-contract`)                                            | 6/6 terverifikasi |

### Fase 3 — Verifikasi pasca-deploy (read-only)

| Langkah | Aksi                                                              | Kriteria lolos      |
| ------: | ----------------------------------------------------------------- | ------------------- |
|     3.1 | `AgentGate.agentIdContract()` == MockAgentId ter-deploy           | Sama                |
|     3.2 | `isAgentHolder` benar untuk holder/non-holder (setelah mint test) | Benar               |
|     3.3 | Dependensi QuestManager (gate/reputation/achievement) cocok       | Cocok               |
|     3.4 | Role matrix penuh via `hasRole` (checklist §4.3 langkah 11)       | Semua cocok         |
|     3.5 | Deployer memegang NOL role; `MockAgentId.owner()` == multisig     | NOL privilege       |
|     3.6 | Timelock `getMinDelay()` == 2 hari; role timelock benar           | Benar               |
|     3.7 | Reputation / Achievement / QuestManager tidak ter-pause           | `paused() == false` |

### Fase 4 — Smoke test (checklist §5.1 + §5.2)

| Langkah | Aksi                                                                                                                                   | Kriteria lolos                             | Catatan urutan                            |
| ------: | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ----------------------------------------- |
|     4.1 | Mint test Agent ID ke 2 dompet uji via Safe                                                                                            | `isAgentHolder` true                       | Mint lewat multisig (PH7-M04)             |
|     4.2 | **Ajukan segera:** proposal timelock grant verifier ke-2 + approve validator OnChain                                                   | Proposal aktif                             | Jeda 2 hari mulai dihitung — longest pole |
|     4.3 | Buat quest CheckIn + Attested threshold-1; selesaikan keduanya                                                                         | Poin + event benar                         | Bisa jalan sebelum timelock selesai       |
|     4.4 | Setelah timelock selesai: grant verifier ke-2, buat + selesaikan quest threshold-2; buat quest OnChain, selesaikan                     | Semua hijau                                | Menutup R-010 butir (1) sebagian          |
|     4.5 | Verifikasi kebijakan on-chain (1.001/T1 revert, 1.001/T2 sukses, high-value badge + T1 revert)                                         | Sesuai harapan                             | Checklist §5.1 langkah 9                  |
|     4.6 | Verifikasi guardrail revoke + prosedur supersedes                                                                                      | Sesuai harapan                             | Checklist §5.1 langkah 10–11              |
|     4.7 | Verifikasi pause (hati-hati: unpause butuh 2 hari — jadwalkan di akhir)                                                                | Pause blokir completion; unpause terjadwal | Jangan pause di tengah smoke              |
|     4.8 | Frontend smoke (§5.2): build testnet, connect wallet, banner wrong-network, quest + attestation end-to-end, leaderboard/dashboard live | Semua hijau                                | Menutup O4 (wallet-app nyata)             |

### Fase 5 — Penutup

- [ ] Perbarui `docs/DEPLOYMENT_RECORD.md` dengan hasil smoke.
- [ ] Putuskan R-010: CLOSED bila smoke penuh hijau (butir 1),
      atau tetap IMPLEMENTED bila ada yang gagal.
- [ ] Laporan deployment-day ke user (alamat, tx hash, hasil smoke).
- [ ] Deployer key boleh dibuang setelah deploy (tidak memegang
      privilege apa pun — PH7-M04).

---

## 6. Batasan & caveat workstream ini

- Semua cek RPC adalah snapshot 2026-11-20 07:44 WIB — gas price
  dan nomor blok berubah; cek ulang di hari-H.
- Angka gas deploy 10.294.857 berasal dari kode pra-Phase 6;
  estimasi 11–12 juta untuk kode Phase 8 belum terukur sampai
  dry-run ulang di kode final (Fase 1 langkah 1.3).
- Estimasi gas smoke (kecuali completion T1/T2/T3 yang terukur)
  adalah perkiraan konservatif, bukan pengukuran.
- Faucet tidak diuji (butuh interaksi web); jumlah drip belum
  diketahui — P-24.
- Tidak ada broadcast, deploy, atau private key dalam workstream ini.

---

_Workstream 3 — Testnet Preflight, AGENTHUB Phase 9. Selesai
2026-11-20 07:45 WIB. Status: 11 terverifikasi / 8 menunggu input
user / 6 belum dapat diverifikasi. Gate: BELUM LOLOS (menunggu
input user)._
