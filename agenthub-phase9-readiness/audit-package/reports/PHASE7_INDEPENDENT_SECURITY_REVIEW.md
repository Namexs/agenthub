# AGENTHUB — Phase 7: Independent Security Review & Testnet Preparation

**Tanggal:** 20 November 2026.
**HEAD yang diaudit:** `5723ff3` (`5723ff377de3d2cd79854b877124a802fb2c23eb`).
**Baseline pembanding:** `129439a` (Phase 6 baseline).
**Laporan acuan:** `agenthub-phase6-threshold/PHASE6_THRESHOLD_IMPLEMENTATION_REPORT.md`
dan `agenthub-phase6-threshold/test-results/gas-benchmark-threshold.md`.
**Metode:** 8 workstream spesialis independen (diff audit, review kontrak,
analisis serangan + PoC Foundry, audit kebijakan, paritas ABI, audit bytecode,
test battery penuh, audit deployment) — masing-masing membaca kode langsung,
bukan mempercayai ringkasan Phase 6. Laporan per-workstream tersimpan di
`agenthub-phase7-review/findings/` (01–08). Tidak ada deploy, tidak ada
broadcast, tidak ada private key yang dipakai. Tidak ada file terlacak yang
diubah di repo (4 file log yang sempat diperbarui runner test dikembalikan ke
HEAD; hanya direktori `agenthub-phase7-review/` yang baru).

## 1. Keputusan

**CONDITIONAL GO untuk validasi live BNB Testnet. NO-GO untuk mainnet.**

**Alasan GO testnet (bersyarat):**

- Tidak ditemukan kerentanan Critical, dan tidak ada satu pun vektor serangan
  yang exploitable oleh penyerang eksternal — seluruh jalur replay
  (cross-chain, cross-quest, cross-deadline, cross-account, pasca-completion),
  substitusi signature, dan griefing nonce ditolak kode, masing-masing
  dibuktikan PoC Foundry (39 PoC: 14 + 25, semuanya lolos).
- Kriptografi threshold M-of-N benar: recovery ECDSA, digest EIP-712,
  nonce sekali pakai, deadline, deteksi duplikat, dan pengecekan
  `VERIFIER_ROLE` per signer semuanya sesuai spesifikasi.
- Immutability `attestationThreshold` terbukti per instance quest
  (satu-satunya jalur tulis di `createQuest`, tanpa setter, tanpa proxy).
- ABI frontend identik 0 drift dari 201 entri; bytecode aman
  (0 opcode Cancun-only, ukuran < 50% batas EIP-170); seluruh test battery
  hijau dengan angka yang terverifikasi ulang secara independen.
- Satu-satunya temuan High (PH7-H01) adalah celah penegakan kebijakan yang
  blast radius-nya di testnet nihil: creator testnet adalah tim sendiri,
  poin testnet tidak bernilai, dan testnet justru tempat proses kebijakan
  itu dilatih.

**Syarat sebelum broadcast testnet:**

1. Perbaiki PH7-M05 (broadcast guard testnet) dan PH7-M06 (chain guard test
   stack) — keduanya perbaikan satu baris pada script deploy, risiko
   regresi minimal — atau terima secara eksplisit dengan mitigasi prosedural.
2. Putuskan nasib ownership MockAgentId (PH7-M04) sebelum deployment-day.
3. Kedelapan input deployment dari user tetap diperlukan (lihat §11).
4. R-010 tetap TIDAK CLOSED sampai smoke test testnet live berhasil.

**Alasan NO-GO mainnet:** PH7-H01 wajib diperbaiki on-chain sebelum mainnet
(kebijakan threshold adalah inti jaminan R-010); PH7-M01–M03, PH7-M07–M09,
dan evaluasi solc (PH7-L20) harus ditutup atau diterima secara formal;
external review (R-012) belum dikomisikan; wallet-app nyata belum pernah
diuji (O4). Daftar lengkap perbaikan pra-mainnet ada di §11.

**R-010: IMPLEMENTED, belum CLOSED.** Status tidak berubah — penutupan
membutuhkan live testnet smoke test yang belum terjadi.

## 2. Ringkasan temuan

**59 temuan unik** setelah deduplikasi 63 temuan mentah dari 8 workstream
(4 pasang temuan ganda digabung — lihat Lampiran A).

| Severity      | Jumlah | ID                   |
| ------------- | -----: | -------------------- |
| Critical      |      0 | —                    |
| High          |      1 | PH7-H01              |
| Medium        |     10 | PH7-M01 s.d. PH7-M10 |
| Low           |     31 | PH7-L01 s.d. PH7-L31 |
| Informational |     17 | PH7-I01 s.d. PH7-I17 |
| **Total**     | **59** |                      |

### Temuan High dan Medium

| ID      | Temuan                                                                       | Sumber           |
| ------- | ---------------------------------------------------------------------------- | ---------------- |
| PH7-H01 | Kebijakan threshold (> 1.000 poin → ≥ 2) tidak ditegakkan on-chain           | 04/P-01          |
| PH7-M01 | Revoke verifier di bawah threshold me-brick quest (tanpa guardrail on-chain) | 02/F1 + 03/P7-01 |
| PH7-M02 | "Real-world badge" tidak didefinisikan di kode mana pun                      | 04/P-02          |
| PH7-M03 | Tanpa timelock/review quest bernilai besar; creator alamat tunggal           | 04/P-05          |
| PH7-M04 | Deployer tetap owner MockAgentId                                             | 08/M-01          |
| PH7-M05 | Tanpa broadcast guard untuk testnet                                          | 08/M-02          |
| PH7-M06 | DeployLocalTestStack tanpa chain guard + kunci publik hardcoded              | 08/M-03          |
| PH7-M07 | Deep-equal ABI parity tidak pernah berjalan di CI                            | 05/F1            |
| PH7-M08 | Parity test hanya mencakup QuestManager                                      | 05/F2            |
| PH7-M09 | EVENT_SIGNATURES tulisan tangan tanpa test; gagal diam-diam                  | 05/F3            |
| PH7-M10 | Klaim "via-IR menghilangkan MCOPY" salah (false positive metadata)           | 06/F1            |

### Temuan Low (ringkas — detail di §5)

PH7-L01 emisi reputasi tanpa batas total · PH7-L02 kopling pause asimetris ·
PH7-L03 TOCTOU sisi grant · PH7-L04 perilaku validator berubah pasca-approval ·
PH7-L05 cek threshold setelah loop recovery (gas terbuang) ·
PH7-L06 nonce global per akun · PH7-L07 deactivate + recreate = klaim ganda ·
PH7-L08 threshold tidak ditegakkan untuk quest non-Attested ·
PH7-L09 tanpa UI pembuatan quest · PH7-L10 tanpa test kebijakan ·
PH7-L11 anvil-integration membaca ABI dari `out/` · PH7-L12 ABI inline +
konstanta EIP-712 tulisan tangan · PH7-L13 solc 0.8.24 + via-IR terpapar bug
compiler · PH7-L14–L23 temuan deployment Low (L-01 s.d. L-10) ·
PH7-L24–L31 temuan akurasi bukti/dokumentasi (S-01, S-02, S-03, S-04, S-05,
S-06, S-07, S-09; S-04 DITUTUP dalam review ini oleh pengukuran ulang gas —
lihat §9).

### Temuan Informational (ringkas — detail di §6)

PH7-I01 frontend menerima high-s/v∈{0,1} · PH7-I02 komentar NatSpec
menyesatkan · PH7-I03 deactivateQuest permanen · PH7-I04 event QuestCreated
tidak memuat threshold · PH7-I05 temuan Slither app-only sudah ditelaah ·
PH7-I06 replay pada fork chainId sama (accepted risk) · PH7-I07 kebijakan
hanya bermakna untuk Attested · PH7-I08 AGENT_ID_ABI tak terverifikasi ·
PH7-I09 generator ABI tanpa mode `--check` · PH7-I10 angka opcode dalam
brief audit salah · PH7-I11 waktu build legacy 2 mnt 4 dtk (bukan ~8 dtk) ·
PH7-I12 QuestManager 49,93% batas ukuran · PH7-I13–I16 temuan deployment
Informational (I-01 s.d. I-04) · PH7-I17 reflow Prettier kosmetik.

## 3. Temuan High

### PH7-H01 — Kebijakan threshold (> 1.000 poin → threshold ≥ 2) tidak ditegakkan on-chain

**Severity: High.** Sumber: findings/04-policy-enforcement.md (P-01).

**Bukti.** `createQuest` (`packages/contracts/src/QuestManager.sol:133-183`)
hanya memvalidasi: role creator, judul 1–128 byte, deskripsi ≤ 1.024 byte,
`0 < rewardPoints ≤ 10.000` (baris 150), jendela waktu, threshold 1–3
(baris 156–158), badge terdefinisi, dan aturan validator. Tidak ada satu pun
pemeriksaan yang menghubungkan `rewardPoints` dengan `attestationThreshold`.
Grep angka `1.000` sebagai ambang kebijakan di seluruh kode (kontrak,
frontend, shared, test) menghasilkan nol; komentar di
`QuestManager.sol:64-65` justru menegaskan batas threshold "uniform for all
quest kinds". Kebijakan ini hanya hidup di dokumen: `docs/VERIFIER_ROLE_SOP.md:165-167`
(§6.1) dan `docs/QUEST_VALIDATION_DESIGN.md:120-123`. Rencana remediasi
sendiri merumuskannya hanya sebagai _"Recommended policy"_ — Phase 6
mengimplementasikan mekanismenya, bukan kebijakannya — tetapi laporan
Phase 6 tidak menyatakan eksplisit bahwa kebijakan itu SOP-only, sehingga
menimbulkan false confidence.

**Reproduksi.** Pemegang `QUEST_CREATOR_ROLE` memanggil `createQuest` dengan
`rewardPoints = 10.000`, `validationKind = Attested`, `maxCompletions = 0`,
`attestationThreshold = 1` → transaksi sukses, quest live, threshold
immutable. Satu verifier yang dikompromikan kini dapat mengesahkan quest
10.000 poin sendirian, untuk akun mana pun, tanpa batas jumlah akun — persis
skenario yang dirancang untuk dicegah R-010. Varian sama berbahayanya:
creator jujur yang salah mengetik threshold 1 pada quest 5.000 poin — tanpa
peringatan, dan kesalahan itu permanen (hanya bisa diperbaiki dengan
deactivate + recreate).

**Dampak.** Integritas reputasi — aset utama platform. Bukan Critical karena
membutuhkan role tepercaya, tidak ada dana langsung yang dipertaruhkan, dan
`deactivateQuest`/`pause()` tersedia sebagai rem darurat. Threat model
menerima risiko "rogue creator" sebagai "capped" — tetapi "capped" merujuk
pada cap 10.000 poin per quest, bukan pada absennya penegakan threshold.

