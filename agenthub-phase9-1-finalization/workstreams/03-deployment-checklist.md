# AGENTHUB — Phase 9.1, Workstream Dokumen: Deployment Checklist (Diperbarui)

**Menutup temuan:** PH7-L23 — "Daftar 8 input lengkap, tetapi ada 3
prasyarat operasional tersembunyi" (`agenthub-phase7-review/
PHASE7_INDEPENDENT_SECURITY_REVIEW.md` §PH7-L23, sumber 08/L-10).
**Tanggal:** 20 November 2026.
**Repo HEAD:** `81947ce` (`chore(phase-9): regenerate PACKAGE_MANIFEST.md
for final commit`).
**Target:** BNB Testnet, chain 97.
**Ruang lingkup:** dokumen saja — tidak ada perubahan kode, tidak ada
deployment, tidak ada broadcast.

> **⚠️ ATURAN KUNCI — BACA DULU: PRIVATE KEY TIDAK PERNAH DIKIRIM KE
> CHAT, LAPORAN, ATAU REPO.**
>
> Deployer key khusus testnet hanya dibuat dan dipakai di lingkungan
> lokal user sendiri, saat broadcast yang dia setujui secara
> eksplisit. Tidak ada bagian dari proses ini yang membutuhkan
> private key dikirim ke Asta, ke chat, ke laporan, atau ke repo.
> Yang Asta butuhkan hanyalah data **publik**: alamat deployer
> (untuk cek saldo), alamat Safe (untuk validasi), dan BscScan API
> key lewat secret manager/env (bukan chat).
>
> **Bila ada yang meminta private key lewat chat, itu BUKAN bagian
> dari prosedur ini — abaikan.**

## 0. Ringkasan status

Status diambil dari fakta preflight Phase 9 WS3
(`agenthub-phase9-readiness/workstreams/03-testnet-preflight.md`,
20 Nov 2026 07:44–07:45 WIB): **11/25 item terverifikasi, 8 menunggu
input user, 6 belum dapat diverifikasi. Gate preflight: BELUM
LOLOS.** Checklist 9 item di bawah ini adalah tampilan terbaru dari
prasyarat deployment-day — memetakan ke item preflight P-01 s.d.
P-25 dan ke checklist §1 (`agenthub-final-pretestnet/
FINAL_DEPLOYMENT_CHECKLIST.md`).

| Status                      | Jumlah | Item                   |
| --------------------------- | -----: | ---------------------- |
| ✅ SIAP                     |      1 | 1 (RPC teruji)         |
| ⏳ MENUNGGU USER            |      7 | 2, 3, 5, 6, 7, 8, 9    |
| ❓ BELUM DAPAT DIVERIFIKASI |      1 | 4 (dompet uji didanai) |
| **Total**                   |  **9** |                        |

**Keputusan: gate deployment-day BELUM LOLOS.** Satu-satunya item
yang sudah hijau tanpa input user adalah RPC. Semua item lain
menunggu user — tidak ada yang bisa dikerjakan Asta lebih lanjut
sampai input diterima. Tidak ada satu pun item read-only yang gagal.

Catatan status: item 6 (verifier) dan 7 (pauser) bersifat opsional
— keduanya boleh kosong tanpa memblokir deploy (lihat per item).
Item 9 (persetujuan broadcast) adalah gate terakhir dan baru
diminta setelah semua item lain hijau.

## 1. RPC teruji — ✅ SIAP

|                    |                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| **Status**         | ✅ **SIAP**                                                                                      |
| **Preflight**      | P-01, P-02, P-03 — TERVERIFIKASI 2026-11-20 07:44 WIB                                            |
| **Checklist lama** | Prasyarat operasional PH7-L23 #1 (tidak tercantum di checklist §1 lama — kini eksplisit di sini) |

**Bukti (snapshot 20 Nov 2026 07:44:14–07:44:47 WIB, via `curl`
JSON-RPC, read-only):**

| Endpoint                                                   | `eth_chainId`      | Blok        | `eth_gasPrice` |
| ---------------------------------------------------------- | ------------------ | ----------- | -------------- |
| Primer `https://data-seed-prebsc-1-s1.binance.org:8545/`   | `0x61` = **97** ✅ | 143.736.674 | 0,1 gwei       |
| Fallback `https://data-seed-prebsc-2-s1.binance.org:8545/` | `0x61` = **97** ✅ | 143.736.704 | 0,1 gwei       |

