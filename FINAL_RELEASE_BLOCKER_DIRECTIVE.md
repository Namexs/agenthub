# AGENTHUB — FINAL RELEASE BLOCKER REMEDIATION & TESTNET READINESS DIRECTIVE

User order 2026-11-19 ~18:14 WIB. Baseline: HEAD `5417787`
(FINAL REMEDIATION selesai 18:06 WIB). Perintah lengkap user tersimpan di
chat turn ini (Phase A–I). Ringkasan:

- PHASE A — Source integrity: inspeksi repo, git status + HEAD, manifest,
  hash + submodule, bandingkan source vs FINAL_REMEDIATION_REPORT.md,
  identifikasi file hilang/berubah/tak terdokumentasi →
  SOURCE_INTEGRITY_REPORT.md. GATE A: jangan lanjut bila integritas
  tidak bisa ditegakkan.
- PHASE B — Dependency security: audit lengkap; Next.js 14.2.18 (termasuk
  CVE-2025-29927 + RCE advisories), vitest/tinypool, PostCSS, zod, glob,
  ws, Vite, Coinbase. Upgrade ke versi aman yang kompatibel, pertahankan
  struktur pnpm workspace, regenerasi pnpm-lock.yaml dengan benar, build
  produksi, audit ulang OSV + package. Jangan klaim fixed sebelum pohon
  dependency terinstal membuktikannya →
  DEPENDENCY_REMEDIATION_REPORT.md. GATE B: tidak ada Critical/High yang
  memengaruhi deployment tanpa risk acceptance yang didokumentasikan dan
  dibenarkan independen.
- PHASE C — Test infrastructure: deklarasikan test deps
  (@testing-library/react, jsdom, playwright, vitest deps) agar
  reproducible; clean install dari fresh clone; frozen lockfile; tanpa
  symlink node_modules manual; jalankan semua test + E2E + build →
  TEST_INFRASTRUCTURE_REPORT.md.
- PHASE D — Smart contract security: audit semua kontrak (AgentGate,
  QuestManager, SafeValidation, attestation, Reputation, Achievement/
  badge, deployment scripts — VERIFIKASI nama file aktual di repo;
  prompt user menyebut AttestationVerifier.sol/ReputationManager.sol
  yang mungkin bernama lain). 15 area cek; regression test untuk setiap
  masalah terkonfirmasi; jangan ubah interface/storage tanpa dokumentasi
  migrasi → CONTRACT_FINAL_AUDIT.md.
- PHASE E — Attestation finalization: review siklus EIP-712 lengkap
  (12 poin termasuk front-running resistance dan failed tx tidak
  mengonsumsi nonce); cek alur frontend vs ABI aktual; identifikasi
  apakah verifier dashboard/backend signing service dibutuhkan; jangan
  perkenalkan signing key terpusat tanpa mendokumentasikan asumsi
  kepercayaan + kontrol keamanan → ATTESTATION_FINAL_REPORT.md.
- PHASE F — Frontend & wallet: audit aplikasi Next.js lengkap (11 area);
  tanpa data live palsu, tanpa alamat produksi hardcode, ABI benar,
  event indexing benar, chain config benar, error handling tx benar,
  layout mobile responsif, 0 console error; uji dengan wallet injected
  nyata di lingkungan terkontrol bila memungkinkan →
  FRONTEND_FINAL_ACCEPTANCE.md.
- PHASE G — CI/CD validation: inspeksi + eksekusi setiap workflow
  GitHub Actions (12 cek); pin versi tool, permission minimal,
  full-history secret scanning, kegagalan audit terlihat; verifikasi
  perilaku workflow DI GITHUB, bukan hanya lokal →
  CI_FINAL_REPORT.md. CATATAN: repo BELUM punya GitHub remote — verifikasi
  di GitHub tidak mungkin tanpa remote dari user; dokumentasikan jujur.
- PHASE H — Testnet deployment preparation: siapkan deploy BNB Testnet,
  JANGAN broadcast. Verifikasi chain 97, RPC, deployer, Safe, Timelock,
  creator, verifier pertama, integrasi Agent ID, konfigurasi verifikasi
  BscScan, validasi env, urutan deployment, verifikasi pasca-deploy.
  Deployer khusus testnet. Jangan pernah minta private key lewat chat →
  TESTNET_DEPLOYMENT_READINESS.md.