**Rekomendasi.** (1) Validasi on-chain di `createQuest`: konstanta
`HIGH_VALUE_REWARD_POINTS = 1.000`, tolak quest Attested dengan
`rewardPoints > 1.000 && attestationThreshold < 2` (error baru). Putuskan
eksplisit apakah aturan berlaku hanya untuk Attested. (2) Penegakan di
tooling pembuatan quest sebagai lapis kedua. (3) Test kebijakan di CI
(reward 1.001/T1 revert; 1.001/T2 sukses; 1.000/T1 sukses).
(4) Sampai penegakan teknis ada, SOP dan laporan harus menyatakan eksplisit
bahwa kebijakan ini prosedural (SOP-only).

## 4. Temuan Medium

### PH7-M01 — Revoke verifier di bawah threshold me-brick quest; tanpa guardrail on-chain

**Severity: Medium.** Sumber: findings/02-questmanager-review.md (F1) +
findings/03-threshold-immutability-attacks.md (P7-01). Dibuktikan dua PoC
independen.

**Bukti.** `_verifyAttestations` (`QuestManager.sol:245-281`) menegakkan
`provided >= threshold` dan `VERIFIER_ROLE` per signer, tetapi tidak ada kode
yang menghubungkan jumlah verifier aktif dengan threshold quest yang live.
`grantRole`/`revokeRole` adalah `AccessControl` standar tanpa override, dan
`AccessControl` tidak bisa mengenumerasi pemegang role. `createQuest` hanya
memvalidasi rentang 1–3 tanpa memeriksa jumlah verifier — quest T3 yang
dibuat saat hanya ada 1 verifier langsung brick sejak lahir.

**Reproduksi.** PoC `testB7b` (attack) dan `test_PoC_RevocationBricksThresholdQuest`
(contracts): quest T2 saat ada 3 verifier → cabut 2 verifier → completion
1 signature revert `InsufficientAttestations(1, 2)`; pasangan dengan
signature tercabut revert `UnauthorizedVerifier`. Quest tidak bisa
diselesaikan siapa pun sampai re-grant (timelock 2 hari) atau deactivate +
recreate (lihat PH7-L07).

**Dampak.** Ketersediaan (availability), bukan pencurian. Membutuhkan aksi
admin tepercaya (timelock), sehingga Medium, bukan High. Namun skenario
nyata: kunci verifier dikompromikan dan harus segera dicabut → admin dipaksa
memilih antara membiarkan kunci kompromi aktif atau me-brick quest.

**Rekomendasi.** (1) Guardrail on-chain: override `_grantRole`/`_revokeRole`
untuk memelihara `verifierCount`, lacak `highestLiveThreshold`, tolak revoke
bila `verifierCount - 1 < highestLiveThreshold`; cek yang sama di
`createQuest`. (2) Minimal: tooling off-chain pre-revoke yang menghitung
verifier hidup dari event `RoleGranted`/`RoleRevoked` dan menolak revoke
yang melanggar. (3) Dokumentasikan jalur pemulihan di SOP.

### PH7-M02 — "Real-world badge" tidak didefinisikan di mana pun dalam kode

**Severity: Medium.** Sumber: findings/04-policy-enforcement.md (P-02).

**Bukti.** Grep `real-world|realWorld|high-value|highValue` di seluruh repo:
nol hasil di kode; hanya dokumen (SOP §6.1, rencana remediasi, laporan
Phase 6). Struct `Badge` (`Achievement.sol:25-29`) hanya
`{name, tokenURI, defined}` — tanpa kategori/flag nilai. `defineBadge`
tidak menerima parameter nilai. `createQuest` hanya memeriksa
`isBadgeDefined(badgeId)`.

**Dampak.** Paruh kedua kebijakan threshold tidak dapat diimplementasikan
sebagaimana dirumuskan. Bahkan bila PH7-H01 diperbaiki berbasis
`rewardPoints`, celah badge tetap terbuka: quest 50 poin dengan badge yang
membuka manfaat dunia nyata tetap bisa dibuat threshold 1. Medium (bukan
High) karena badge saat ini soulbound tanpa utilitas on-chain tercatat —
nilai dunia nyatanya masih prospektif.

**Rekomendasi.** (1) Tambahkan field `bool highValue` / enum kategori pada
`Badge`, diisi saat `defineBadge` oleh `BADGE_MANAGER_ROLE`, plus getter
`isBadgeHighValue`; `createQuest` menolak threshold 1 bila badge high-value.
(2) Alternatif: mapping khusus di `QuestManager`. (3) Minimal tanpa
perubahan kontrak: SOP memuat daftar eksplisit badgeId real-world-value.

### PH7-M03 — Tanpa timelock/review untuk quest bernilai besar; creator alamat tunggal

**Severity: Medium.** Sumber: findings/04-policy-enforcement.md (P-05).

**Bukti.** `createQuest` langsung efektif dalam satu transaksi
(`onlyRole(QUEST_CREATOR_ROLE)` saja, `QuestManager.sol:145`), tanpa
timelock, jeda review, atau persetujuan kedua; quest langsung `active = true`.
Timelock hanya memegang `DEFAULT_ADMIN_ROLE` pasca-deploy
(`DeployAgentHub.s.sol:228-230`); `QUEST_CREATOR_ROLE` diberikan langsung ke
satu alamat `params.questCreator` (baris 221) tanpa validasi multisig —
berbeda dengan `adminMultisig` yang melalui validasi Safe eksplisit.
Threat model mengklaim mitigasi "role is multisig-held in production"
(`SECURITY_THREAT_MODEL.md:143-146`) — klaim operasional yang tidak
ditegakkan kode maupun script deploy. Tidak ada status draft/pending atau
fungsi persetujuan quest oleh admin.

**Dampak.** Satu kunci creator yang dikompromikan — atau satu kesalahan
operator — langsung menerbitkan quest bernilai besar yang live, tanpa
jendela penangkapan kesalahan sebelum completion terjadi. Dikombinasikan
dengan PH7-H01, seluruh rantai perlindungan quest bernilai tinggi bertumpu
pada satu alamat dan satu manusia. Medium karena dampak terbatas pada poin
reputasi dan rem pasca-publikasi (deactivate + pause) tersedia.

**Rekomendasi.** (1) Jadikan `QUEST_CREATOR` Safe multisig (≥ 2-of-3)
sebagai persyaratan deployment yang diverifikasi — tambahkan pemeriksaan di
`DeployAgentHub.s.sol` sejajar validasi `adminMultisig`. (2) Review window:
quest `rewardPoints > 1.000` tidak dapat diselesaikan sebelum X jam setelah
pembuatan. (3) Alur dua langkah untuk quest bernilai besar
(creator mengajukan → admin/timelock menyetujui).

### PH7-M04 — Deployer tetap menjadi owner MockAgentId

**Severity: Medium.** Sumber: findings/08-deployment-testnet.md (M-01).

**Bukti.** `new MockAgentId()` di dalam blok broadcast
(`DeployAgentHub.s.sol:185`) → owner = deployer
(`MockAgentId.sol:16`, `Ownable(msg.sender)`). Tidak ada
`transferOwnership`/`renounceOwnership` di seluruh `deploy()`, dan
`_verifyWiring` tidak memeriksa `mock.owner()`. Ini melanggar klaim header
script ("The deployer ends with ZERO privileges"), `ROLE_MATRIX.md` §2, dan
checklist §4.3 langkah 12 — semuanya benar untuk role AccessControl, tetapi
kepemilikan `Ownable` pada mock bukan role sehingga lolos dari semua
pemeriksaan. Deployer bisa `mint()` Agent ID mock tanpa batas kapan pun.
Artefak broadcast fork mengonfirmasi: 6 CREATE + 12 CALL, nol
`transferOwnership`.

**Dampak.** Testnet-only (mock tidak pernah di mainnet). Di staging,
pemegang kunci deployer bisa mencetak identitas Agent ID palsu dan
menyelesaikan quest apa pun — merusak validitas smoke test dan demo.
Kontradiksi prosedural: `DEPLOYMENT_PLAN.md` §4.6 menyuruh membuang kunci
deployer, tetapi checklist §5.1 membutuhkan deployer untuk mint test
Agent ID.

**Rekomendasi.** (1) Di akhir `deploy()`, `mock.transferOwnership(params.adminMultisig)`
— minting smoke test lewat Safe. Atau dokumentasikan retensi kunci eksplisit
sampai smoke test selesai + langkah transfer terpisah. (2) Tambahkan cek
`mock.owner()` ke `_verifyWiring`. (3) Perbaiki klaim "ZERO privileges".

### PH7-M05 — Tidak ada broadcast guard untuk testnet (chain 97)

**Severity: Medium.** Sumber: findings/08-deployment-testnet.md (M-02).

**Bukti.** Satu-satunya guard persetujuan eksplisit adalah
`CONFIRM_MAINNET_DEPLOY` untuk chain 56 (`DeployAgentHub.s.sol:111`).
Grep `CONFIRM_TESTNET` → 0 hasil. Di chain 97, `run()` langsung
`vm.startBroadcast(deployerKey)` (baris 127) begitu env terisi. Kontrol
satu-satunya adalah prosedural (checklist §1 item 8) — script, garis
pertahanan terakhir, tidak menegakkannya. Dry-run fork membuktikan: tanpa
guard, script hanya gagal di validasi Safe; bila `ADMIN_MULTISIG` diisi
Safe asli, script lanjut ke broadcast tanpa memeriksa persetujuan apa pun.

**Dampak.** Satu perintah `--broadcast` yang dijalankan terlalu dini
men-deploy staging dengan parameter apa pun yang ada di env. Kerusakan
dapat dipulihkan (redeploy), tetapi deploy yang "sudah terlanjur" dapat
membingungkan (alamat staging ganda, frontend menunjuk stack yang salah)
dan melanggar kontrol proses "No approval = no broadcast".

**Rekomendasi.** Tambahkan guard simetris `CONFIRM_TESTNET_DEPLOY=true`
yang wajib di chain 97 (dan `CONFIRM_LOCAL_DEPLOY` opsional untuk 31337).
Perbarui `.env.example`, `DEPLOYMENT_PLAN.md` §3, checklist §4.2 langkah 5.

### PH7-M06 — DeployLocalTestStack tanpa chain guard + kunci publik hardcoded

**Severity: Medium.** Sumber: findings/08-deployment-testnet.md (M-03).

**Bukti.** `DeployLocalTestStack.s.sol:70,78` memanggil
`vm.startBroadcast(DEPLOYER_KEY)` dan `vm.startBroadcast(ALICE_KEY)` tanpa
satu pun pemeriksaan `block.chainid` di `run()`. Bandingkan
`DeployMock.s.sol:18` yang memiliki allowlist chain. Kunci yang di-hardcode
(baris 36, 40–44): kunci deployer anvil 0, kunci alice, kunci verifier
`0xA11CE5`/`0xA11CE6` — semuanya publik dan trivial (bukan kebocoran
rahasia — sudah di-allowlist gitleaks). Stack memakai admin = deployer
langsung tanpa timelock/Safe (baris 88–99).

**Dampak.** Salah ketik `--rpc-url` (menunjuk RPC testnet, bukan
`127.0.0.1:8545`) + `--broadcast` — persis pola perintah di komentar
header script — men-deploy satu stack AGENTHUB penuh di testnet dengan
admin = alamat anvil 0, yang kunci privatnya diketahui semua orang.
Siapa pun bisa grant role, membuat quest, pause/unpause, dan mencetak
MockAgentId di stack itu — yang terlihat seperti deployment sah di BscScan.