Kedua endpoint Binance live, chainId benar, gas price 0,1 gwei di
keduanya. Fallback siap dipakai bila primer gagal di deployment-day.
Alternatif ketiga tercatat di `.env.example`:
`https://bsc-testnet-rpc.publicnode.com` (merespons ~2,5 detik saat
endpoint binance.org timeout dari VM build, 19 Nov 2026).

**Cara verifikasi (ulang di deployment-day):**

```bash
curl -s -X POST https://data-seed-prebsc-1-s1.binance.org:8545/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
# Harus mengembalikan "result":"0x61" (97). Ulangi untuk eth_blockNumber
# (blok harus maju) dan eth_gasPrice (untuk perhitungan biaya).
```

**Yang harus dilakukan user:** tidak ada — kecuali cek ulang di
hari-H (gas price dan nomor blok berubah; snapshot di atas
kedaluwarsa dalam hitungan menit). Bila primer gagal di hari-H,
pakai fallback.

## 2. Safe admin tersedia — ⏳ MENUNGGU USER

|                    |                                                                                                                               |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| **Status**         | ⏳ **MENUNGGU USER**                                                                                                          |
| **Preflight**      | P-14 — MENUNGGU INPUT USER; P-05/P-06 (infrastruktur Safe) TERVERIFIKASI; P-20 (verifikasi Safe tim) BELUM DAPAT DIVERIFIKASI |
| **Checklist lama** | §1 item 3                                                                                                                     |

**Keadaan sekarang:** alamat Safe admin belum diterima — belum satu
pun input user diterima (preflight §3C). Yang sudah terverifikasi
adalah infrastrukturnya: singleton Safe v1.4.1
(`0x41675C099F32341bf84BFc5382aF534df5C7461a`) dan v1.3.0
(`0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552`) serta factory
v1.4.1/v1.3.0 semuanya live di chain 97 (P-05/P-06) — Safe baru
bisa dibuat sekarang.

**Cara verifikasi (setelah alamat diterima):**

1. Deploy script memvalidasi on-chain SEBELUM deploy apa pun
   (`SafeValidation`): singleton kanonis + proxy codehash kanonis
   - threshold ≥ 2. EOA, non-Safe, atau threshold-1 → deploy
     revert (`DeployAgentHub.s.sol`, PH7-M03; 7 test deploy hijau).
2. Verifikasi 5 langkah checklist §3 (P-20) — script membuktikan
   Safe itu ASLI, bukan membuktikan itu Safe TIM:
   - Buka alamat di Safe web app (app.safe.global, jaringan BSC
     Testnet): termuat sebagai Safe dengan owner + threshold yang
     diharapkan. Bila app tidak mengenalinya → STOP.
   - Konfirmasi setiap owner out-of-band (kanal kedua, bukan hanya
     pesan chat yang memberi alamat). Threshold ≥ 2.
   - BscScan creation trace: dibuat oleh factory kanonis dengan
     singleton kanonis.
   - `ADMIN_MULTISIG=<0x..> forge script script/ValidateSafe.s.sol
--fork-url <testnet-rpc>` mencetak baris OK dengan threshold
     dan jumlah owner yang diharapkan. Simpan outputnya.
   - Test-sign dengan Safe: para owner mengeksekusi no-op (atau
     proposal timelock percobaan) untuk membuktikan kuorum masih
     bisa dicapai.

**Yang harus dilakukan user:**

1. Buat Safe baru di app.safe.global, jaringan **BSC Testnet**,
   threshold ≥ 2 (**2-of-3 direkomendasikan**). Ini adalah
   prasyarat operasional PH7-L23 #2: Safe harus SUDAH DIBUAT
   sebelum deploy (proksi + setup owner/threshold + pendanaan
   tBNB untuk eksekusi Safe).
2. Kirim **ALAMATNYA saja** (publik) — bukan key, bukan seed phrase.
3. Siapkan para owner untuk konfirmasi out-of-band dan test-sign
   (langkah 2 dan 5 di atas).

## 3. Safe quest creator tersedia dan berbeda dari admin — ⏳ MENUNGGU USER

