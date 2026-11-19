# AGENTHUB — SECURITY REVIEW REMEDIATION DIRECTIVE

User order 2026-11-19 ~14:29 WIB, setelah memeriksa
`agenthub-source-8b8751e.zip` sendiri. Keputusan user: **belum GO untuk
deployment testnet** sampai dua masalah utama diperbaiki dan diuji.
Verdict GO TESTNET dari re-test (c568ee0) DITUNDA oleh keputusan ini.

## Temuan user

### TEMUAN 1 — Quest completion belum membuktikan tugas dilakukan (P1)

`QuestManager.completeQuest(questId)` hanya memeriksa kepemilikan Agent ID,
status quest, periode, batas penyelesaian, duplikasi, dan cooldown — lalu
langsung memberi poin + badge. Tidak ada bukti aktivitas eksternal dilakukan.
Contoh: quest "bagikan postingan di X" bisa diklaim hanya dengan memanggil
fungsi. Dampak: reputasi dan badge kehilangan kredibilitas.

Perbaikan: bedakan quest:

1. **On-chain:** penyelesaian divalidasi melalui kondisi/transaksi on-chain.
2. **Off-chain:** wajib attestation dari verifier resmi.
3. **Check-in:** didefinisikan eksplisit sebagai self-check-in, bukan bukti
   tugas eksternal.

Attestation harus punya: authorized signer, nonce per pengguna, deadline,
chain ID + contract address binding, quest ID + account binding, proteksi
replay, signature verification yang aman, pengelolaan dan rotasi signer.
Jangan anggap pemanggilan completeQuest sebagai bukti aktivitas eksternal.

### TEMUAN 2 — AgentGate belum mengunci alamat Agent ID resmi (P1)

`AgentGate.sol` constructor (baris 23–31) hanya memeriksa non-zero dan
`code.length > 0`. Kontrak ERC-721 apa pun bisa diterima. Alamat resmi BSC
Mainnet: `0x60B9262456de011f7d15a54cdd8c48baaa8b022f`. Validasi frontend
(`apps/web/lib/env.ts`) bukan pengaman on-chain. Dampak: salah konfigurasi
saat deploy mainnet → pemegang NFT palsu lolos pemeriksaan identitas.

Perbaikan:

- Chain 56 WAJIB alamat Agent ID resmi.
- Chain 97 boleh MockAgentId.
- Chain 31337 boleh mock lokal.
- Tambah regression test: tolak alamat palsu di chain 56; test alamat salah
  dan chain yang tidak sesuai.

### TEMUAN 3 — Dependency validation (P2)

Constructor QuestManager:

- Validasi dependency bukan zero address.
- Validasi dependency merupakan kontrak.
- Pemeriksaan integrasi untuk Gate, Reputation, Achievement.
- Jangan anggap cek code length saja membuktikan kontrak tepercaya.

### TEMUAN 4 — Deployment (P2)

Buat deployment script untuk AgentGate, Reputation, Achievement,
QuestManager:

- Urutan deployment benar.
- Role diberikan ke alamat yang tepat.
- SCORE_SOURCE_ROLE dan ISSUER_ROLE ke QuestManager.
- Admin dan operational roles dipisahkan.
- Tidak ada privilege deployer tertinggal.
- Mainnet menolak mock Agent ID.
- Script TIDAK melakukan deployment mainnet otomatis.

## Pemeriksaan user atas 2 kontrak lain (statis awal, bukan audit formal)

- **Reputation.sol:** tidak ada fungsi admin tambah poin sembarangan;
  pembatasan SCORE_SOURCE_ROLE desain baik.
- **Achievement.sol:** soulbound, penerbitan dibatasi role, `_mint` tanpa
  callback ERC-721 — desain tepat.
- User belum menyimpulkan keduanya bebas kerentanan.

## Kekurangan paket ZIP (P3)

- Folder `lib` submodule tidak disertakan (bawaan `git archive`).
- Tidak ada PACKAGE_MANIFEST.md.
- Tidak ada metadata Git untuk verifikasi commit.
- README.md masih menyebut Phase 1 dan kontrak belum diimplementasikan
  (stale — empat kontrak sudah tersedia).
- Laporan keamanan menyebut snapshot `c666878`, ZIP dikirim sebagai
  `8b8751e` — tanpa metadata Git, asal commit tidak bisa diverifikasi dari
  ZIP saja.
- Tidak ditemukan `.env` asli atau private key (bukan jaminan mutlak).

Perbaikan P3: lengkapi paket review (submodule, manifest, metadata commit,
perbarui README).

## Pengujian wajib

Unit, fuzz, invariant, attack simulation, signature replay, unauthorized
signer, fake Agent ID, quest farming, access control, integration.
Jangan hapus atau lemahkan test yang sudah ada.

## Laporan

- REMEDIATION_REPORT.md
- NEW_THREAT_MODEL.md
- QUEST_VALIDATION_DESIGN.md
- DEPLOYMENT_PLAN.md
- REGRESSION_RESULTS.md

## Aturan

- Jangan deploy ke jaringan mana pun.
- Jangan gunakan private key atau dana sungguhan.
- Jangan menyatakan vulnerability sudah diperbaiki sebelum regression test
  membuktikannya.
- Berikan daftar perubahan kode dan hasil pengujian secara lengkap.