**Rekomendasi.** Satu baris di awal `run()`:
`require(block.chainid == 31337, "DeployLocalTestStack: local Anvil only");`

### PH7-M07 — Deep-equal ABI parity check tidak pernah berjalan di CI

**Severity: Medium.** Sumber: findings/05-abi-parity.md (F1).

**Bukti.** `abi-parity.test.ts:28,77`: `describe.skipIf(!buildExists)` —
deep-equal di-skip bila `packages/contracts/out/.../QuestManager.json`
tidak ada. Job `web` CI (`.github/workflows/ci.yml:40-66`) tidak memiliki
langkah foundry-toolchain, `forge build`, maupun download artefak; `out/`
di-gitignore sehingga `buildExists` selalu `false` di job web. Job
`contracts` menjalankan forge tetapi bukan vitest dan tidak mengunggah
`out/`; job `e2e` menjalankan forge + Playwright tetapi bukan vitest.
Tidak ada kombinasi job yang menjalankan forge dan vitest bersamaan.

**Dampak.** Jaring pengaman drift ABI yang dirancang Phase 6 tidak
berfungsi di pipeline. Perubahan kontrak yang di-merge tanpa regenerasi
ABI tetap membuat CI hijau. Mitigasi parsial: wallet E2E CI menangkap
drift hanya pada fungsi yang dilalui (`isAgentHolder`, daftar quest,
completion, `points`); drift pada `createQuest` (jalur admin), sebagian
besar getter/event/error lolos ke produksi dan baru gagal saat runtime.

**Rekomendasi.** (1) Tambahkan foundry-toolchain + `forge build` di job
`web` sebelum vitest (biaya ~5 menit build via-IR; pantau timeout 15
menit). (2) Atau pindahkan deep-equal ke job yang sudah memiliki forge.
(3) Minimal: mode `--check` pada `export-abis.mjs` di CI (lihat PH7-I09).

### PH7-M08 — Parity test hanya mencakup QuestManager

**Severity: Medium.** Sumber: findings/05-abi-parity.md (F2).

**Bukti.** `abi-parity.test.ts` hanya mengimpor `QUEST_MANAGER_ABI`
(baris 6) dan hanya membangun satu `artifactPath`. Tidak ada deep-equal —
bahkan lokal dengan `out/` tersedia — untuk `AgentGate`, `Reputation`,
maupun `Achievement`. Keempat structural check juga semuanya tentang
QuestManager.

**Dampak.** Drift pada 3 dari 4 kontrak tidak memiliki penangkap otomatis
apa pun, bahkan bagi pengembang yang menjalankan vitest lokal setelah
`forge build`. Hari ini ketiga ABI tersebut deep-equal (0 drift), jadi
ini murni celah deteksi.

**Rekomendasi.** Perluas `abi-parity.test.ts` menjadi perulangan atas
keempat kontrak (satu deep-equal per kontrak). Perubahan kecil; bersama
PH7-M07 menutup seluruh celah paritas ABI yang di-commit.

### PH7-M09 — EVENT_SIGNATURES tulisan tangan tidak tercakup parity test

**Severity: Medium.** Sumber: findings/05-abi-parity.md (F3).

**Bukti.** `apps/web/lib/events.ts:17-27` mendefinisikan 5 string tanda
tangan event dengan tangan (`questCompleted`, `pointsAdded`, `badgeIssued`,
`badgeDefined`, `attestationUsed`), dipakai `useContractLogs` untuk
`getLogs` dan oleh `useTxHistory`/`useReputation` untuk leaderboard serta
riwayat transaksi. Tidak ada test — parity maupun unit — yang membandingkan
string ini dengan event di ABI hasil kompilasi maupun yang di-commit
(`events.test.ts` hanya mem-parse string itu sendiri, memvalidasi sintaks,
bukan kecocokan). Status saat ini: kelima string COCOK persis (termasuk
`AttestationUsed(address indexed account, uint256 indexed questId, uint256 nonce, address indexed signer)`).

**Dampak bila drift di masa depan — inilah yang membuatnya Medium.**
Kegagalan di sini bersifat diam-diam: `indexed` yang salah → `getLogs`
mengembalikan 0 log → leaderboard dan riwayat kosong tanpa error; nama
parameter salah → agregasi membaca `args.<nama>` yang `undefined` → poin
dihitung 0; tipe salah → decoding gagal atau nilai salah. Satu-satunya
penangkap adalah anvil integration (tidak berjalan di CI) dan wallet E2E
(hanya sebagian tampilan).

**Rekomendasi.** Turunkan string event dari ABI yang di-commit (helper
yang membangun tanda tangan kanonis dari entri event), atau tambahkan
test vitest yang membandingkan setiap string dengan tanda tangan kanonis —
pola yang sama dengan deep-equal, tanpa perlu `out/` bila dibandingkan
dengan ABI yang di-commit.

### PH7-M10 — Klaim "via-IR menghilangkan MCOPY" salah (false positive metadata)

**Severity: Medium** (integritas bukti/jejak audit; bukan kerentanan kode).
Sumber: findings/06-via-ir-bytecode.md (F1).

**Bukti.** Laporan Phase 6 (§3, §5.1) mengklaim baseline legacy memiliki
"1× MCOPY di Reputation + 1× di Achievement" dan via-IR menghilangkannya.
Reproduksi dengan `cast disassemble` atas `deployedBytecode` penuh (metode
Phase 5/6) pada build legacy memang menampilkan `MCOPY` di Reputation PC
`0x946` dan Achievement PC `0x1887` — tetapi kedua PC itu berada di dalam
sufiks metadata, bukan kode: Reputation total 2.404 byte, kode berakhir di
offset 2.351, PC `0x946` = 2.374 (23 byte di dalam metadata, di tengah
hash IPFS); Achievement kode berakhir 6.266, PC `0x1887` = 6.279.
Disassembly di sekitar PC itu memperlihatkan `PUSH5 0x6970667358` — harfiah
ASCII `"ipfs"` dari header CBOR. Bukti penguat: disassembly penuh
QuestManager via-IR tepat 7.748 baris — sama persis dengan angka laporan
Phase 6 — membuktikan Phase 6 mendisassembly bytecode penuh termasuk
metadata (bagian kode saja 7.728 instruksi). Disassembly yang benar
(bagian kode saja, melewati data PUSH) + cross-check `cast disassemble`:
**0 opcode Cancun-only di keempat kontrak pada KEDUA build**.

**Dampak.** Kesimpulan "kompatibilitas Cancun terpenuhi" tetap benar,
tetapi alasan yang dikutip salah; temuan Phase 5 F3 yang dinyatakan MOOT
karena via-IR sebenarnya tidak pernah valid sejak awal. Auditor eksternal
yang mengandalkan klaim ini akan menilai bukti Phase 6 tidak dapat
dipercaya.

**Rekomendasi.** (1) Perbaiki laporan Phase 6 (§3, §5.1) dan
`NEXT_PHASE_VALIDATION.md` dengan koreksi: 0 opcode Cancun-only di kedua
build; MCOPY baseline adalah false positive metadata. (2) Adopsi scanner
opcode yang memotong metadata CBOR sebelum disassembly (skrip audit
`~/workspace/.tmp/phase7-bytecode-audit.py` dapat dijadikan acuan) dan
jadikan bagian dari CI/regression battery. (3) Perbaiki angka opcode yang
salah dalam dokumen penugasan (MCOPY `0x27` → `0x5e`; TSTORE/TLOAD
tertukar — lihat PH7-I10).

## 5. Temuan Low

Setiap entri: lokasi, bukti, reproduksi, rekomendasi. Detail penuh ada di
laporan workstream yang dirujuk.

### PH7-L01 — Tidak ada batas total reputasi yang bisa diterbitkan satu creator

Sumber: 02/F2. Lokasi: `QuestManager.sol:133-196` (`createQuest`),
`QuestManager.sol:322-372` (`_completeQuest`). Batas hanya per quest
(`rewardPoints ≤ 10.000`); tidak ada batas jumlah quest per creator, batas
total poin per quest sepanjang hidupnya, dan quest Daily/Weekly bisa
diselesaikan berulang tanpa batas (`maxCompletions == 0`). Justifikasi AR-3
threat model ("capped at 10.000 pts/quest") hanya menutup per-quest, bukan
total. **Reproduksi (PoC):** 5 quest OneTime @ 10.000 poin + 1 quest harian
@ 10.000 poin → alice memegang **70.000 poin** dalam 2 hari simulasi.
**Rekomendasi:** verifikasi `QUEST_CREATOR` sebagai multisig di deploy
script/checklist; pertimbangkan `maxLifetimePoints` per quest atau
rate-limit pembuatan quest; perbaiki justifikasi AR-3.

### PH7-L02 — Pause di Reputation/Achievement membekukan completion QuestManager (kopling asimetris)

Sumber: 02/F3. Lokasi: `QuestManager.sol:364-370`, `Reputation.sol:56-60`,
`Achievement.sol:57-62`. Pause `Reputation` → SEMUA completion revert
(`EnforcedPause` dari `addPoints`). Pause `Achievement` → quest ber-badge
revert hanya untuk pengguna yang belum memegang badge (pengguna yang sudah
memegang badge tetap bisa menyelesaikan quest karena `issue()` dilewati).
Perilaku asimetris ini tidak didokumentasikan. **Reproduksi (PoC):** dua
test PoC membuktikan revert/sukses sesuai penjelasan di atas.
**Rekomendasi:** dokumentasikan kopling di `docs/SECURITY.md`/runbook pause;
pertimbangkan apakah `pause()` QuestManager saja sudah cukup sebagai tombol
darurat.

### PH7-L03 — Attestation yang ditandatangani SEBELUM grant role menjadi valid SETELAH grant (TOCTOU sisi grant)

Sumber: 02/F4. Lokasi: `QuestManager.sol:311-315`. Role dicek hanya pada
saat submit, bukan saat sign; digest tidak mengikat status role. Sisi
revoke didokumentasikan sebagai fitur; sisi kebalikannya tidak dibahas:
verifier yang dicabut lalu di-grant kembali bisa memiliki attestation "lama"
yang tiba-tiba valid (nonce publik dan dapat diprediksi; deadline ≤ 7 hari).
**Reproduksi (PoC):** tandatangani dengan kunci non-verifier → submit
revert `UnauthorizedVerifier`; grant role ke alamat yang sama → submit
signature lama yang sama berhasil. **Rekomendasi:** SOP — jangan re-grant
tanpa jeda melewati masa berlaku attestation terlama (7 hari); jangka
panjang, ikat attestation ke "era" verifier.

### PH7-L04 — Perilaku validator bisa berubah setelah di-approve

