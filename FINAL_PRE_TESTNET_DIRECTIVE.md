# AGENTHUB — FINAL PRE-TESTNET CLEANUP DIRECTIVE

User order 2026-11-19 ~15:49 WIB. Baseline: HEAD `76572c6` (remediasi
selesai, 193/193 test).

Aturan utama: **jangan ubah logika smart contract yang sudah lulus pengujian,
kecuali ditemukan bug yang terbukti.**

## Tugas

1. Perbaiki PACKAGE_MANIFEST.md agar seluruh 168 hash cocok dengan source
   tree terbaru.
2. Pastikan commit dan manifest konsisten.
3. Perbarui docs/SECURITY_DEPLOYMENT_GATE.md berdasarkan kondisi terbaru:
   - 193 Foundry tests.
   - Slither 10 findings: 0 Critical/High/Medium, 4 Low, 6 Informational.
   - Deployment script sudah tersedia.
   - Testnet belum benar-benar di-deploy.
4. Tambahkan Vitest untuk apps/web dan packages/shared. (Ini menutup temuan
   M4 dari audit Phase 1: nol unit test web/shared.)
5. Tambahkan validasi operasional agar alamat ADMIN_MULTISIG diverifikasi
   sebagai Safe dan threshold-nya diperiksa sebelum deployment.
6. Buat daftar validator yang disetujui untuk quest OnChain.
7. Buat SOP pengelolaan VERIFIER_ROLE, termasuk rotasi dan pencabutan.
8. Investigasi dua kegagalan sementara yang pernah muncul. Jika tidak dapat
   direproduksi, dokumentasikan secara eksplisit.
9. Jalankan ulang seluruh 193 Foundry tests, fuzz 10.000 runs, Slither,
   lint, typecheck, dan build.
10. Jangan broadcast transaksi atau deploy ke jaringan.

## Deliverable

- Laporan FINAL_PRE_TESTNET.md (di docs/) + seluruh bukti pengujian (log
  perintah asli).
- Keputusan GO atau NO-GO untuk testnet.
