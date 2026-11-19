# AGENTHUB — Blueprint (ringkasan keputusan + spesifikasi build)

Proyek untuk Binance Wallet Agent ID Hackathon. Total hadiah 60.000 USDC.
Pengumuman: https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf

## Keputusan user (2026-11-19)

- **Mode: MVP dahulu** — fitur inti, keamanan, cepat live.
- **Target: testnet dahulu**, mainnet setelah pengujian lolos.
- **JANGAN submit hackathon dulu** — user mau tes dulu.
- **JANGAN deploy mainnet** tanpa persetujuan eksplisit user (butuh BNB asli + approval).
- AI coding agent: Asta (Muse).

## Klarifikasi kompetisi (user, 2026-11-19 ~12:26 WIB)

- Binance mewajibkan proyek punya kontrak **di BNB Chain (mainnet)**, terverifikasi di
  BscScan, dan memakai Agent ID secara aktif. **Testnet hanya tahap pengembangan,
  BUKAN deployment final untuk kompetisi** — deployment final harus mainnet.
- Urutan pembangunan kontrak (setelah repo selesai): 1. AgentGate (identitas/akses), 2. QuestManager (sistem misi), 3. Reputation (reputasi), 4. Achievement (badge).
- Setiap fitur harus benar-benar bisa digunakan dan dibuktikan lewat transaksi
  blockchain. Target: produk yang layak dinilai juri, bukan sekadar berhasil di-deploy.

## Jadwal hackathon

- Submit: 18 Nov 2026 15:00 WIB – 9 Des 2026 15:00 WIB
- Review internal: 9–17 Des; review publik: 17–20 Des
- Hadiah: Growth Award 29.000 USDC (top 10, metrik on-chain), Innovation Award 29.000 USDC (top 10, juri), Community Promotion 2.000 USDC (20 × 100 USDC via post X)
- Syarat kelayakan Innovation Award: produk live + min 30 alamat Agent ID unik berinteraksi selama periode submit
- Tiap proyek hanya dapat 1 penghargaan proyek. Pemenang juga dapat jatah klaim Agent ID 2 digit.

## Konsep

**AGENTHUB — "Your Agent ID. Your Onchain Reputation."**
Platform aktivitas dan reputasi untuk pemegang Binance Agent ID: quest marketplace,
reputasi on-chain, badge non-transferable, leaderboard, community campaign.
Non-custodial: tidak menyimpan aset pengguna.

## Kontrak resmi Agent ID

- Alamat (BSC): `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` (ERC-721 non-transferable)
- Verifikasi: `balanceOf(address) > 0` pada kontrak resmi itu. Jangan anggap NFT lain valid.

## Arsitektur

| Komponen       | Teknologi                                               |
| -------------- | ------------------------------------------------------- |
| Frontend       | Next.js + TypeScript + Tailwind CSS                     |
| Blockchain     | BNB Smart Chain (testnet dulu: BSC Testnet, chainId 97) |
| Smart contract | Solidity + OpenZeppelin                                 |
| Wallet         | EVM wallet integration                                  |
| Hosting        | Vercel                                                  |
| Source code    | GitHub                                                  |
| Explorer       | BscScan                                                 |

Kontrak: `AgentGate.sol` (verifikasi Agent ID), `QuestManager.sol` (misi),
`Reputation.sol` (skor reputasi), `Achievement.sol` (badge non-transferable).
Boleh digabung jadi 2–3 kontrak agar mudah diaudit.

## Keamanan (wajib)

- Role-based access control, ReentrancyGuard bila relevan, validasi input,
  replay protection (nonce + domain separation), cooldown/rate limit,
  emergency pause, least privilege, role separation + multisig untuk admin.
- TIDAK PERNAH minta seed phrase / private key / API secret / pairing code.
- TIDAK ADA web QR login Agentic Wallet, TIDAK ADA simpan sesi login user,
  TIDAK ADA transaksi aset tanpa konfirmasi user, TIDAK ADA unlimited approval,
  TIDAK ADA transfer otomatis tersembunyi.
- Reputasi hanya naik lewat aksi tervalidasi; admin tidak bisa kasih skor ke diri sendiri tanpa validasi.
- Upgrade (bila ada) via multisig + timelock. Kontrak open-source, izin owner didokumentasikan.
- Test: unit, integration, fuzz, invariant, access-control, Agent ID verification, malicious-input.
- Jangan klaim test/audit/deploy berhasil kalau tidak benar-benar terjadi.

## Fitur MVP

1. Landing page
2. Connect wallet + verifikasi Agent ID (balanceOf > 0)
3. Registrasi profil (1 profil per alamat Agent ID)
4. Quest: daily check-in, first profile, first quest, community campaign
5. Reputasi on-chain + badge non-transferable
6. Leaderboard (berdasarkan aktivitas sah, bukan spam)
7. Campaign creator dashboard (sederhana)
8. Transaction history + halaman keamanan/dokumentasi

## Desain

Dark navy, aksen cyan/electric blue, glassmorphism, tipografi bersih,
mobile-first, terlihat seperti platform Web3 produksi, bukan template generik.

## Pertumbuhan (organik saja)

- Target awal: 30+ alamat Agent ID unik (syarat Innovation Award)
- Misi harian/mingguan/komunitas; hadiah awal berupa badge + reputasi, tanpa janji finansial
- DILARANG: user palsu, transaksi palsu, manipulasi volume, pendaftaran massal

## Deliverables

1. Source code frontend lengkap
2. Source code smart contract lengkap
3. Test suite otomatis (harus lolos)
4. Script deployment (testnet) + contoh env tanpa secret
5. Repo siap GitHub
6. Instruksi verifikasi BscScan
7. Checklist deployment produksi
8. Draf deskripsi submission hackathon (JANGAN disubmit)
9. Instruksi demo
10. Dokumentasi keamanan

## Referensi

- Pengumuman hackathon (link di atas)
- Binance Agentic Wallet docs: https://web3.binance.com/en/dev-docs/products/agentic-wallet/introduction
- OpenZeppelin: https://github.com/OpenZeppelin/openzeppelin-contracts
- Agent ID di BscScan: https://bscscan.com/address/0x60b9262456de011f7d15a54cdd8c48baaa8b022f