Sumber: 02/F5. Lokasi: `QuestManager.sol:378-398` (`approveValidator`
hanya cek `code.length != 0`), `QuestManager.sol:425-436` (`_validateOnChain`).
Approval bersifat per alamat instance. Bila validator yang di-approve adalah
proxy (UUPS/transparent) atau kontrak dengan state yang bisa diubah
pemiliknya, pengendali validator — bukan admin AGENTHUB — bisa mengubah
hasil `validate()` menjadi selalu `true` tanpa re-approval. Validator
referensi `TokenBalanceValidator` aman (field immutable). Terkait:
`_validateOnChain` memakai `staticcall` tanpa batas gas (DoS per quest
via gas). **Reproduksi (PoC):** validator mutable di-approve saat
`pass == false` → completion revert; pemilik membalik flag → completion
berhasil sementara `approvedValidators` tetap `true`. **Rekomendasi:** SOP
approval — hanya approve validator terverifikasi dan tidak upgradeable;
catat codehash saat approval + pengecekan berkala off-chain; pertimbangkan
stipend gas pada `staticcall`.

### PH7-L05 — Cek threshold setelah loop recovery: gas terbuang pada submission yang pasti gagal

Sumber: 02/F6 + 03/P7-05 (dua pengukuran independen). Lokasi:
`QuestManager.sol:261-269`. Loop recovery semua signature (ecrecover +
SLOAD role per signature) berjalan dulu; cek `provided < threshold` baru di
baris 269. **Reproduksi/pengukuran:** 1 signature untuk quest T3 vs array
kosong — terukur 16.222 gas terbuang (55.707 vs 39.485 gas, PoC 02) dan
3.234 gas pada urutan pengukuran lain (PoC 03; perbedaan metodologi
pengukuran, orde yang sama). Gas dibayar pemanggil sendiri; tidak dapat
dieksploitasi terhadap orang lain. **Rekomendasi:** pindahkan cek
`provided < threshold` ke segera setelah cek batas array/deadline, sebelum
digest dan loop. Perubahan satu baris, tanpa perubahan semantik.

### PH7-L06 — Nonce global per akun membuat attestation basi lintas quest

Sumber: 02/F7 + 03/P7-03. Lokasi: `QuestManager.sol:83`,
`QuestManager.sol:259-275`. Nonce `mapping(address => uint256)` global per
akun, bukan per quest. Pengguna yang sedang mengumpulkan M signature untuk
quest A kehilangan seluruh set bila menyelesaikan quest attested lain lebih
dulu. Bukan kerentanan keamanan (penyerang tidak bisa memajukan nonce
korban — dibuktikan PoC `testB7c`); sudah dicatat sebagai residual risk #3
Phase 6. **Reproduksi (PoC):** kumpulkan attestation quest T1 (nonce 0),
selesaikan quest T2 dulu → nonce 1 → attestation T1 revert.
**Rekomendasi:** pertimbangkan nonce per `(account, questId)` — replay
antar-quest tetap dicegah karena `questId` sudah ada di digest; atau
tambahkan peringatan UI bila pengguna menyelesaikan quest attested lain
selagi satu set attestation belum di-submit.

### PH7-L07 — Deactivate + recreate menurunkan threshold secara efektif dan memungkinkan klaim ganda

Sumber: 03/P7-02. Lokasi: `QuestManager.sol:178-179` (questId baru),
`QuestManager.sol:78-80` (penyelesaian per `(account, questId)`),
`QuestManager.sol:439-447` (`deactivateQuest`). Creator/admin menonaktifkan
quest T2 lalu membuat ulang quest yang sama di T1; pengguna yang sudah
menyelesaikan quest lama dapat menyelesaikan quest baru. Transparan
on-chain (event + questId baru) dan butuh pihak tepercaya — tetapi ini
adalah jalur pemulihan yang direkomendasikan untuk PH7-M01, sehingga
keduanya berinteraksi. **Reproduksi (PoC `testA2`):** Alice menyelesaikan
T2 (100 poin) → deactivate + recreate T1 → Alice menyelesaikan lagi →
saldo **200 poin**. **Rekomendasi:** SOP — recreate hanya bila quest lama
belum pernah diselesaikan siapa pun; opsi desain: field `supersedesQuestId`

- tolak completion oleh akun yang sudah menyelesaikan quest yang
  digantikan, atau event `QuestRecreated(oldQuestId, newQuestId)`.

### PH7-L08 — Threshold disimpan tapi tidak ditegakkan untuk quest non-Attested

Sumber: 03/P7-04. Lokasi: `QuestManager.sol:156-158` (validasi 1–3 untuk
semua kind), `QuestManager.sol:226` (hanya completion Attested yang
membaca nilai tersimpan). **Reproduksi (PoC `testA3`):** quest CheckIn
threshold 3 diselesaikan via `completeQuest` tanpa signature — berhasil,
100 poin. **Dampak:** nilai menyesatkan bagi integrator/indexer yang
membaca `getQuest`. **Rekomendasi:** di `createQuest`, bila
`validationKind != Attested`, simpan threshold 1 (atau tolak nilai ≠ 1);
minimal, dokumentasikan di `IQuestManager.Quest` dan dokumentasi API.

### PH7-L09 — Tidak ada penegakan frontend: tidak ada UI pembuatan quest sama sekali

Sumber: 04/P-03. Bukti: grep `createQuest` di `apps/web` (di luar ABI)
hanya mengenai test/komentar; tidak ada `CreateQuestForm`/`useCreateQuest`.
Pembuatan quest praktis lewat skrip/`cast` tanpa pemeriksaan kebijakan apa
pun. **Dampak:** tidak ada lapisan pertahanan di sisi manusia — tanpa
peringatan "reward > 1.000 butuh threshold 2", tanpa default yang aman.
**Rekomendasi:** bila UI pembuatan quest dibangun, hitung threshold minimum
dari `rewardPoints` + kategori badge sebagai nilai minimum/default; sampai
saat itu, tambahkan pemeriksaan kebijakan fail-closed pada skrip pembuatan
quest tim.

### PH7-L10 — Tidak ada test yang meng-assert kebijakan threshold

Sumber: 04/P-04. Bukti: `ThresholdAttestation.t.sol` (32 test) menguji
rentang (0 dan 4 revert) dan completion — tidak satu pun membuat quest
`rewardPoints > 1.000` dan meng-assert perilaku threshold; helper
`_createAttested` memakai reward 100 di semua kasus. **Rekomendasi:**
tambahkan test kebijakan (tabel kasus reward/badge/threshold) dan jadikan
bagian gate CI.

### PH7-L11 — anvil-integration.mjs membaca ABI dari `out/`, bukan dari `lib/abis/`

Sumber: 05/F4. Lokasi: `apps/web/scripts/anvil-integration.mjs:20-26`
(`abiOf` membaca `packages/contracts/out/`). Ke-30 check anvil memakai ABI
segar dari build, bukan ABI frontend yang di-commit — drift pada
`lib/abis/*.ts` tidak akan membuat satu pun check gagal, meskipun header
file mengklaim menguji "the EXACT RPC patterns the frontend hooks use".
**Rekomendasi:** ubah `abiOf()` agar mengimpor dari `lib/abis/*.ts`, atau
tambahkan assert kesetaraan ABI `out/` vs yang di-commit di awal skrip.

### PH7-L12 — ABI minimal inline + konstanta EIP-712 tulisan tangan tanpa pin otomatis

Sumber: 05/F5. Lokasi: `wallet-e2e.mjs:211-231,269-277`,
`sign-attestation.mjs:65-90` (ABI inline); konstanta EIP-712 tersebar di
6 tempat (`lib/attestation.ts`, `sign-attestation.mjs`,
`anvil-integration.mjs`, `wallet-e2e.mjs`, `anvil-integration.test.ts`).
Status saat ini: semua cocok, kecuali 2 perbedaan nama parameter kosmetik
(`nonces` input `account` vs `""`; output `points` `""` vs `total`) yang
tidak berpengaruh ke encoding viem. **Dampak:** drift di masa depan
membutuhkan perubahan manual di 6 tempat; kegagalan mengubah salah satunya
membuat signature tidak valid (gagal terlihat, bukan diam-diam).
**Rekomendasi:** sentralisasi konstanta di `lib/attestation.ts` sebagai
satu-satunya sumber; impor ABI inline dari `lib/abis/*.ts`.

### PH7-L13 — solc 0.8.24 + via-IR terpapar bug compiler yang diketahui

Sumber: 06/F2. Bukti (daftar bug resmi Solidity): `UnsoundSpillInMutualRecursion`
(medium, fixed 0.8.36) dan `SpillSlotCollisionAcrossMutualRecursion`
(low/medium, fixed 0.8.37) **tidak berlaku** (tidak ada rekursi di kode);
"TSTORE Poison" **tidak berlaku** (0 kemunculan `transient`/`delete`);
tetapi `YulOptimizerKnowledgeBaseStaleBookkeeping` (low, fixed 0.8.38)
**tidak dapat disingkirkan secara statis** — "any code may be affected".
Mitigasi empiris: 287 test + fuzz 10k + E2E hijau pada build via-IR ini.
**Rekomendasi:** sebelum deploy mainnet, evaluasi upgrade solc ke ≥ 0.8.38
dengan re-regressi penuh (upgrade solc mengubah seluruh bytecode lagi);
tetap pin `solc_version`; catat daftar bug solc yang diperiksa di checklist
deploy.

### PH7-L14 — Tidak ada `[rpc_endpoints]` di foundry.toml

Sumber: 08/L-01. `BSC_TESTNET_RPC_URL` di `.env.example` tidak dibaca
forge — operator harus menempel URL mentah di `--fork-url`/`--rpc-url`.
Risiko salah URL dimitigasi sebagian allowlist chain (hanya 56/97/31337).
**Rekomendasi:** tambahkan `[rpc_endpoints]` (`bsc-testnet`,
`bsc`) dan ubah perintah dokumen menjadi `--fork-url bsc-testnet`.

### PH7-L15 — `.env.example` tidak lengkap dan instruksinya salah untuk forge

Sumber: 08/L-02. Variabel yang dibaca script tetapi tidak ada di
`.env.example`: `AGENT_ID_ADDRESS`, `SAFE_SINGLETON`,
`SAFE_PROXY_CODEHASH`, `CONFIRM_MAINNET_DEPLOY`. Header menyuruh "Copy to
.env.local" — **dibuktikan empiris tidak berfungsi untuk forge** (forge
hanya memuat `.env`, bukan `.env.local`; file dummy sudah dihapus setelah
pengujian). **Rekomendasi:** lengkapi keempat variabel; perbaiki instruksi
(variabel forge di shell atau `packages/contracts/.env`); pertimbangkan
`packages/contracts/.env.example` terpisah.

### PH7-L16 — Dokumen menyebut "11 wiring CALLs", padahal dengan VERIFIER menjadi 12

Sumber: 08/L-03. Checklist §4.1 dan `DEPLOYMENT_PLAN.md` menulis 11;
hitungan sebenarnya 8 `grantRole` + 3 `renounceRole` = 11 tanpa verifier,
12 dengan verifier (18 transaksi). Dibuktikan artefak fork: 17 tx tanpa
verifier, 18 tx dengan verifier. **Dampak:** operator yang men-deploy
dengan verifier dan mengikuti checklist akan melihat ketidakcocokan —
paling buruk, operator belajar mengabaikan ketidakcocokan hitungan.
**Rekomendasi:** ubah dokumen menjadi "11 wiring CALLs (12 bila `VERIFIER`
di-set; 17 transaksi total, 18 dengan verifier)".

