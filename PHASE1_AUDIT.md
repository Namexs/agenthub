# AGENTHUB — PHASE 1 AUDIT

**Tanggal audit:** 2026-11-19 ~12:51–12:58 WIB
**Auditor:** Asta (validasi independen terhadap hasil Phase 1)
**Repo:** `~/workspace/agenthub/` — commit `bae7ce6` (Phase 1 `a08dc40` + fix fuzz `bae7ce6`)
**Ruang lingkup:** validasi fondasi repo saja. Tidak ada rewrite proyek, tidak ada
implementasi 4 kontrak utama, tidak ada deploy, tidak ada submit hackathon.

> Semua hasil di bawah ini benar-benar dieksekusi. Tidak ada hasil yang diklaim
> tanpa dijalankan. Satu pengecualian dicatat jujur: `pnpm audit` tidak bisa
> jalan di lingkungan ini (registry menolak — lihat §4).

---

## 1. Test execution results

| Perintah                   | Hasil                                                                                                                                                                                        |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm test` (agregat root) | ✅ PASS — kontrak 5/5; web/shared placeholder jujur (belum ada unit test)                                                                                                                    |
| `forge test -vvv`          | ✅ **5/5 lolos, 0 gagal** (4 unit + 1 fuzz 256 runs)                                                                                                                                         |
| Detail forge test          | `test_NonHolderHasZeroBalance` ✅ · `test_MintGrantsOwnership` ✅ · `test_TransferIsBlocked_Soulbound` ✅ · `test_OnlyOwnerCanMint` ✅ · `testFuzz_MintGrantsBalance(address)` ✅ (256 runs) |

Catatan: fuzz test sempat flaky sebelum audit (gagal pada satu seed karena
`_safeMint` menolak alamat kontrak tanpa `onERC721Received`). Sudah diperbaiki
di commit `bae7ce6` (fuzz dibatasi ke EOA) dan diverifikasi lolos di 3 seed
berbeda + sekali lagi di run audit ini.

**Celah:** web dan shared belum punya unit test sama sekali — skrip `test`
mereka hanya `echo` + `exit 0`. Agregat `pnpm test` jadi hijau tanpa menguji
frontend. Lihat temuan M4.

## 2. Build results

| Perintah                    | Hasil                                                                                                                                                                                                                                                                                                        |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `pnpm install`              | ⚠️ **EXIT 255** — EPERM `chown` pada `node_modules/.modules.yaml.*` setelah baris "resolved 903, reused 830, downloaded 0, added 0, done". Dependency tetap terinstal dan fungsional (semua perintah di bawah jalan). Ini masalah lingkungan VM ini (filesystem melarang chown), bukan cacat repo. Lihat M1. |
| `pnpm build` (agregat)      | ✅ PASS — contracts (forge build) + shared (tsc) + web (next build, 9 route, 11 halaman statis, First Load JS 87–151 kB)                                                                                                                                                                                     |
| `forge build` (solc 0.8.24) | ✅ PASS                                                                                                                                                                                                                                                                                                      |

Catatan: build web di VM ini membutuhkan `NODE_OPTIONS=--max-old-space-size=1024`
(RAM ketat); tanpa itu berisiko OOM. Skrip `build` belum mengatur ini sendiri (L6).

## 3. Lint and typecheck results

| Perintah                                  | Hasil                                                                                                 |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `pnpm lint` (agregat)                     | ✅ PASS — `forge fmt --check` ✅, `eslint` shared ✅, `next lint` ✅ ("No ESLint warnings or errors") |
| `pnpm typecheck` (agregat)                | ✅ PASS — `forge build` + `tsc --noEmit` strict (web + shared)                                        |
| `pnpm format:check` + `forge fmt --check` | ✅ PASS (dijalankan di Phase 1; tidak diulang di audit ini)                                           |
| `git status --short`                      | ✅ Bersih — tidak ada perubahan yang belum di-commit                                                  |

## 4. Dependency audit

- **Semua dependency AGENTHUB di-pin eksak** (tanpa `^`/`~`) di root, web,
  shared, dan config `package.json`. Referensi `workspace:*` hanya untuk
  paket internal — benar.
- **OpenZeppelin Contracts v5.0.2** — via git submodule, tag terverifikasi
  - `foundry.lock` rev `dbb6104c`. **forge-std v1.9.0**, rev `8948d45d`.
- **Toolchain:** pnpm 9.15.4 (di-pin via `packageManager` + `engines`),
  Node ≥20 <25, Foundry 1.9.0, Solidity 0.8.24, Next.js 14.2.18,
  React 18.3.1, wagmi 2.12.29, viem 2.21.45.
- **Peringatan peer dep (non-blocking):** `react-native@0.88.1` (transitif
  via wagmi/MetaMask SDK, tidak dipakai app) meminta React 19; `@metamask/sdk`
  meminta `eciesjs@^0.3.16`, terpasang 0.4.18. Build tetap hijau (L8).
- **`pnpm audit` TIDAK DAPAT DIJALANKAN di lingkungan ini** — registry
  npm menolak endpoint audit (HTTP 403 `policy_denied`). **Pemindaian
  kerentanan dependency belum dilakukan** dan harus dijalankan di mesin
  dengan akses registry, atau via GitHub Dependabot setelah repo di-push (L9).

## 5. Configuration audit

| Item                                    | Status | Catatan                                                                                                                                                                                                                                                                                                      |
| --------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `package.json` scripts (root + 3 paket) | ✅     | Agregat `pnpm -r` lengkap; kontrak punya build/test/lint/typecheck                                                                                                                                                                                                                                           |
| `pnpm-workspace.yaml`                   | ✅     | `apps/*`, `packages/*`                                                                                                                                                                                                                                                                                       |
| `foundry.toml`                          | ⚠️     | solc 0.8.24, optimizer on (200 runs), fuzz 256, invariant terkonfigurasi. Masalah: `solc` + `solc_version` redundan (L2); **`evm_version` tidak di-pin** (M2)                                                                                                                                                |
| `remappings.txt`                        | ✅     | Konsisten dengan `foundry.toml`                                                                                                                                                                                                                                                                              |
| `.gitmodules`                           | ✅     | forge-std + openzeppelin-contracts, tag ter-pin                                                                                                                                                                                                                                                              |
| `.env.example`                          | ✅     | Hanya placeholder; alamat resmi Agent ID benar di komentar; `DEPLOYER_PRIVATE_KEY`/`BSCSCAN_API_KEY` tanpa prefix `NEXT_PUBLIC` (tidak masuk bundle browser)                                                                                                                                                 |
| `.gitignore`                            | ⚠️     | Menutupi node_modules, `.next`, `out`, `broadcast`, `.env`, `.env.local`, `.env.*.local`, `*.pem`, `*.key`. Celah: `.env.production`/`.env.staging` tidak tertutup (L1)                                                                                                                                      |
| GitHub Actions `ci.yml`                 | ⚠️     | 3 job (web/shared/contracts), pnpm 9.15.4 ter-pin, Node 20, `--frozen-lockfile`, submodule rekursif. Celah: foundry-toolchain `stable` tidak di-pin (M3); tanpa format check, tanpa `pnpm audit`, tanpa secret scanning, tanpa `permissions:` (L5); **CI belum pernah dieksekusi** (belum ada remote GitHub) |
| TypeScript config                       | ⚠️     | Strict + `noUncheckedIndexedAccess` + `exactOptionalPropertyTypes` di semua paket. Masalah: `apps/web/tsconfig.json` menduplikasi opsi base secara inline, bukan extend `@agenthub/config` (risiko drift — L3)                                                                                               |
| Solidity compiler                       | ⚠️     | 0.8.24 ter-pin; optimizer on. `evm_version` tidak di-pin — default solc adalah Cancun (M2)                                                                                                                                                                                                                   |
| OpenZeppelin install                    | ✅     | v5.0.2 via submodule terverifikasi (tag + lock rev)                                                                                                                                                                                                                                                          |

### Konfigurasi Agent ID (diperiksa khusus)

- Alamat resmi `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` **konsisten di
  semua file** (constants, env example, interface, mock, script, docs).
  Ditulis lowercase (bukan EIP-55 checksummed) — fungsional identik, kosmetik (L7).
- `DeployMock.s.sol` menolak jalan di chainId 56 (mainnet) — tapi guard-nya
  denylist, bukan allowlist: script akan jalan di chain apa pun selain 56 (L4).
- `env.ts` memvalidasi semua alamat dengan zod + throw saat config salah.
  Celah: `NEXT_PUBLIC_CHAIN_ID` tidak di-allowlist (56/97/31337) dan alamat
  nol (`0x0000…`) lolos validasi; tidak ada cek konsistensi chain ↔ alamat
  Agent ID (alamat mainnet + chain testnet akan gagal diam-diam di runtime) (M5).

## 6. Security findings

### Critical — tidak ada.

### High — tidak ada.

### Medium

| ID  | Temuan                                                                                                                                                                                                     | Perbaikan                                                                                                                                                        |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M1  | `pnpm install` exit 255 di VM ini (EPERM chown `.modules.yaml`). Dependency terinstal dan semua perintah lanjutan lolos, tapi rantai perintah yang mengandalkan exit code install akan gagal di sini.      | Masalah lingkungan, bukan kode repo. Selidiki store/chown atau dokumentasikan; CI (ubuntu-latest) tidak terdampak (belum terverifikasi karena belum ada remote). |
| M2  | `evm_version` tidak di-pin di `foundry.toml`. Default solc 0.8.24 = Cancun. OpenZeppelin 5.x `ReentrancyGuard` memakai transient storage (EIP-1153) — dukungannya di BSC harus dibuktikan sebelum mainnet. | Pin `evm_version` eksplisit (mis. `cancun` setelah verifikasi) + smoke test transient storage di BSC testnet pada Phase 2.                                       |
| M3  | CI memakai `foundry-rs/foundry-toolchain@v1` versi `stable` (mengambang).                                                                                                                                  | Pin ke `1.9.0` (versi yang terverifikasi lokal).                                                                                                                 |
| M4  | Nol unit test untuk web/shared; `pnpm test` agregat hijau lewat placeholder `echo`.                                                                                                                        | Tambah vitest + test pertama di Phase 2 (sudah direncanakan).                                                                                                    |
| M5  | Tidak ada cek konsistensi chain ↔ alamat Agent ID; chainId tidak di-allowlist; alamat nol lolos validasi env.                                                                                             | Allowlist chainId (56/97/31337), tolak alamat nol, beri peringatan saat alamat mainnet dipakai dengan chain testnet (dan sebaliknya).                            |

### Low

| ID  | Temuan                                                                                                   | Perbaikan                                                   |
| --- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| L1  | `.gitignore` tidak menutupi `.env.production`/`.env.staging`.                                            | Tambah pola `.env.*` dengan pengecualian `.env.example`.    |
| L2  | `foundry.toml` mengatur `solc` dan `solc_version` sekaligus (redundan).                                  | Pertahankan satu.                                           |
| L3  | `apps/web/tsconfig.json` menduplikasi opsi base inline.                                                  | Extend `@agenthub/config/typescript/base`.                  |
| L4  | Guard `DeployMock` denylist (hanya blokir 56).                                                           | Ubah ke allowlist 97/31337.                                 |
| L5  | CI tanpa format check, `pnpm audit`, secret scanning, dan blok `permissions:`.                           | Tambah di Phase 2.                                          |
| L6  | Skrip `build` web tidak mengatur batas memori; build OOM di mesin RAM kecil tanpa `NODE_OPTIONS` manual. | Atur `--max-old-space-size` di skrip atau dokumentasikan.   |
| L7  | Alamat Agent ID ditulis lowercase, bukan EIP-55 checksummed.                                             | Kosmetik; gunakan bentuk checksummed agar mudah dibaca.     |
| L8  | Peringatan peer dep (React 19, eciesjs). Non-blocking.                                                   | Pantau saja.                                                |
| L9  | `pnpm audit` tidak bisa jalan di lingkungan ini (registry 403).                                          | Jalankan di mesin lain / Dependabot setelah push ke GitHub. |

### Pemindaian secret

`git grep` pada semua file terlacak untuk pola private key, mnemonic,
`BEGIN PRIVATE KEY`, token API, dan string 64-hex: **bersih**. Satu-satunya
kecocokan adalah kalimat pemasaran di `apps/web/app/page.tsx` ("No seed
phrase, no QR login…") — pernyataan, bukan secret. Tidak ada file `.env`
nyata yang terlacak (hanya `.env.example` placeholder).

## 7. Failed checks and their fixes

| Check gagal                           | Status                  | Perbaikan                                                                                                                                                                                  |
| ------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `pnpm install` exit 255 (EPERM chown) | ⚠️ Terbuka (lingkungan) | Bukan cacat repo. Workaround: abaikan exit code bila baris "done" tercetak dan perintah lanjutan lolos; investigasi store/chown bila perlu. CI ubuntu-latest diperkirakan tidak terdampak. |
| Fuzz test flaky (pra-audit)           | ✅ Sudah diperbaiki     | Commit `bae7ce6`: fuzz dibatasi ke EOA. Diverifikasi 5/5 di 3 seed + run audit.                                                                                                            |

Tidak ada check lain yang gagal. Semua build/lint/typecheck/test lolos.

## 8. Remaining blockers

1. **Belum ada remote GitHub** — CI belum pernah dieksekusi; Dependabot dan
   `pnpm audit` via GitHub belum tersedia. User perlu buat repo + push.
2. **`pnpm audit` terblokir di lingkungan ini** (registry 403) — pemindaian
   kerentanan belum dilakukan.
3. **Deploy testnet (Phase 2) butuh dari user:** tBNB dari faucet, deployer
   key khusus (bukan wallet utama), BscScan API key, WalletConnect project id
   (opsional).
4. **Keputusan `evm_version` + verifikasi transient storage di BSC testnet**
   sebelum deploy mainnet apa pun (M2).
5. **pnpm terinstal di `/usr/bin` (ephemeral)** — bila VM diganti, instal
   ulang `npm install -g pnpm@9.15.4`. Foundry di `~/.foundry/bin` (persisten).

## 9. Final Phase 1 readiness decision

### ✅ PHASE 1 READY — dengan catatan (conditional pass)

Fondasi repo solid: semua build, lint, typecheck, dan test lolos; tidak ada
temuan Critical/High; tidak ada secret yang terekspos; semua dependency
di-pin; alamat Agent ID konsisten dan benar; arsitektur mainnet-first sudah
terdokumentasi.

**Syarat sebelum/saat Phase 2:**

1. Perbaiki M3, M5, L1–L4, L6 sebagai pekerjaan awal Phase 2 (kecil, cepat).
2. Tambah vitest + unit test web/shared (M4) bersamaan dengan fitur Phase 2.
3. Verifikasi M2 (transient storage di BSC testnet) sebelum deploy mainnet apa pun.
4. Buat remote GitHub + push agar CI berjalan dan `pnpm audit` tersedia.
5. M1 dicatat sebagai keterbatasan lingkungan VM ini, bukan blocker proyek.

**Phase 2 (implementasi AgentGate → QuestManager → Reputation → Achievement)
BOLEH dimulai setelah user menyetujui audit ini.** Tidak ada deploy mainnet
tanpa persetujuan eksplisit user.
