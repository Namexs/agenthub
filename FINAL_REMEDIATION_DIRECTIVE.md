# AGENTHUB — FINAL PRE-TESTNET REMEDIATION & INTEGRATION DIRECTIVE

User order 2026-11-19 ~16:26 WIB. Baseline: HEAD `c5bed05`
(218 Foundry tests, 24 Vitest, Slither 10: 4 Low + 6 Info, format:check
hijau, manifest terverifikasi untuk c1aaebc).

Perintah lengkap user tersimpan di chat turn ini (10 phase). Ringkasan:

- PHASE 1 — Safe multisig authenticity: verifikasi singleton/implementation
  Safe terhadap alamat resmi per jaringan; jangan hanya getThreshold/
  getOwners; threshold ≥2-of-N; tolak zero/EOA; cek chain ID; bila on-chain
  tidak bisa membuktikan identitas Safe, wajib prosedur verifikasi manual;
  jangan klaim terverifikasi tanpa bukti. Test: genuine, fake interface,
  threshold 1, threshold > owners, EOA, wrong chain, zero address.
- PHASE 2 — PAUSER_ROLE consistency: multisig terverifikasi sebagai pemegang
  PAUSER_ROLE di konfigurasi default produksi; deployer tidak mempertahankan
  operational role setelah handover; pisahkan semua role; Timelock untuk
  tindakan sensitif; role matrix; selaraskan script + semua docs.
- PHASE 3 — Git & package integrity: satu commit final sebagai source of
  truth; rev-parse/status/submodule tercatat; manifest diregenerasi (SHA-256
  ulang, 100% cocok); secret scan sebelum ZIP; 0 secret; jangan mengarang
  commit bila metadata tidak valid.
- PHASE 4 — CI & dependency security: perkuat GitHub Actions (11+ job:
  build, test, fuzz/invariant, fmt, slither, lint, typecheck, web build,
  shared test, vitest, prettier, dependency audit, secret scanning); pin
  Foundry/Node/pnpm; frozen lockfile; permission minimal; jangan klaim
  audit lulus tanpa hasil aktual. CATATAN: repo BELUM punya GitHub remote —
  CI tidak bisa dijalankan di GitHub; jelaskan + berikan bukti lokal.
- PHASE 5 — Approved validator registry: hanya validator disetujui admin;
  identitas + versi + dokumentasi per validator; tolak zero/EOA; kebijakan
  quest aktif saat validator dicabut; emergency revocation; code.length
  bukan bukti aman. Test: approved, unapproved, malicious, false, revert,
  revoked, zero, EOA, returndata tidak valid.
- PHASE 6 — Verifier security: perkuat EIP-712 attestation (signer resmi,
  nonce, deadline, binding chain/kontrak/quest/akun, anti-replay,
  anti-malleability, rotasi, revokasi, tolak expired/unauthorized) + SOP
  (key management, rotasi, pencabutan, key compromise, monitoring);
  pertimbangkan multisig/threshold attestation untuk quest bernilai tinggi.
  Jangan pernah masukkan private key ke source.
- PHASE 7 — Frontend integration nyata (bukan data statis): Agent ID
  (connect Binance Wallet, deteksi chain, cek AgentGate, tolak chain tak
  didukung), quest marketplace on-chain (list/detail/status/eligibility/
  completion/konfirmasi/error), attestation flow, reputation (read + riwayat
  dari event), achievement (soulbound, tanpa transfer), leaderboard dari
  event (pagination, dedup, waktu update), tx history (hash, block, status,
  link BscScan per jaringan). Alamat kontrak dari konfigurasi tervalidasi.
- PHASE 8 — Frontend testing: Vitest untuk semua alur (wallet, wrong
  network, holder/non-holder, quest, attestation, reputation, badge,
  pending/success/failure, RPC error, empty state) + E2E bila browser
  tersedia. Jangan klaim integrasi penuh hanya dari build berhasil.