### PH7-L17 — `_verifyWiring` tidak memeriksa CANCELLER_ROLE

Sumber: 08/L-04. `ROLE_MATRIX.md` dan `DEPLOYMENT_PLAN.md` mencantumkan
Timelock `CANCELLER_ROLE` = admin multisig, tetapi `_verifyWiring`
(`DeployAgentHub.s.sol:259-272`) tidak memeriksanya. Keadaan on-chain
sebenarnya benar (konstruktor OZ memberikan `CANCELLER_ROLE` kepada setiap
proposer) — yang hilang hanya asersinya. **Rekomendasi:** tambahkan
pemeriksaan `timelock.hasRole(timelock.CANCELLER_ROLE(), params.adminMultisig)`
dan perbarui hitungan "29 checks" menjadi 30.

### PH7-L18 — DeployAgentHub tidak menulis artefak deployment (hanya console.log)

Sumber: 08/L-05. `DeployAgentHub.s.sol:129-134` hanya `console.log` enam
alamat; tidak ada `vm.writeJson` (grep → 0), padahal pola `_writeJson`
sudah ada di `DeployLocalTestStack.s.sol`. `foundry.toml:10` membatasi
`fs_permissions` hanya ke `./.anvil-deployment.json`. Akibatnya pencatatan
alamat + tx hash sepenuhnya manual (6 alamat + nomor blok disalin dengan
tangan); `docs/DEPLOYMENT_RECORD.md` belum ada. **Rekomendasi:** tambahkan
penulisan JSON deployment, perluas `fs_permissions` ke path itu, buat
kerangka `DEPLOYMENT_RECORD.md` sebelum deployment-day.

### PH7-L19 — Tidak ada helper untuk proposal timelock pasca-deploy

Sumber: 08/L-06. Langkah pasca-deploy (`DEPLOYMENT_PLAN.md` §6: approve
validator, definisi badge, grant verifier tambahan via timelock) tidak ada
di script; operator harus merakit calldata manual (via `cast`/UI Safe)
termasuk hash role yang benar. Relevan untuk R-010: syarat "≥ 3 verifier
sebelum quest threshold-2 pertama di mainnet" bergantung pada grant manual
ini. **Rekomendasi:** sediakan script `ProposeGrantRole.s.sol` (dry-run +
ringkasan yang dapat dibaca manusia) atau dokumentasikan perintah `cast`
persis di checklist §5.

### PH7-L20 — Artefak broadcast chain 97 yang basi terlihat seperti deployment nyata

Sumber: 08/L-07. `packages/contracts/broadcast/DeployAgentHub.s.sol/97/`
berisi dua run dengan 18 transaksi DENGAN receipts (status `0x1`) — format
artefak `--broadcast` yang sekilas terlihat seperti dua deployment testnet,
bertentangan dengan status "NOT DEPLOYED". **Verifikasi live (dua RPC):**
`eth_getTransactionReceipt` → `null`; `eth_getCode` alamat MockAgentId
tercatat → `0x`. Artefak berasal dari broadcast ke fork anvil lokal
(chainId 97), bukan testnet live. `broadcast/` sudah di-gitignore.
**Rekomendasi:** hapus `run-*.json` chain 97 (kecuali subfolder `dry-run/`)
atau pindahkan ke folder log dengan README "artefak fork lokal, BUKAN
deployment live".

### PH7-L21 — `AGENT_ID_ADDRESS` yang di-supply di chain 97 tidak divalidasi

Sumber: 08/L-08. Bila `AGENT_ID_ADDRESS` di-set di chain 97,
`DeployAgentHub.s.sol:184` memakainya apa adanya; satu-satunya validasi
adalah `code.length == 0` di konstruktor `AgentGate.sol:39`. Kontrak jahat
yang mengembalikan 1 untuk semua alamat dari `balanceOf` akan membuat
semua orang lolos gate. Jalur default (variabel kosong → mock baru) aman.
**Rekomendasi:** validasi minimal — cek codehash cocok bytecode MockAgentId,
atau cek `supportsInterface(0x80ac58cd)` + panggilan `balanceOf` uji; atau
dokumentasikan tegas bahwa variabel ini HARUS kosong di testnet.

### PH7-L22 — Verifikasi BscScan manual kekurangan constructor args per kontrak

Sumber: 08/L-09. Jalur otomatis sudah benar (`foundry.toml:43-45`,
`--verifier etherscan` + `--chain 97`). Jalur manual kurang: tidak ada
daftar constructor args per kontrak di dokumen mana pun (AgentGate,
TimelockController, Reputation, Achievement, QuestManager, MockAgentId).
Catatan via-IR: verifikasi mengulang kompilasi dari metadata — settings
harus identik (via-IR, solc 0.8.24, optimizer 200, evm cancun); verifikasi
manual dari checkout lain dengan `foundry.toml` berbeda gagal dengan
"bytecode mismatch". **Rekomendasi:** tambahkan tabel constructor args +
perintah `forge verify-contract` lengkap per kontrak, dan peringatan bahwa
verifikasi harus dari checkout yang sama.

### PH7-L23 — Daftar 8 input lengkap, tetapi ada 3 prasyarat operasional tersembunyi

Sumber: 08/L-10. Pemetaan `DeployAgentHub.run()` ke 8 input checklist §1:
lengkap, **tidak ada input ke-9 berupa rahasia**. Namun 3 prasyarat tidak
tercantum: (1) URL RPC testnet yang berfungsi (default dokumentasi pernah
403 dari VM build); (2) Safe testnet harus SUDAH DIBUAT sebelum deploy
(proksi + setup owner/threshold + pendanaan tBNB); (3) dompet uji + tBNB
untuk smoke test (checklist §5.1 butuh 2 dompet uji didanai).
**Rekomendasi:** tambahkan §1.x "Prasyarat operasional (bukan rahasia)" ke
checklist.

### PH7-L24 — Tiga warning lint forge BARU dari kode Phase 6

Sumber: 01/S-01. `regression-forge-build.log` memuat 3×
`warning[require-revert-in-loop]` dari kode baru Phase 6
(`QuestManager.sol`:265, 313, 315); laporan §5.4 menyebut warning build
"pre-existing" — tidak benar untuk ketiganya. Dampak keamanan: tidak ada
(revert fail-fast by design, loop M ≤ 5). **Rekomendasi:** koreksi laporan
dengan errata (lihat §9).

### PH7-L25 — Rincian Slither app-only salah hitung satu

Sumber: 01/S-02 + 07/§2.11. Laporan Phase 6 menulis "4 Low + 7 Info" (11);
bukti menunjukkan **4 Low + 8 Info = 12**. Penyebab teridentifikasi oleh
test battery: detektor `pragma` (Info) terbuang saat Phase 6 memfilter JSON
lengkap ke subset app-only, tetapi run gate `--exclude-dependencies` tetap
melaporkannya. Himpunan temuan identik; gate 0 High/Medium tidak berubah.
**Rekomendasi:** koreksi laporan dengan errata (lihat §9).

### PH7-L26 — `environment-read-across-mutation`: 8 instansi, nol dari EconomicAttack

Sumber: 01/S-03. Laporan §5.4 menyebut "one `environment-read-across-mutation`
help from the restructured `EconomicAttack` test". Faktanya build log memuat
8 instansi dan tidak satu pun di `EconomicAttack.t.sol` (3 di
`Attestation.t.sol`, 3 di `QuestManager.t.sol`, 1 di `Integration.t.sol`,
1 di `ValidatorRegistry.t.sol`). Semua di kode test — bukan masalah
produksi. **Rekomendasi:** koreksi laporan dengan errata (lihat §9).

### PH7-L27 — Angka gas headline tidak ada di log regresi yang di-commit — DITUTUP dalam review ini

Sumber: 01/S-04. Angka 242.735 / 253.867 / 265.221 (pengukuran `gasleft()`)
tidak muncul di `regression-forge-test.log` karena forge test dijalankan
tanpa `-vv`. **Status: DITUTUP.** Koordinator Phase 7 mengukur ulang
langsung: `forge test --match-test testGas -vv` (log
`agenthub-phase7-review/logs/16-gas-remeasure.log`) menghasilkan
**242.735 / 253.867 / 265.221** persis, dengan cross-check
242.735 / 253.868 / 265.229 (selisih ≤ 8 gas, sesuai dokumen gas).
**Rekomendasi:** tidak ada tindakan lanjut; log pengukuran ulang ini
menjadi bukti permanen.

### PH7-L28 — Klaim durasi build 303 detik tanpa bukti di log

Sumber: 01/S-05. Laporan §5.1 menyatakan build via-IR "303s measured in
the clean copy"; `regression-forge-build.log` tidak memuat baris waktu.
Pengukuran Phase 7: build via-IR bersih 5 mnt 13 dtk CPU (konsisten dengan
303 dtk); wall 12 mnt 27 dtk di bawah beban paralel. **Rekomendasi:**
catat durasi build pada run berikutnya untuk memvalidasi klaim dan margin
timeout CI.

### PH7-L29 — Provenance `slither-phase6.json` mendahului run regresi clean-copy

Sumber: 01/S-06. `regression-slither.log` mencatat "slither-phase6.json
exists already, the overwrite is prevented" — JSON di-commit berasal dari
run implementer sebelum baterai regresi clean-copy. Jumlah 44 temuan
diverifikasi ulang di clean copy, sehingga isinya konsisten — tetapi byte
JSON-nya bukan artefak run tersebut. **Rekomendasi:** regenerasi JSON di
clean copy pada fase berikutnya agar jejak bukti sepenuhnya teraudit.

### PH7-L30 — Log OSV menyebut path output lama

Sumber: 01/S-07. `regression-osv.log` menyatakan output ditulis ke
`agenthub-final-pretestnet/logs/phase4-osv-audit.json` — path hardcoded
usang. JSON Phase 6 yang sebenarnya berada di
`agenthub-phase6-threshold/test-results/osv-audit-phase6.json`.
**Rekomendasi:** perbaiki path output hardcoded di script OSV.

### PH7-L31 — Log duplikat usang tidak di-refresh

Sumber: 01/S-09. `apps/agenthub-final-pretestnet/logs/phase7-anvil-integration.log`
(167 byte, run gagal karena path salah) adalah salinan usang yang tidak
ikut di-refresh Phase 6; dua file log bernama sama di dua lokasi, salah
satunya hasil run gagal. **Rekomendasi:** hapus atau arsipkan log duplikat
usang.

## 6. Temuan Informational

### PH7-I01 — Frontend menerima signature high-s dan v ∈ {0,1} yang ditolak kontrak

Sumber: 02/I1. Lokasi: `apps/web/lib/attestation.ts:96-133`. viem
`recoverPublicKey` (@noble/curves) hanya memvalidasi `s ∈ [1, N-1]` tanpa
penegakan low-s dan menerima `v ∈ {0, 1, 27, 28}` — signature malleated
dilaporkan frontend sebagai "valid" tetapi transaksi submit revert on-chain
dengan `InvalidAttestationSignature`. Kontrak fail-closed; murni masalah
UX. **Rekomendasi:** tolak di `checkAttestation` bila `s > n/2` dan bila
`v ∉ {27, 28}`, dengan pesan error yang menjelaskan penolakan kontrak.