- PHASE I — Final regression: seluruh suite setelah semua perubahan
  (Foundry, fuzz, Vitest, typecheck, lint, build, Playwright E2E, anvil,
  Slither, dependency audit, secret scan); bandingkan dengan baseline;
  dokumentasikan setiap regresi, skipped test, dan masalah tak terselesaikan
  → FINAL_ACCEPTANCE_REPORT.md.

Keputusan akhir: GO / CONDITIONAL GO / NO-GO. GO mensyaratkan: instalasi
bersih reproducible, semua test wajib lulus, tidak ada vuln kritis tak
terselesaikan, CI berhasil dieksekusi DI GITHUB, integrasi kontrak +
frontend terverifikasi, konfigurasi deployment tervalidasi, tidak ada
deployment tanpa izin.

ATURAN NON-NEGOTIABLE (user):
1. Jangan hapus test demi hasil lulus. 2. Jangan lemahkan asersi keamanan.
3. Jangan diam-diam menonaktifkan cek CI. 4. Jangan sembunyikan vuln atau
menurunkan severity tanpa bukti. 5. Jangan deploy/broadcast tanpa approval
eksplisit. 6. Jangan pakai production private key di test. 7. Jangan
tampilkan private key/seed/kredensial di log. 8. Pertahankan arsitektur
kecuali perubahan diperlukan. 9. Perubahan inkremental + dokumentasikan
setiap modifikasi. 10. Berhenti dan laporkan bila kegagalan kritis tidak
bisa diselesaikan dengan aman.

PROTOKOL: kerja berurutan; tiap phase: laporkan temuan → perbaiki →
jalankan test relevan → catat bukti → commit → lanjut hanya bila gate
lulus. Bila phase gagal, berhenti dan laporkan. Jangan skip.

DELIVERABLES: 9 laporan (SOURCE_INTEGRITY, DEPENDENCY_REMEDIATION,
TEST_INFRASTRUCTURE, CONTRACT_FINAL_AUDIT, ATTESTATION_FINAL_REPORT,
FRONTEND_FINAL_ACCEPTANCE, CI_FINAL_REPORT,
TESTNET_DEPLOYMENT_READINESS, FINAL_ACCEPTANCE_REPORT) + commit hash
persis, inventaris file berubah, log test, bukti audit dependency, risiko
tersisa, deployment blocker, keputusan akhir.

KONTEKS PENTING (dari parent):
- Repo BELUM punya GitHub remote → Phase G "verifikasi di GitHub" dan
  syarat GO "CI berhasil di GitHub" TIDAK BISA dipenuhi tanpa remote yang
  dibuat user. Dokumentasikan sebagai blocker eksplisit; jangan klaim GO
  bila syarat ini belum terpenuhi.
- Deployer address, Safe, creator, verifier, BscScan key, tBNB BELUM
  diberikan user → Phase H memvalidasi struktur/konfigurasi, BUKAN
  alamat nyata; jangan mengarang alamat.
- Kendala VM: pnpm install gagal EPERM chown di repo (mount btrfs);
  regenerasi lockfile pakai workaround yang sudah terbukti: salin repo
  ke ~/workspace/.tmp, jalankan `pnpm install --lockfile-only` di sana,
  salin lockfile kembali (JANGAN `pnpm add --lockfile-only` — tetap
  install node_modules ~500 MB). /tmp hanya 512 MB tmpfs — jangan simpan
  file besar di sana. pnpm mungkin tidak ada di PATH sesi exec biasa —
  cari/aktifkan via corepack atau path pnpm yang dipakai sesi sebelumnya.
- RAM ketat: kerja sekuensial. Slither: ~/workspace/slither-venv/bin/slither.
  Foundry: ~/.foundry/bin. Build web: NODE_OPTIONS=--max-old-space-size=1024.
- JANGAN deploy/broadcast. JANGAN sentuh wallet user (baw). JANGAN
  masukkan/cetak private key, seed, mnemonic, API token.
- User: "Jangan berikan izin deployment sebelum laporan akhir menyatakan
  GO" — izin deploy HANYA setelah laporan final menyatakan GO.
- Simpan log perintah ASLI untuk semua bukti. Commit bertahap.