- PHASE 9 — Final security regression: forge clean/build/test -vvv/
  fuzz 10k/fmt, slither, pnpm lint/typecheck/test/build/format:check + semua
  test baru; periksa 12 kategori serangan; setiap temuan: severity, file,
  function, line, exploit scenario, impact, PoC, remediation, regression
  test. Jangan ubah test agar vulnerability terlihat hilang.
- PHASE 10 — Testnet readiness: deployment checklist; validasi alamat Agent
  ID per jaringan; verifikasi Safe independen; validasi dependency address;
  role matrix; Timelock; deployer khusus testnet; key hanya di environment
  aman; tBNB; BscScan API key via secret manager. DEPLOY HANYA setelah
  persetujuan eksplisit user. Mainnet butuh persetujuan terpisah.

Deliverables: folder `agenthub-final-pretestnet/` berisi
FINAL_REMEDIATION_REPORT.md, SAFE_VALIDATION_REVIEW.md,
PAUSER_ROLE_REVIEW.md, APPROVED_VALIDATOR_REGISTRY.md,
VERIFIER_SECURITY_SOP.md, FRONTEND_INTEGRATION_REPORT.md,
CI_EVIDENCE.md, FINAL_SECURITY_FINDINGS.md,
FINAL_DEPLOYMENT_CHECKLIST.md, PACKAGE_MANIFEST.md, logs/,
test-results/ — plus ZIP source terbaru tanpa kredensial.

Keputusan akhir: GO / CONDITIONAL GO / NO-GO TESTNET berdasarkan bukti.
JANGAN menyatakan GO bila ada Critical/High terbuka, test utama gagal,
konfigurasi identitas salah, atau deployment authority belum diverifikasi.

KONTEKS PENTING (dari parent):
- Deployment authority BELUM diverifikasi: user belum memberikan tBNB,
  deployer key, alamat Safe, atau kunci verifier. Ini membatasi keputusan
  maksimal menjadi CONDITIONAL GO — jangan klaim GO penuh.
- Repo belum punya GitHub remote → CI GitHub tidak bisa dijalankan.
- Jangan broadcast/deploy ke jaringan mana pun. Jangan sentuh wallet user
  (baw). Jangan pernah memasukkan/mencetak private key/seed/token.
- Pertahankan semua test yang ada; jangan hapus/melemahkan test; jangan
  ubah laporan lama agar terlihat lebih baik.
- RAM VM ketat: kerjakan sekuensial, jangan fan-out paralel berat.
- /tmp hanya 512 MB tmpfs — jangan simpan file besar di sana; pakai
  ~/workspace/.tmp bila perlu. pnpm install exit 255 EPERM chown adalah
  masalah lingkungan VM (bukan cacat repo); lockfile-only workaround:
  `pnpm install --lockfile-only` (bukan `pnpm add --lockfile-only` yang
  tetap install node_modules ~500 MB).
- Slither: ~/workspace/slither-venv/bin/slither (bukan di PATH).
- Foundry: ~/.foundry/bin (tambah ke PATH).
- Build web: NODE_OPTIONS=--max-old-space-size=1024.
- Simpan log perintah ASLI (bukan ringkasan) untuk semua bukti.
- Prinsip user: jangan kejar angka test besar; jangan buat temuan palsu;
  jangan sembunyikan kegagalan; jangan klaim keamanan absolut.

## GATE PER PHASE (tambahan user 2026-11-19 ~16:31 WIB)

Kerjakan secara BERURUTAN. Jangan melewati phase bila pengujian phase
sebelumnya gagal — perbaiki dulu sampai hijau, baru lanjut. Tiga hasil
yang harus didapat:
1. Smart contract: konfigurasi Safe, role, validator, verifier
   benar-benar diperkuat.
2. Frontend: website tidak lagi hanya data contoh, tetapi terhubung
   dengan blockchain.
3. Deployment: semua konfigurasi siap untuk BNB Testnet tanpa langsung
   menyentuh Mainnet.

Setelah selesai, kirim ZIP source terbaru + laporan final ke user di chat
ini. User akan memeriksa sendiri sebelum memberikan izin deployment
Testnet. JANGAN deploy tanpa izin itu.