|                    |                            |
| ------------------ | -------------------------- |
| **Status**         | ⏳ **MENUNGGU USER**       |
| **Preflight**      | P-15 — MENUNGGU INPUT USER |
| **Checklist lama** | §1 item 4                  |

**Keadaan sekarang:** alamat Safe creator belum diterima. Sejak
Phase 8 (PH7-M03) creator WAJIB Safe asli threshold ≥ 2 —
single-key creator ditolak: satu key yang dikompromikan tidak boleh
bisa memublikasikan quest bernilai tinggi sendirian. Sejak Phase 9
WS2 (PH9-D01) kedua Safe juga **wajib BERBEDA** — deploy script
menegakkannya on-chain dengan error `AdminAndCreatorMustDiffer`
sebelum validasi atau CREATE apa pun. Safe yang sama untuk kedua
peran akan meruntuhkan pemisahan tugas yang diciptakan M03.

**Cara verifikasi (setelah alamat diterima):** sama seperti item 2
— validasi Safe asli oleh deploy script (check yang sama persis),
ditambah:

- `QUEST_CREATOR != ADMIN_MULTISIG` (dicek script; bila sama,
  deploy revert sebelum apa pun di-deploy).
- Ulangi langkah 1–2 verifikasi §3 checklist (Safe web app +
  konfirmasi owner out-of-band) untuk Safe creator.

**Yang harus dilakukan user:**

1. Buat Safe **kedua yang berbeda** di app.safe.global, jaringan
   BSC Testnet, threshold ≥ 2 (2-of-3 direkomendasikan).
2. Kirim **ALAMATNYA saja**.
3. Jangan menyalin alamat Safe admin ke kolom creator — deploy
   akan gagal (fail-closed, by design).

## 4. Dompet uji didanai — ❓ BELUM DAPAT DIVERIFIKASI

|                    |                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| **Status**         | ❓ **BELUM DAPAT DIVERIFIKASI**                                                                  |
| **Preflight**      | P-22 — BELUM DAPAT DIVERIFIKASI (butuh alamat dompet uji)                                        |
| **Checklist lama** | Prasyarat operasional PH7-L23 #3 (tidak tercantum di checklist §1 lama — kini eksplisit di sini) |

**Keadaan sekarang:** belum ada alamat dompet uji, jadi saldo tidak
bisa dicek. Smoke test checklist §5.1 membutuhkan **2 dompet uji
didanai** — masing-masing perlu test Agent ID (di-mint via Safe
pasca-deploy, PH7-M04) dan tBNB untuk gas transaksi smoke
(completion ~0,000025 tBNB per tx).

**Cara verifikasi (setelah alamat diterima):**
`eth_getBalance` per dompet — lolos bila tiap dompet **≥ 0,005
tBNB** (preflight §2.5: angka itu sudah lebih dari cukup untuk
seluruh smoke). Gagal bila 0 — smoke tidak bisa jalan.

**Yang harus dilakukan user:**

1. Siapkan 2 alamat dompet uji (EOA biasa; boleh dompet yang sama
   dengan yang dipakai untuk koneksi frontend smoke test).