### PH7-I02 — Komentar NatSpec yang menyesatkan tentang replay attestation

Sumber: 02/I2. Lokasi: `QuestManager.sol:270-273`. "Recovers a different
signer" menyiratkan hasil recovery deterministik; faktanya me-recover
signature lama terhadap digest baru menghasilkan alamat praktis acak yang
gagal di cek role. Perilaku kode benar; hanya komentarnya imprecise.
**Rekomendasi:** ubah komentar menjadi "…so recovery against the new digest
yields an unrelated address that fails the VERIFIER_ROLE check."

### PH7-I03 — `deactivateQuest` bersifat permanen — tidak ada cara reaktivasi

Sumber: 02/I3. Lokasi: `QuestManager.sol:439-449`. Tidak ada
`reactivateQuest`; kesalahan deaktivasi hanya bisa diperbaiki dengan quest
baru (ID baru, riwayat hilang, attestation hangus). Event
`QuestDeactivated` juga tidak mencatat siapa yang menonaktifkan.
**Rekomendasi:** pertimbangkan `reactivateQuest` (admin only) atau tambahkan
aktor ke event.

### PH7-I04 — Event `QuestCreated` tidak memuat threshold, badgeId, jendela waktu, dan maxCompletions

Sumber: 02/I4 + 03/P7-06. Lokasi: `IQuestManager.sol:140-146`,
`QuestManager.sol:195`. Indexer/monitoring off-chain harus memanggil
`getQuest` per quest untuk mendapatkan `attestationThreshold` dan field
lainnya. Bukan masalah keamanan — threshold tidak pernah berubah setelah
creation. **Rekomendasi:** tambahkan field ke event (perubahan ABI —
lakukan sebelum mainnet bila dianggap perlu); bila tidak, dokumentasikan
bahwa indexer wajib membaca `getQuest`.

### PH7-I05 — Temuan Slither app-only (4 Low + 8 Info) sudah ditelaah — semuanya false positive / by-design

Sumber: 02/I5 + 07/§2.11. Keempat Low adalah `timestamp` (perbandingan
`block.timestamp` untuk jendela berskala hari/menit — produsen blok BSC
hanya bisa menggeser timestamp dalam hitungan detik). Kedelapan Info:
`assembly` ×3, `low-level-calls` ×3, `pragma` ×1, `cyclomatic-complexity`
×1 — semuanya pola yang disengaja atau tidak material. **Tidak ada
tindakan yang diperlukan**; dicatat agar penelaahan ini terdokumentasi.

### PH7-I06 — Replay pada fork dengan `chainId` yang sama secara teori dimungkinkan (accepted risk)

Sumber: 03/P7-07. Domain separator mengikat `chainId` + alamat kontrak;
`AgentGate` menolak `chainId` berbeda. Kedua pengikat gagal bersamaan hanya
pada fork state yang mempertahankan `chainId` yang sama DAN alamat kontrak
yang sama — attestation bisa dipakai di kedua chain. Dampak terbatas pada
poin reputasi di chain fork. Keterbatasan standar EIP-712, bukan bug
AGENTHUB. **Rekomendasi:** catat sebagai risiko yang diterima di
`SECURITY_THREAT_MODEL.md`. Replay antar-chain dengan chainId berbeda
(56 vs 97) terbukti mustahil (PoC `testB1a`/`testB1c`).

### PH7-I07 — Kebijakan hanya bermakna untuk quest Attested

Sumber: 04/P-06. Quest CheckIn 10.000 poin (self-service, tanpa bukti)
atau OnChain 10.000 poin dengan validator longgar dapat dibuat secara sah —
kebijakan threshold tidak berlaku bagi mereka, dan tidak ada kebijakan
pengganti. SOP §6.1 sendiri membatasi kebijakan pada "any attested quest",
jadi konsisten dengan rumusan yang ada. **Rekomendasi:** putuskan dan
dokumentasikan eksplisit apakah quest CheckIn boleh membawa reward besar;
bila tidak, tambahkan batas reward per kind di `createQuest` atau SOP.

### PH7-I08 — AGENT_ID_ABI tidak dapat diverifikasi dari repo

Sumber: 05/F6. Lokasi: `apps/web/lib/contracts.ts:18-26`. ABI minimal
`balanceOf(address)` untuk kontrak Agent ID eksternal; alamat dari env,
tidak ada artefak build-nya. Bentuknya tanda tangan standar ERC-721 dan
pemakaian terbatas pada fallback di `useAgentId` (hanya bila `agentGate`
belum di-deploy). **Rekomendasi:** dokumentasikan alamat Agent ID yang
diharapkan untuk BSC testnet/mainnet di `docs/DEPLOYMENT.md`.

### PH7-I09 — Generator ABI deterministik, tetapi tanpa mode `--check` dan tanpa pin solc

Sumber: 05/F7. Lokasi: `packages/contracts/script/export-abis.mjs`.
Deterministik (keempat file byte-identik dengan regenerasi dari build
segar — membuktikan tidak ada edit manual). Tetapi skrip membaca artefak
`out/` apa pun tanpa memeriksa versi solc/pengaturan build, dan tidak ada
cara menjalankannya sebagai pemeriksaan CI tanpa menimpa file.
**Rekomendasi:** tambahkan `node export-abis.mjs --check` + assert versi
solc dari metadata artefak; jalankan `--check` di CI setelah `forge build`.

### PH7-I10 — Angka opcode Cancun-only dalam dokumen penugasan audit salah

Sumber: 06/F3. Brief audit menyebut "MCOPY `0x27`, TSTORE `0x5c`, TLOAD
`0x5d`". Nomor kanonik: MCOPY **`0x5e`** (EIP-5656), TLOAD **`0x5c`**,
TSTORE **`0x5d`** (EIP-1153), BLOBHASH `0x49`, BLOBBASEFEE `0x4a` —
dikonfirmasi EIP dan `cast disassemble` (`0x27` = `UNKNOWN`, nomor draf
awal yang tidak pernah diadopsi). **Rekomendasi:** perbaiki angka dalam
templat penugasan Phase 7.

### PH7-I11 — Waktu build legacy 2 mnt 4 dtk, bukan ~8 dtk

Sumber: 06/F4. Build legacy bersih: 2 mnt 4 dtk wall / 32 dtk CPU — bukan
~8 dtk seperti klaim "pengukuran implementer" di laporan Phase 6 §5.1
(angka 8 dtk kemungkinan build inkremental). Rasio via-IR/legacy ≈ 10×
CPU, bukan ≈ 40×. **Rekomendasi:** koreksi angka 8 dtk di laporan Phase 6;
jangan menjalankan build via-IR bersih paralel di mesin kecil.

### PH7-I12 — QuestManager memakai 49,93% batas EIP-170 — aman, pantau pertumbuhannya

Sumber: 06/F5. QuestManager via-IR 12.272 byte (headroom 12.304 byte);
tumbuh +425 byte (+3,59%) dari legacy. **Rekomendasi:** tambahkan
pemeriksaan ukuran bytecode ke CI (gagal bila > 80% batas).

### PH7-I13 — ProbeSafeProxy.s.sol tanpa chain guard (tidak berbahaya)

Sumber: 08/I-01. `ProbeSafeProxy.s.sol:41-55` memanggil
`createProxyWithNonce` di kedua factory kanonis tanpa `startBroadcast` dan
tanpa pemeriksaan chain (komentar header: fork-only). Bila dijalankan
dengan `--broadcast` ke testnet, ia membuat 2 proxy Safe nyata dengan
owner yang tidak dikendalikan siapa pun — menghabiskan gas, tanpa dampak
keamanan. **Rekomendasi:** tambahkan catatan "fork-only" yang lebih tegas
atau `require` chain — prioritas rendah.

### PH7-I14 — Broadcast forge tidak atomik terhadap perubahan state

Sumber: 08/I-02. `forge script --broadcast` mensimulasikan seluruh script
dulu, lalu menyiarkan transaksi satu per satu. Bila state berubah di antara
simulasi dan broadcast, deployment dapat berhenti di tengah jalan dengan
sebagian kontrak sudah ter-deploy. Dokumen sudah mengakui obatnya
(redeploy — checklist §6). **Rekomendasi:** tidak ada tindakan selain
kesadaran operator: jangan ubah state Safe/chain selama jendela broadcast.

### PH7-I15 — Urutan deploy di script sudah benar; urutan singkat di tugas ini tidak mungkin

Sumber: 08/I-03. Urutan script — MockAgentId → AgentGate → TimelockController
→ Reputation → Achievement → QuestManager — adalah satu-satunya urutan yang
memenuhi dependensi konstruktor (QuestManager membutuhkan alamat Gate +
Reputation + Achievement). Role di-grant setelah semua CREATE. Tidak ada
langkah yang hilang atau berurutan salah.

### PH7-I16 — Kunci yang di-hardcode di DeployLocalTestStack adalah kunci uji publik, bukan kebocoran

Sumber: 08/I-04. Kunci di `DeployLocalTestStack.s.sol:36,40-44` adalah
kunci uji publik yang didokumentasikan dan sudah masuk allowlist gitleaks.
Tidak ada kunci privat asli di repo — `DeployAgentHub.s.sol:123` membaca
`DEPLOYER_PRIVATE_KEY` dari env tanpa nilai default. Risiko sebenarnya
dari kunci-kunci ini adalah PH7-M06 (tidak adanya chain guard), bukan
keberadaannya.

### PH7-I17 — Reflow format Prettier di `anvil-integration.mjs`

Sumber: 01/S-08. Beberapa baris panjang di-wrap ulang tanpa perubahan
semantik. Tidak disebut di laporan; trivial dan terverifikasi tidak
mengubah logika cek.

## 7. Area yang terverifikasi BENAR

Review ini tidak hanya mencari yang salah — berikut area yang diverifikasi
benar dengan bukti independen (bukan dari klaim laporan Phase 6):

1. **Kriptografi threshold (02 + 03, 39 PoC).** Recovery ECDSA via
   `tryRecover` (menolak high-s, signature 64-byte, v tidak valid);
   digest EIP-712 field-by-field cocok dengan frontend (domain
   `"AGENTHUB QuestManager"`, `"1"`, chainId di-bind, separator dihitung
   ulang bila chainId berubah); nonce dikonsumsi tepat sekali setelah
   semua signature terverifikasi dan sebelum `_completeQuest` — completion
   gagal tidak membakar nonce; deadline inklusif di kedua ujung
   (`== block.timestamp` valid, `== now + 7 hari` valid); duplikat
   dideteksi via alamat hasil recovery (tidak ada celah encoding);
   `VERIFIER_ROLE` dicek untuk SETIAP signer; junk di mana pun dalam
   array menggagalkan seluruh tx (fail-closed).
2. **Immutability threshold (03).** Satu-satunya jalur tulis
   `QuestManager.sol:194` (createQuest); tidak ada setter; tidak ada
   proxy/UUPS/`delegatecall` di kontrak aplikasi (deploy polos `new`);
   `deactivateQuest` hanya mengubah `active` (dibuktikan PoC `testA1`).
3. **Matriks serangan (03).** 25 vektor dinilai; tidak satu pun
   exploitable oleh penyerang eksternal. Batas array > 5 ditegakkan
   sebelum loop (revert 6 signature hanya 58.638 gas); loop O(M²) dengan
   M ≤ 5 (maks 10 perbandingan); reentrancy tertutup (`nonReentrant` +
   `_mint` bukan `_safeMint` + validator via `STATICCALL`); `createQuest`
   role-gated terhadap spam; front-run bakar nonce mustahil (digest
   mengikat `msg.sender`).
4. **Diff Phase 6 sesuai klaim (01).** 62 file, +12.081/−428, 11 commit;
   klaim "43 file, +2.532/−385" untuk 129439a..53849d9 terverifikasi
   PERSIS; 32 test Foundry + 23 test frontend baru dihitung manual;
   tidak ada test yang dihapus, tidak ada assertion yang dilemahkan;
   manifest 61/61 file tercatat, 0 hash mismatch; tidak ada perubahan
   CI/package.json/lockfile/deploy script.
5. **Paritas ABI 0 drift (05).** 201 entri di 4 kontrak identik
   field-per-field dengan compiled ABI; keempat file byte-identik dengan
   output `export-abis.mjs`; 5 string `EVENT_SIGNATURES` cocok persis;
   kontrol positif terhadap baseline 129439a membuktikan metode audit
   mendeteksi drift bila ada; vitest parity 5/5 lulus dengan `out/`
   tersedia.
6. **Bytecode aman (06).** 0 opcode Cancun-only di kode keempat kontrak
   (kedua build, disassembly bagian kode saja + cross-check `cast
disassemble`); ukuran runtime < 50% batas EIP-170; creation < 29%
   batas initcode EIP-3860; metadata CBOR konsisten (51 byte, solc
   0.8.24); tidak ada library linking; `foundry.toml` sehat (solc
   ter-pin, `evm_version="cancun"`, optimizer 200, `via_ir=true`
   terdokumentasi dengan alasan dan bukti biseksi).
7. **Alamat Agent ID di testnet — tidak ada masalah (08).** Alamat resmi
   hanya dikunci untuk chain 56 (`AgentGate.sol:55-56`); di chain 97
   script men-deploy `MockAgentId` bila `AGENT_ID_ADDRESS` kosong;
   verifikasi live ke dua RPC testnet: alamat resmi tidak punya kode di
   chain 97 (`eth_getCode` → `0x`), jadi jalur mock memang wajib dan
   sudah benar.
8. **Validasi Safe kuat (08).** `SafeValidation.sol` memeriksa kode,
   threshold ∈ [2, owner], owner ≥ 2, singleton kanonis v1.3.0/v1.4.1,
   codehash proxy kanonis, `VERSION()`; keempat alamat kanonis
   terverifikasi punya kode di chain 97 dan `VERSION()` v1.4.1
   mengembalikan `"1.4.1"`; dry-run fork membuktikan fail-closed
   (multisig EOA → revert `NotASafe` sebelum satu pun CREATE).
9. **Deployment script (08).** Urutan deploy benar secara dependensi;
   timelock 2 hari + self-admin benar; semua grant setelah semua CREATE;
   admin → timelock + deployer renounce + 29 cek `_verifyWiring`;
   tidak ada hardcoded key asli; pemetaan BscScan benar; cakupan
   `DeployScript.t.sol` (21 test) baik; klaim "NOT DEPLOYED" benar
   (artefak broadcast chain 97 terverifikasi sebagai fork lokal).
10. **Kontrol yang sudah benar di kebijakan (04).** Cap
    `MAX_REWARD_POINTS = 10.000`, rentang threshold 1–3, imutabilitas
    threshold, penegakan threshold saat completion, role-gating, rem
    darurat — semuanya terverifikasi on-chain. Semua `LAUNCH_QUESTS`
    mematuhi kebijakan (10–75 poin, threshold 1).

## 8. Test battery — angka final terverifikasi ulang

Dijalankan 20 November 2026, 05.00–05.25 WIB, HEAD `5723ff3`, secara
berurutan di repo utama. Log lengkap di `agenthub-phase7-review/logs/`
(01–16). **Semua angka klaim Phase 6 TERVERIFIKASI — tidak ada satu pun
test gagal di suite mana pun, dan tidak ada suite yang tidak terverifikasi.**

| Suite                                     | Klaim Phase 6                   | Hasil Phase 7                                                                                                                                                                             |
| ----------------------------------------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `forge build` (via-IR)                    | exit 0                          | **exit 0** (build bersih terputus restart runtime ~9 mnt, dilanjutkan inkremental: solc 660,86 dtk untuk 37 file sisa)                                                                    |
| `forge test`                              | 287/287 (20 suite)              | **287 lulus, 0 gagal, 0 skip** (20 suite, 77,88 dtk)                                                                                                                                      |
| Fuzz 10.000 runs, seed 42                 | 287/287                         | **287 lulus, 0 gagal, 0 skip** (perintah persis CI)                                                                                                                                       |
| Vitest web                                | 159 + 5 skip                    | **159 lulus + 5 skip (164)**                                                                                                                                                              |
| Vitest shared                             | 8/8                             | **8/8**                                                                                                                                                                                   |
| Typecheck + lint (web + shared)           | exit 0                          | **semua exit 0**                                                                                                                                                                          |
| Production build Next.js                  | exit 0, 8 route + `_not-found`  | **exit 0, 8 route + `_not-found`, semua statis**                                                                                                                                          |
| E2E smoke                                 | 23/23                           | **23/23**, 0 console error                                                                                                                                                                |
| Wallet E2E                                | 26/26                           | **26/26**, 0 console error (threshold-2 end-to-end, poin bob 150)                                                                                                                         |
| Anvil integration                         | 30/30 + 5/5                     | **30/30 cek node + 5/5 vitest**                                                                                                                                                           |
| Slither app-only                          | exit 0, 12 hasil, 0 High/Medium | **exit 0; 12 hasil: 0 High, 0 Medium, 4 Low, 8 Info**                                                                                                                                     |
| OSV audit                                 | 7 (0C/0H/6M/1L)                 | **7 (6 Moderate, 1 Low), 0 High/Critical**; set identik persis dengan Phase 6 (960 paket)                                                                                                 |
| Gitleaks full history                     | 0 leak (97 commit)              | **0 leak (100 commit)**                                                                                                                                                                   |
| `forge fmt` + Prettier                    | exit 0                          | `forge fmt` exit 0; Prettier exit 1 — 9 file, **semuanya artefak review Phase 7, nol di source** (sudah diformat ulang dengan `prettier --write` setelah laporan ini selesai — lihat §13) |
| Gas completion (pengukuran ulang Phase 7) | 242.735 / 253.867 / 265.221     | **242.735 / 253.867 / 265.221** — terverifikasi langsung via `forge test --match-test testGas -vv` (log 16); cross-check 242.735 / 253.868 / 265.229 (selisih ≤ 8 gas)                    |

**Caveat battery (dicatat dengan jujur):**

1. **`node_modules` lokal sudah basi** — terinstal Next **14.2.35** +
   React **18.3.1**, sementara lockfile mem-pin Next 15.5.29 + React
   19.3.1 (vitest/viem/wagmi/TS/playwright cocok). Semua verifikasi sisi
   JS berjalan di runtime lama itu; angkanya cocok persis dengan klaim
   Phase 6 (yang diukur dari instalasi frozen-lockfile bersih), tetapi
   secara ketat ini verifikasi atas tree basi. `pnpm install` tidak
   mungkin di VM ini (EPERM). Verifikasi penuh atas tree yang di-pin
   butuh mesin lain atau CI — CI run #4 (#44561141296) HIJAU 10/10 pada
   HEAD yang sama adalah otoritas untuk tree yang di-pin.
2. **Build via-IR lambat di VM ini** (1,5 CPU): run bersih 9+ menit
   belum selesai untuk 94 file; shared build Phase 7 terbunuh SIGTERM;
   satu build auditor terbunuh OOM saat 3 build via-IR berjalan
   bersamaan. Ini keterbatasan mesin, bukan regresi — timeout CI
   15–30 menit/job masih mencakup build tunggal.
3. **Slither menjalankan `forge clean` + rebuild tanpa test/script**,
   sehingga `out/` kini hanya berisi artefak `src/`; `forge test`
   berikutnya perlu rebuild penuh.

## 9. Errata laporan Phase 6

Review ini menemukan ketidakakuratan pada laporan Phase 6 yang layak
dikoreksi (tidak satu pun mengubah penilaian keamanan material, kecuali
PH7-H01 yang sudah menjadi temuan tersendiri):

| #   | Klaim Phase 6                                                                                                | Koreksi Phase 7                                                                                                                                               |
| --- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| E1  | "via-IR menghilangkan MCOPY" (1× di Reputation + 1× di Achievement → 0)                                      | **Salah.** MCOPY baseline adalah false positive dari hash metadata IPFS (PH7-M10). 0 opcode Cancun-only di kedua build. Temuan Phase 5 F3 tidak pernah valid. |
| E2  | Rincian Slither app-only "4 Low + 7 Info"                                                                    | Seharusnya **4 Low + 8 Info = 12** (PH7-L25). Detektor `pragma` terbuang saat filtering JSON.                                                                 |
| E3  | Warning build "pre-existing" + "satu `environment-read-across-mutation` dari EconomicAttack"                 | 3 warning `require-revert-in-loop` BARU dari kode Phase 6 (PH7-L24); 8 instansi `environment-read-across-mutation`, nol dari EconomicAttack (PH7-L26).        |
| E4  | Build legacy ~8 detik                                                                                        | Build legacy bersih **2 mnt 4 dtk** (PH7-I11). Rasio via-IR/legacy ≈ 10× CPU, bukan ≈ 40×.                                                                    |
| E5  | Angka gas headline 242.735 / 253.867 / 265.221 (tanpa bukti di log)                                          | **Angka benar** — terverifikasi langsung dalam review ini (PH7-L27, log 16). Bukti kini tersedia.                                                             |
| E6  | Kebijakan threshold 2 untuk reward > 1.000 / real-world badge (didokumentasikan sebagai bagian implementasi) | Kebijakan itu **SOP-only**, tidak ditegakkan kode (PH7-H01, PH7-M02). Laporan tidak menyatakan ketiadaan penegakan ini.                                       |
| E7  | Klaim build 303 detik                                                                                        | Tidak ada bukti durasi di log (PH7-L28); pengukuran Phase 7 (5 mnt 13 dtk CPU) konsisten dengan klaim.                                                        |
| E8  | `slither-phase6.json` sebagai artefak run regresi                                                            | JSON berasal dari run implementer sebelum clean-copy (PH7-L29); isinya konsisten, byte-nya bukan artefak run tersebut.                                        |

## 10. Keterbatasan review ini (baca sebelum mengutip "aman")

Review ini **tidak** menyatakan sistem aman. Yang diklaim hanyalah:
pada HEAD `5723ff3`, dengan metode di atas, tidak ditemukan kerentanan
Critical dan tidak ada vektor serangan eksternal yang exploitable.
Keterbatasan yang berlaku:

1. **Bukan external review.** Review ini dilakukan oleh agen-agen
   dalam lingkungan yang sama dengan implementasi (R-012, external
   review yang dikomisikan, belum terjadi). Review independen eksternal
   tetap diperlukan sebelum mainnet.
2. **Tidak ada pengujian di chain live.** Semua PoC berjalan di Foundry
   lokal (Anvil, chainId 31337) dan fork testnet kering. Perilaku di BSC
   testnet — termasuk interaksi dengan kontrak Agent ID mock, Safe
   nyata, dan RPC publik — belum terbukti. Itulah fungsi smoke test
   testnet yang menjadi syarat penutupan R-010.
3. **Hasil tes internal bukan bukti keamanan.** 287 test + fuzz + E2E
   hijau membuktikan kode berperilaku sesuai spesifikasi yang diuji —
   bukan bahwa spesifikasinya lengkap atau tidak ada kelas bug di luar
   cakupan test. Review manual di sini menutup sebagian celah itu, tetapi
   review manual juga terbatas oleh waktu dan cakupan.
4. **Verifikasi JS berjalan di tree basi** (Next 14 + React 18
   terinstal vs Next 15 + React 19 yang di-pin — lihat §8 caveat 1).
   Otoritas untuk tree yang di-pin adalah CI (hijau 10/10), bukan
   battery lokal ini.
5. **Asumsi kepercayaan yang tidak diuji:** kejujuran admin/timelock,
   keamanan kunci verifier dan creator, kebenaran kontrak Agent ID
   resmi, dan keamanan dependensi OpenZeppelin (temuan Slither
   1 High + 8 Medium di `lib/` dicatat tetapi di luar scope — itu
   kode OpenZeppelin, bukan AGENTHUB).
6. **Satu bug compiler low tidak dapat disingkirkan secara statis**
   (`YulOptimizerKnowledgeBaseStaleBookkeeping`, PH7-L13) — mitigasi
   empirisnya adalah test battery + smoke test testnet + evaluasi
   upgrade solc sebelum mainnet.
7. **Cakupan:** review ini fokus pada diff Phase 6 dan interaksinya.
   Audit penuh keempat kontrak dari nol, audit frontend menyeluruh, dan
   audit dependensi JS di luar OSV bukan bagian dari review ini.

## 11. Yang harus diperbaiki sebelum mainnet — dan sebelum testnet

### Wajib sebelum mainnet (blocker)

| #   | Temuan                        | Perbaikan                                                                                                                    |
| --- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 1   | PH7-H01 (High)                | Validasi on-chain `rewardPoints > 1.000 → threshold ≥ 2` di `createQuest` + test kebijakan di CI                             |
| 2   | PH7-M02                       | Definisikan "real-world badge" di kode (flag/kategori `Badge`) + penegakan di `createQuest`                                  |
| 3   | PH7-M01                       | Guardrail on-chain (counter verifier + `highestLiveThreshold`) atau tooling pre-revoke yang ditegakkan + SOP                 |
| 4   | PH7-M03                       | `QUEST_CREATOR` wajib Safe multisig terverifikasi; pertimbangkan review window / alur dua langkah untuk quest bernilai besar |
| 5   | PH7-L01                       | Batas total emisi reputasi per creator/quest atau mitigasi monitoring yang terdokumentasi                                    |
| 6   | PH7-L13                       | Evaluasi upgrade solc ≥ 0.8.38 dengan re-regressi penuh                                                                      |
| 7   | PH7-M07, M08, M09             | Tutup celah deteksi ABI: deep-equal keempat kontrak berjalan di CI; `EVENT_SIGNATURES` diturunkan dari ABI / ditest          |
| 8   | —                             | External security review (R-012) dikomisikan dan temuan kritisnya ditutup                                                    |
| 9   | O4 (dari validasi sebelumnya) | Uji wallet-app nyata (wagmi hanya `injected()`, tanpa WalletConnect)                                                         |
| 10  | —                             | ≥ 3 verifier di-grant sebelum quest threshold-2 pertama di mainnet                                                           |

### Disarankan sebelum broadcast testnet (murah, risiko regresi minimal)

| #   | Temuan            | Perbaikan                                                                                               |
| --- | ----------------- | ------------------------------------------------------------------------------------------------------- |
| 1   | PH7-M05           | Tambahkan `CONFIRM_TESTNET_DEPLOY=true` guard                                                           |
| 2   | PH7-M06           | Tambahkan `require(block.chainid == 31337)` ke `DeployLocalTestStack`                                   |
| 3   | PH7-M04           | Putuskan ownership MockAgentId (transfer ke multisig / retensi terdokumentasi) + cek di `_verifyWiring` |
| 4   | PH7-L15, L14      | Lengkapi `.env.example`; tambahkan `[rpc_endpoints]`                                                    |
| 5   | PH7-L16, L18, L22 | Perbaiki hitungan wiring di dokumen; artefak JSON deployment; tabel constructor args                    |
| 6   | PH7-L20           | Bersihkan artefak broadcast fork chain 97 (atau beri label jelas)                                       |
| 7   | PH7-L23           | Tambahkan 3 prasyarat operasional ke checklist §1 (RPC teruji, Safe sudah dibuat, dompet uji didanai)   |
| 8   | PH7-L05           | Pindahkan cek `provided < threshold` sebelum loop recovery (satu baris, hemat gas)                      |

### Input deployment yang masih dibutuhkan dari user (tidak berubah)

tBNB (≥ 0,05), deployer key khusus testnet, alamat Safe testnet
(threshold ≥ 2), quest creator, verifier pertama (opsional), pauser
(opsional), BscScan API key, persetujuan broadcast eksplisit — ditambah
3 prasyarat operasional PH7-L23.

## 12. Status R-010

**IMPLEMENTED, belum CLOSED.** Tidak berubah oleh review ini. Kriteria
penutupan dari rencana remediasi yang masih terbuka: (1) testnet smoke —
quest threshold-1 dan threshold-2 dibuat dan diselesaikan di live
testnet, revert duplikat/insufficient teramati on-chain (terblokir 8 input
user); (2) diff termasuk dalam external review yang dikomisikan (R-012,
belum dikomisikan); (3) ≥ 3 verifier di-grant sebelum quest threshold-2
pertama di mainnet. Review Phase 7 ini adalah langkah menuju (2), bukan
penggantinya.

## 13. Manifest verifikasi & indeks bukti

- **HEAD yang diaudit:** `5723ff377de3d2cd79854b877124a802fb2c23eb`
  (`5723ff3`). Working tree bersih kecuali direktori baru
  `agenthub-phase7-review/` (tidak ada file terlacak yang diubah —
  `git status` hanya menunjukkan `?? agenthub-phase7-review/`).
- **Hash SHA-256 laporan ini** tidak dapat tercantum di dalam laporan
  itu sendiri (self-referential); hash laporan beserta hash seluruh file
  temuan dan log tercatat di `agenthub-phase7-review/VERIFICATION.md`
  yang dihasilkan setelah penulisan final laporan ini.
- **PACKAGE_MANIFEST.md tidak diperbarui** — tidak ada file terlacak
  yang berubah; regenerasi manifest menjadi bagian dari langkah commit
  (keputusan parent agent / user).
- **Prettier:** setelah laporan ini ditulis, seluruh direktori
  `agenthub-phase7-review/` diformat dengan `prettier --write` sehingga
  tidak ada lagi file review yang gagal format check (battery mencatat
  9 file gagal sebelum pemformatan — semuanya artefak review, nol di
  source).

### Laporan workstream (`agenthub-phase7-review/findings/`)

| File                                   | Workstream                    | Temuan                                        |
| -------------------------------------- | ----------------------------- | --------------------------------------------- |
| `01-diff-audit.md`                     | Audit diff Phase 6            | 62 file, 9 surprise (S-01–S-09)               |
| `02-questmanager-review.md`            | Review QuestManager + EIP-712 | 1 Medium, 6 Low, 5 Info; 14/14 PoC            |
| `03-threshold-immutability-attacks.md` | Immutability + serangan       | 1 Medium, 3 Low, 3 Info; 25/25 PoC            |
| `04-policy-enforcement.md`             | Penegakan kebijakan           | 1 High, 2 Medium, 2 Low, 1 Info               |
| `05-abi-parity.md`                     | Paritas ABI                   | 0 drift / 201 entri; 3 Medium, 2 Low, 2 Info  |
| `06-via-ir-bytecode.md`                | via-IR + bytecode             | 0 opcode Cancun-only; 1 Medium, 1 Low, 3 Info |
| `07-test-battery.md`                   | Test battery penuh            | Semua suite terverifikasi (lihat §8)          |
| `08-deployment-testnet.md`             | Deployment + testnet          | 3 Medium, 10 Low, 4 Info                      |

### Log (`agenthub-phase7-review/logs/`)

`01-forge-build.log` s.d. `15-fmt-prettier.log` (test battery — lihat
findings/07 §6) + `16-gas-remeasure.log` (pengukuran ulang gas Phase 7
oleh koordinator: 242.735 / 253.867 / 265.221).

### PoC Foundry (salinan scratch, bukan repo utama)

- `~/workspace/.tmp/phase7-contracts-poc/contracts/test/Phase7ReviewPoC.t.sol`
  — 14/14 lolos.
- `~/workspace/.tmp/phase7-attack-poc/packages/contracts/test/Phase7AttackPoC.t.sol`
  — 25/25 lolos.
- Skrip audit ABI: `~/workspace/.tmp/abi-audit.mjs` (+ output
  `abi-audit-head5723ff3.txt`, `abi-audit-phase7-abi.txt`,
  `abi-audit-baseline-control.txt`).
- Skrip audit bytecode: `~/workspace/.tmp/phase7-bytecode-audit.py`
  (+ worktree `~/workspace/.tmp/phase7-bytecode/` dan
  `~/workspace/.tmp/phase7-baseline/`).

## Lampiran A — Peta deduplikasi temuan

Empat pasang temuan dari workstream berbeda digabung menjadi satu temuan
unified (temuan dengan severity lebih tinggi yang dipakai):

| Temuan unified | Sumber yang digabung                                                              |
| -------------- | --------------------------------------------------------------------------------- |
| PH7-M01        | 02/F1 (Medium) + 03/P7-01 (Medium) — revoke verifier me-brick quest               |
| PH7-L05        | 02/F6 (Low, 16.222 gas) + 03/P7-05 (Info, 3.234 gas) — cek threshold setelah loop |
| PH7-L06        | 02/F7 (Low) + 03/P7-03 (Low) — nonce global per akun                              |
| PH7-I04        | 02/I4 (Info) + 03/P7-06 (Info) — event QuestCreated tanpa threshold               |

Total mentah 63 temuan − 4 penggabungan = **59 temuan unik**
(1 High + 10 Medium + 31 Low + 17 Info).

---

_Phase 7 selesai 20 November 2026. Keputusan: CONDITIONAL GO testnet,
NO-GO mainnet. R-010: IMPLEMENTED, belum CLOSED._