2. Danai masing-masing **≥ 0,005 tBNB** dari faucet
   (https://testnet.bnbchain.org/faucet-smart).
3. Kirim kedua **ALAMATNYA** (publik) agar Asta bisa verifikasi
   saldo on-chain.

Catatan: jumlah drip faucet belum diverifikasi (preflight P-24 —
faucet butuh interaksi web, tidak diuji di WS3). Bila faucet kering
atau drip kurang, cari faucet alternatif atau minta dari tim.

## 5. Saldo deployer cukup — ⏳ MENUNGGU USER

|                    |                                                                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| **Status**         | ⏳ **MENUNGGU USER**                                                                                                                  |
| **Preflight**      | P-12 (tBNB ≥ 0,05) — MENUNGGU INPUT USER; P-13 (deployer key) — MENUNGGU INPUT USER; P-21 (saldo on-chain) — BELUM DAPAT DIVERIFIKASI |
| **Checklist lama** | §1 item 1 (tBNB) + item 2 (deployer key)                                                                                              |

**Kebutuhan tBNB (angka terukur, bukan karangan):**

| Skenario                                                                 |         Gas | Biaya @ 0,1 gwei |
| ------------------------------------------------------------------------ | ----------: | ---------------: |
| Deploy penuh (terukur, fork dry-run WS4, 2 run identik, VERIFIER di-set) |   8.307.890 |    0,000831 tBNB |
| Deploy + smoke test                                                      | ~10.868.496 |   ~0,001087 tBNB |
| Deploy + smoke + 1× redeploy penuh                                       |           — |   ~0,001918 tBNB |
| Skenario sama @ 1 gwei (lonjakan gas 10×)                                |           — |      ~0,019 tBNB |

**Minimal mutlak:** 0,002 tBNB. **Minimal yang direkomendasikan:
≥ 0,05 tBNB** — menutup deploy + smoke + 1 redeploy bahkan bila
gas naik 10× lipat, dengan sisa ~2× lipat. Angka 10.294.857 gas di
checklist lama adalah pengukuran kode pra-Phase 6 dan sudah
digantikan pengukuran 8.307.890 gas untuk kode final.

**Keadaan sekarang:** alamat deployer belum diketahui, jadi saldo
belum bisa dicek (P-21). Deployer key khusus testnet juga belum
dibuat/dikonfirmasi (P-13).

**Cara verifikasi (setelah alamat deployer diketahui):**
`eth_getBalance` on-chain — lolos bila **≥ 0,05 tBNB**; gagal bila
< 0,002 tBNB (di bawah minimal mutlak). Cek ulang tepat sebelum
broadcast (gas price bisa berubah).

**Yang harus dilakukan user:**

1. Buat **deployer key baru, fresh, single-use** di mesin sendiri —
   khusus untuk deploy testnet ini, hanya didanai untuk deploy
   ini, **bukan** dompet Agent ID dan bukan dompet yang memegang
   dana riil.
2. Danai alamat deployer dengan **≥ 0,05 tBNB** dari faucet
   (https://testnet.bnbchain.org/faucet-smart).
3. Kirim **ALAMAT deployer saja** (publik) agar Asta bisa
   verifikasi saldo on-chain.
4. **JANGAN PERNAH** mengirim private key-nya ke chat, laporan,
   atau repo — key hanya dipakai lokal di mesin user saat broadcast
   yang disetujui (item 9). Setelah deploy selesai, deployer key
   boleh dibuang: deployer berakhir dengan NOL privilege di semua
   kontrak (PH7-M04).

## 6. Verifier tersedia — ⏳ MENUNGGU USER (opsional)

|                    |                                               |
| ------------------ | --------------------------------------------- |
| **Status**         | ⏳ **MENUNGGU USER** — opsional, boleh kosong |
| **Preflight**      | P-16 — MENUNGGU INPUT USER                    |
| **Checklist lama** | §1 item 5                                     |

**Keadaan sekarang:** belum ada keputusan — alamat verifier pertama
belum diterima. Item ini **tidak memblokir deploy**: bila
`VERIFIER` unset, deploy tetap jalan (12 wiring CALL, bukan 13)
dan `VERIFIER_ROLE` bisa diberikan belakangan lewat timelock.

**Implikasi bila kosong:** grant verifier belakangan butuh proposal
timelock dengan jeda **2 hari** — quest threshold-2 (yang butuh ≥2
verifier berbeda) tidak bisa di-smoke-test sampai grant itu
selesai. Bila verifier pertama diberikan saat deploy, hanya grant
verifier ke-2 yang menunggu timelock.

**Cara verifikasi:** alamat EOA valid (bila diberikan). Tidak ada
validasi Safe untuk verifier — verifier adalah EOA penanda tangan
attestasi, bukan multisig.

**Yang harus dilakukan user:** putuskan salah satu — (a) beri
alamat EOA verifier pertama sekarang (direkomendasikan, agar
smoke threshold-2 tidak tertunda lebih lama), atau (b) kosongkan
dan grant belakangan via timelock (terima jeda 2 hari).

## 7. Pauser tersedia jika diperlukan — ⏳ MENUNGGU USER (opsional)

|                    |                                                                  |
| ------------------ | ---------------------------------------------------------------- |
| **Status**         | ⏳ **MENUNGGU USER** — opsional; default sudah menutup kebutuhan |
| **Preflight**      | P-17 — MENUNGGU INPUT USER                                       |
| **Checklist lama** | §1 item 6                                                        |

**Keadaan sekarang:** belum ada keputusan — alamat pauser belum
diterima. Item ini **tidak memblokir deploy**: bila `PAUSER`
unset, `PAUSER_ROLE` otomatis diberikan ke **admin multisig**
(production default, Final Remediation Phase 2). Pause adalah
aksi darurat cepat tanpa timelock, jadi default ke multisig admin
adalah konfigurasi yang dimaksudkan.

**Cara verifikasi:** bila pauser eksplisit diberikan — alamat
valid. Bila kosong — tidak ada yang perlu diverifikasi (default
diterapkan script dan dicek `_verifyWiring`).

**Yang harus dilakukan user:** hanya bila pauser yang **berbeda
dari admin** dimaksudkan (konfigurasi non-default, dicatat di
`docs/ROLE_MATRIX.md`) — beri alamatnya. Bila default (admin
multisig sebagai pauser) dapat diterima, tidak ada aksi — item ini
dianggap selesai dengan default saat deploy.

## 8. BscScan API key tersedia — ⏳ MENUNGGU USER

|                    |                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------- |
| **Status**         | ⏳ **MENUNGGU USER**                                                                          |
| **Preflight**      | P-18 — MENUNGGU INPUT USER; P-23 (verifikasi BscScan pasca-deploy) — BELUM DAPAT DIVERIFIKASI |
| **Checklist lama** | §1 item 7                                                                                     |

**Keadaan sekarang:** key belum diterima. Key dibutuhkan untuk
verifikasi source keenam kontrak di BscScan testnet — baik lewat
`--verify` saat broadcast maupun fallback manual
`forge verify-contract` (lihat dokumen pendamping
`02-constructor-args-and-verification.md`, PH7-L22). Verifikasi
adalah bagian dari definisi "deployment testnet selesai"
(checklist §4.2 langkah 7: target 6/6 terverifikasi) dan wajib
untuk submisi hackathon — kontrak yang tidak terverifikasi tidak
eligible.

**Cara verifikasi (setelah key tersedia):** key valid untuk
verifikasi kontrak testnet — dibuktikan dengan verifikasi pertama
yang berhasil. Bila key tidak valid, `--verify` gagal (fallback:
verifikasi manual, yang juga butuh key). Mekanisme key sudah
terverifikasi: `foundry.toml` memetakan `BSCSCAN_API_KEY` ke
konfigurasi `bsc-testnet` (foundry sendiri TIDAK membaca
`BSCSCAN_API_KEY` — tanpa pemetaan itu gagal dengan
"ETHERSCAN_API_KEY must be set"). Satu key yang sama berlaku untuk
BscScan testnet dan mainnet.

**Yang harus dilakukan user:**

1. Sediakan BscScan API key lewat **secret manager / env lokal** —
   **tidak pernah di chat atau di repo**.
2. Key dimasukkan sebagai `BSCSCAN_API_KEY` di lingkungan lokal
   saat broadcast (`--verify`) atau saat verifikasi manual.
   Jangan mengetiknya di command line terminal bersama.

## 9. Persetujuan broadcast eksplisit — ⏳ MENUNGGU USER

|                    |                                      |
| ------------------ | ------------------------------------ |
| **Status**         | ⏳ **MENUNGGU USER** — gate terakhir |
| **Preflight**      | P-19 — MENUNGGU INPUT USER           |
| **Checklist lama** | §1 item 8                            |

**Keadaan sekarang:** belum ada persetujuan. Tanpa persetujuan
ini, **tidak ada broadcast — tanpa kecuali**. Guard teknis
menegakkannya: deploy script di chain 97 revert tanpa
`CONFIRM_TESTNET_DEPLOY=true` (PH7-M05), dan guard itu tidak bisa
membedakan simulasi dry-run dari broadcast nyata — dry-run pun
butuh env var tersebut.

**Cara verifikasi:** persetujuan eksplisit dari user untuk deploy
testnet **spesifik ini**, setelah memeriksa laporan + source.
Bukan persetujuan umum, bukan persetujuan untuk mainnet (mainnet
tetap NO-GO dan butuh persetujuan terpisah +
`CONFIRM_MAINNET_DEPLOY=true`).

**Yang harus dilakukan user:** setelah item 1–8 hijau (atau
diterima eksplisit untuk item opsional 6–7), periksa laporan
Phase 9 + source, lalu setujui broadcast testnet ini secara
eksplisit. Urutan yang benar: persetujuan adalah langkah
**terakhir**, bukan pertama.

## 10. Pemetaan penutup PH7-L23

Rekomendasi L23: tambahkan §1.x "Prasyarat operasional (bukan
rahasia)" ke checklist — 3 prasyarat yang tidak tercantum di
daftar 8 input lama. Ketiganya kini eksplisit di checklist ini:

| Prasyarat operasional L23                                                                            | Di checklist ini                           | Status                                                                                  |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------ | --------------------------------------------------------------------------------------- |
| (1) URL RPC testnet yang berfungsi (default dokumentasi pernah 403 dari VM build)                    | Item 1 — RPC teruji                        | ✅ SIAP (ditutup WS3: kedua endpoint Binance terverifikasi live, 20 Nov 2026 07:44 WIB) |
| (2) Safe testnet harus SUDAH DIBUAT sebelum deploy (proksi + setup owner/threshold + pendanaan tBNB) | Item 2 — Safe admin; Item 3 — Safe creator | ⏳ MENUNGGU USER (infrastruktur Safe terverifikasi; Safe tim belum dibuat)              |
| (3) Dompet uji + tBNB untuk smoke test (checklist §5.1 butuh 2 dompet uji didanai)                   | Item 4 — Dompet uji didanai                | ❓ BELUM DAPAT DIVERIFIKASI (alamat belum ada)                                          |

Pemetaan `DeployAgentHub.run()` ke 8 input checklist §1 tetap
lengkap — L23 mengonfirmasi **tidak ada input ke-9 berupa
rahasia**. Checklist ini tidak menambah input rahasia apa pun:
satu-satunya secret dalam proses adalah deployer key (item 5) dan
BscScan API key (item 8), dan keduanya tidak pernah melewati chat,
laporan, atau repo.

**Status: PH7-L23 DITUTUP** — checklist ini adalah artefak
penutupnya. Sisa pekerjaan adalah operasional: user memenuhi item
2–9 (item 1 sudah hijau), lalu gate deployment-day dapat diloloskan.

## 11. Urutan menuju deployment-day

Gate diloloskan dalam urutan ini (preflight §4):

1. Terima item 5 (tBNB + alamat deployer) dan item 2–3 (kedua
   alamat Safe) → verifikasi on-chain item 4, saldo deployer,
   dan Safe tim (P-20/P-21/P-22).
2. Terima keputusan item 6–7 (boleh kosong — catat implikasinya).
3. Terima item 8 (BscScan key via jalur aman).
4. Terima item 9 (persetujuan broadcast eksplisit) — terakhir,
   setelah semua di atas hijau.
5. Jalankan urutan deployment-day (preflight §5): Fase 0
   (persiapan, tanpa broadcast) → Fase 1 (dry-run, tanpa
   broadcast) → Fase 2 (broadcast + `--verify`) → Fase 3
   (verifikasi pasca-deploy, read-only) → Fase 4 (smoke test)
   → Fase 5 (penutup + keputusan R-010).

> **Pengingat terakhir: PRIVATE KEY TIDAK PERNAH DIKIRIM KE CHAT,
> LAPORAN, ATAU REPO.** Bila ada yang memintanya, itu bukan bagian
> dari prosedur ini.

---

_Sumber utama: `agenthub-phase9-readiness/workstreams/
03-testnet-preflight.md` (status P-01 s.d. P-25, snapshot 20 Nov
2026 07:44 WIB), `agenthub-phase9-readiness/workstreams/
04-live-testnet-test-plan.md` (gas deploy terukur 8.307.890,
urutan deploy), `agenthub-final-pretestnet/
FINAL_DEPLOYMENT_CHECKLIST.md` §1–§5, `packages/contracts/script/
DeployAgentHub.s.sol` (validasi Safe, guard M05, `AdminAndCreatorMustDiffer`),
`docs/DEPLOYMENT.md` §5 (mekanisme BscScan key), `.env.example`
(RPC primer + fallback)._
