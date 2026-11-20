# AGENTHUB — Phase 9, Workstream 1: Review Kebijakan Reward

**Tanggal:** 20 November 2026.
**Baseline:** HEAD `e1b316b` (Phase 8 final, Solidity 0.8.39, `via_ir=true`).
**Ruang lingkup:** temuan Phase 7 PH7-H01, PH7-M02, PH7-L08, PH7-I07 dan
keputusan desain Phase 8 yang membatasi kebijakan threshold pada quest
Attested.
**Acuan:** `agenthub-phase8-remediation/PHASE8_SECURITY_REMEDIATION_REPORT.md`
(§2 H01/M02, §3 L08/I07),
`agenthub-phase7-review/PHASE7_INDEPENDENT_SECURITY_REVIEW.md`,
`packages/contracts/src/QuestManager.sol`,
`packages/contracts/src/Achievement.sol`,
`packages/contracts/test/PolicyEnforcement.t.sol`,
`docs/SECURITY_THREAT_MODEL.md`, `docs/NEW_THREAT_MODEL.md`,
`docs/QUEST_VALIDATION_DESIGN.md`, `docs/VERIFIER_ROLE_SOP.md` §6.1.

---

## 1. Keputusan: A — Pengecualian desain SAH, jangan ubah kode

**Pengecualian Phase 8 (kebijakan threshold hanya berlaku untuk quest
Attested) adalah sah secara keamanan. Tidak ada perubahan kode, tidak ada
perubahan test.** PH7-L08 dan PH7-I07 ditutup sebagai keputusan desain
oleh dokumen ini (§6).

Alasan dalam satu kalimat: **threshold adalah kontrol atas pihak ketiga
yang mengesahkan (verifier), dan hanya jalur Attested yang punya pihak
ketiga untuk dikontrol** — pada CheckIn/OnChain tidak ada attestation
yang bisa di-threshold, sehingga memaksakan threshold ≥ 2 di sana tidak
mengurangi kemampuan penyerang mana pun; ia hanya mengubah satu byte
metadata yang tidak pernah dibaca saat completion, dan menciptakan
kesan keamanan palsu (false confidence) — persis mode kegagalan yang
dikritik Phase 7 pada H01.

Bukti struktural yang menentukan: nilai `attestationThreshold` yang
tersimpan hanya pernah ditegakkan di **satu titik** dalam seluruh
codebase — `QuestManager.sol:336` (`provided < threshold` di dalam
`_verifyAttestations`), yang hanya dapat dicapai lewat
`completeQuestWithAttestation` (`QuestManager.sol:295`), yang menolak
quest non-Attested di gerbang kind (`QuestManager.sol:294`,
`QuestNotAttested`). Jalur `completeQuest` (CheckIn/OnChain) tidak
pernah membaca nilai itu. Grep atas seluruh pemakaian
`attestationThreshold` di `QuestManager.sol` mengonfirmasi: semua
pembacaan di luar `createQuest` adalah jalur Attested
(verifikasi:295, counter guardrail M01:260–263, 541 — keduanya
bercabang Attested-only).

---

## 2. Analisis ancaman per ValidationKind

### 2.1 Attested — threshold bermakna, kebijakan tepat sasaran

**Siapa yang mengesahkan:** M verifier berbeda pemegang `VERIFIER_ROLE`,
masing-masing menandatangani digest EIP-712 yang sama
(account + questId + nonce + deadline), diverifikasi di
`_verifyAttestations` (`QuestManager.sol:303–350`): batas array,
deadline ≤ 7 hari, recovery ECDSA anti-malleable, cek role per signer
saat verifikasi (revoke langsung menginvalidasi), distinctness pairwise,
`provided ≥ threshold` (`:336`), konsumsi nonce sekali pakai.

**Trust assumption:** verifier jujur dan kuncinya aman. Attestation
membuktikan "verifier berwenang menandatangani", bukan "verifier berkata
benar" (`QUEST_VALIDATION_DESIGN.md` §2.3; `NEW_THREAT_MODEL.md`
T-ATT-01, High residual). Threshold M menaikkan biaya serangan dari 1
kunci kompromi menjadi M kunci kompromi/berkolusi.

**Skenario serangan (reward 10.000, T1):** satu verifier dikompromi
menandatangani attestation untuk akun mana pun, tanpa batas jumlah akun
(`maxCompletions = 0`) — 10.000 poin per akun, plus badge bila ada.
**Threshold 2 mencegahnya secara nyata:** penyerang butuh kunci verifier
kedua yang independen; satu kunci saja tidak cukup. Inilah skenario yang
dirancang dicegah R-010 dan yang direproduksi PH7-H01. Kebijakan
`createQuest` (`QuestManager.sol:196–200`) menutupnya di akar: quest
Attested > 1.000 poin tidak bisa lahir dengan T1.

**Catatan batas:** threshold tidak melindungi dari M verifier berkolusi,
dan tidak melindungi dari creator nakal (creator memilih threshold —
lihat §2.4). Kedua residual itu sudah dicatat di threat model dan di
luar jangkauan kebijakan ini.

### 2.2 CheckIn — threshold tidak bermakna; floor T2 adalah teater

**Siapa yang mengesahkan:** tidak ada siapa-siapa — completer sendiri.
`completeQuest` (`QuestManager.sol:274–284`) → `_completeQuest`
(`:399–463`) hanya memeriksa: pemegang Agent ID, aktif, jendela waktu,
cap, duplikat/cooldown, supersedes. Tidak ada signature, tidak ada
verifier, tidak ada bukti eksternal. Desain dokumen menyebutnya jujur:
"the call IS the activity" (`QUEST_VALIDATION_DESIGN.md` §2.1).

**Trust assumption:** tidak ada klaim pembuktian sama sekali. Satu-satunya
janji adalah label jujur di UI ("Check-in — no external proof required",
never "verified" — desain §3).

**Skenario serangan (reward 10.000, T1) — satu per satu:**

| Aktor                                  | Serangan                                                                      | Apa yang didapat                                                                                                                 | Apakah T2 mencegah?                                                                                                                                                                                                                                                                                                                                                                                                                |
| -------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Creator nakal / kunci creator kompromi | Buat quest CheckIn 10.000 poin, farming sendiri / biarkan siapa pun farming   | Poin tak terbatas (per quest 10.000 × N akun; atau quest repeatable tanpa cap)                                                   | **Tidak.** Creator-lah yang memilih threshold; ia tinggal memasukkan 2. Completion tetap nol signature. Kontrol yang nyata: creator wajib Safe multisig tervalidasi (PH7-M03, ditutup Phase 8), cap per-quest 10.000 (`QuestManager.sol:56` + cap per-event `Reputation.sol:71`), penerbitan publik + monitoring lonjakan (SOP §8), `deactivateQuest`/`pause()`. Total tak terbatas sudah diterima eksplisit (PH7-L01, AR-3 — §5). |
| Verifier kompromi                      | —                                                                             | Tidak ada. Verifier tidak berperan di jalur ini; kunci verifier tidak memberi kemampuan apa pun atas quest CheckIn.              | Tidak relevan.                                                                                                                                                                                                                                                                                                                                                                                                                     |
| User (self-farming)                    | Menyelesaikan quest berulang                                                  | Dibatasi aturan anti-farming yang ortogonal terhadap threshold: OneTime sekali per akun, cooldown Daily/Weekly, `maxCompletions` | **Tidak.** T2 tidak mengubah satu pun aturan itu.                                                                                                                                                                                                                                                                                                                                                                                  |
| Integrator/indexer tertipu             | Membaca `attestationThreshold = 1` dan menyimpulkan "lemah" — atau sebaliknya | Kebingungan label, bukan pencurian                                                                                               | **T2 memperburuknya:** quest CheckIn T2 akan terbaca "membutuhkan 2 signature verifier" padahal membutuhkan nol. UI sudah menangani ini dengan benar: threshold hanya dirender bila kind Attested (`apps/web/components/QuestCardLive.tsx:57`).                                                                                                                                                                                    |

**Kesimpulan CheckIn:** tidak ada aktor yang kemampuannya berkurang bila
floor T2 diberlakukan. Satu-satunya efek B adalah memaksa creator
menulis angka 2 pada field yang tidak pernah ditegakkan — teater murni,
dengan efek samping negatif (state menyesatkan + false confidence).

Pertanyaan yang _sah_ tentang CheckIn 10.000 poin bukanlah threshold,
melainkan **ukuran reward**: apakah satu bare call pantas dihargai
10.000 poin? Itu pertanyaan kebijakan besaran (per-kind reward cap),
bukan kebijakan attestation — lihat §6.2 untuk keputusan eksplisitnya.

### 2.3 OnChain — threshold tidak bermakna; pengesah adalah kode, bukan penanda tangan

**Siapa yang mengesahkan:** kontrak validator quest itu, dipanggil via
STATICCALL di fase checks (`_validateOnChain`, `QuestManager.sol:515–533`;
dipanggil dari `_completeQuest:440`), dengan cek returndata ketat
(32 byte, word 0/1) dan cek ulang approval registry saat completion.
Validator yang revert/gagal format = completion gagal (fail-closed).

**Trust assumption:** (a) kode validator benar-benar mengkodekan kondisi
yang dimaksud — dijamin proses, bukan kriptografi: approval per-instance
oleh admin (timelock) dengan metadata wajib nama/versi/dokumentasi
(`approveValidator`, desain §2.4); (b) validator tidak bisa mengubah state
— dijamin EVM via STATICCALL; (c) kondisi dicek live tiap completion
(T-VAL-02, mitigated).

**Skenario serangan (reward 10.000, T1) — satu per satu:**

| Aktor                                                                                               | Serangan                                          | Apa yang didapat                            | Apakah T2 mencegah?                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Creator nakal + validator longgar                                                                   | Lampirkan validator always-true (quest ≡ CheckIn) | Semua pemegang Agent ID dapat 10.000 poin   | **Tidak.** Creator hanya bisa melampirkan validator yang sudah disetujui admin (`createQuest` cek `_validatorInfo[validator].approved`, `:221–229`). Validator always-true harus lolos review sumber + timelock 2 hari — itu kegagalan governance, bukan threshold. Dan creator tinggal menulis T2. Kontrol nyata: proses approval validator + revocasi live (`revokeValidator` / `emergencyRevokeValidator` efektif seketika saat completion). Tercatat sebagai residual T-VAL-01 (Medium, creator-trust). |
| Validator berubah pasca-approval (proxy upgrade / kondisi menjadi trivial, mis. harga token runtuh) | Kondisi yang dulu ketat menjadi mudah dipenuhi    | Farming massal 10.000 poin                  | **Tidak.** Validator adalah satu kontrak; tidak ada signature kedua untuk diminta. Kontrol nyata: prefer validator non-proxy konfigurasi immutable (desain §2.4), pencatatan codehash + SOP approval (PH7-L04 — masih terbuka, prosedural), revocasi darurat.                                                                                                                                                                                                                                               |
| User mengakali kondisi on-chain (mis. pinjam token sesaat untuk lolos balance check)                | Lolos kondisi tanpa memenuhi maksudnya            | 10.000 poin per akun                        | **Tidak.** Ini masalah desain validator (mis. butuh time-weighted balance / snapshot), bukan threshold.                                                                                                                                                                                                                                                                                                                                                                                                     |
| Verifier kompromi                                                                                   | —                                                 | Tidak ada. Tidak ada verifier di jalur ini. | Tidak relevan.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

**Catatan desain:** M-of-N yang _bermakna_ untuk OnChain akan berbentuk
"M dari N kontrak validator harus mengembalikan true" — itu mekanisme
baru (multi-validator), bukan penegakan kebijakan atas field yang sudah
ada. Ia membutuhkan desain, review, dan test tersendiri, dan tidak
dituntut oleh ancaman mana pun di atas: validator sudah berada di bawah
kontrol admin timelock + revocasi live. Dicatat sebagai ide desain masa
depan (§7), bukan kebutuhan Phase 9.

**Kesimpulan OnChain:** sama seperti CheckIn — floor T2 mengubah nol
kemampuan penyerang.

### 2.4 Argumen struktural: siapa yang memilih parameter

Threshold dipilih oleh **creator** saat `createQuest`. Floor atas
parameter pilihan creator hanya punya makna keamanan bila parameter itu
mengikat **pihak lain** selain creator. Pada Attested, ia mengikat
verifier (role, kunci, dan domain kepercayaan yang berbeda dari creator).
Pada CheckIn/OnChain, tidak ada pihak ketiga di jalur completion —
hanya creator (yang menetapkan parameter) dan completer (yang membuktikan
diri sendiri atau memenuhi kondisi deterministik on-chain). Membatasi
parameter yang hanya ditetapkan creator dan tidak ditegakkan siapa pun
tidak dapat mengurangi kemampuan penyerang mana pun, siapa pun aktornya.
Inilah alasan formal mengapa pengecualian Phase 8 sah, dan mengapa opsi B
bukan "defense in depth" melainkan teater: defense in depth menambah
lapisan yang _berfungsi_; B menambah lapisan yang _tidak terhubung ke
apa pun_.

Uji delta opsi B: di bawah B, quest CheckIn 10.000 poin dibuat dengan
threshold 2, bukan 1. Perilaku completion: identik. Kemampuan semua aktor:
identik. Nilai keamanan marginal: **nol**. Biaya: bukan nol — state
menyebabkan, false confidence, churn kode + gas + permukaan re-audit,
dan inkonsistensi dengan guardrail M01 (counter `liveAttestedByThreshold`
hanya menghitung quest Attested, `QuestManager.sol:260–263, 541` — quest
CheckIn "T2" bahkan tidak berpartisipasi dalam guardrail ketersediaan
verifier, sehingga klaim T2-nya kosong di dua level).

---

## 3. High-value badge: konsistensi kebijakan di semua kind

Aturan badge di `createQuest` (`QuestManager.sol:209–213`) juga
Attested-only — dan itu **konsisten**, dengan alasan yang sama:

- Badge diterbitkan di `_completeQuest` (`QuestManager.sol:455–458`)
  pada _setiap_ completion yang berhasil, apa pun kind-nya. Integritas
  badge diturunkan dari integritas jalur completion, bukan dari field
  threshold.
- Pada Attested, T2 menaikkan bar terhadap verifier kompromi yang ingin
  mencetak badge bernilai dunia nyata — perlindungan nyata, ditegakkan
  (`:336`).
- Pada CheckIn, siapa pun pemegang Agent ID bisa self-complete dan
  mengklaim badge terlepas dari threshold tersimpan. Floor T2 tidak
  melindungi badge sedikit pun.
- Pada OnChain, perlindungan badge adalah kualitas validator + approval
  admin, bukan threshold.

**Residual yang nyata — dan berbeda:** pertanyaan sah bukanlah "apakah
badge high-value di quest CheckIn harus T2?", melainkan "bolehkah badge
high-value dilekatkan pada quest CheckIn sama sekali?" — karena di sana
badge bernilai dunia nyata dapat diklaim dengan satu bare call. Itu
pertanyaan **pembatasan kind**, bukan threshold, dan jawaban yang benar
adalah kontrol yang sesuai: aturan SOP (jangan lekatkan badge high-value
pada quest CheckIn tanpa review eksplisit) dan, bila tim menghendaki,
pembatasan kind on-chain di fase mendatang. Ini dicatat sebagai
rekomendasi tindak lanjut R-9-WS1-1 (§7) — **bukan** alasan memilih B,
dan **bukan** blocker: blast radius saat ini terbatas (badge soulbound,
satu per (akun, badgeId) — `Achievement.sol:88–92`, penerbitan publik,
creator multisig, flag dikontrol `BADGE_MANAGER_ROLE`), dan tidak ada
badge high-value yang dilekatkan pada quest CheckIn di deployment mana
pun saat ini (belum ada deployment).

Flag `highValue` sendiri sudah tepat desainnya untuk peran ini: mutable
via `setBadgeHighValue` (`Achievement.sol:62–66`) agar klasifikasi bisa
berubah sepanjang hidup badge, dibaca hanya saat creation (re-flagging
tidak mengubah quest live — ditest di
`PolicyEnforcement.t.sol:test_HighValueFlagIsMutableAndReadAtCreation`),
getter tidak pernah revert (`Achievement.sol:70–75`).

---

## 4. Konsistensi dengan threat model repo

Keputusan ini konsisten dengan threat model yang sudah diterima:

- **AR-3 / T4 "rogue creator capped 10.000"**
  (`SECURITY_THREAT_MODEL.md:355`, `:188–195`): cap bersifat **per-quest**,
  total tidak ter-cap — diterima eksplisit (PH7-L01) atas dasar creator
  tepercaya (multisig kampanye, kini ditegakkan on-chain oleh validasi
  Safe PH7-M03), penerbitan publik + monitoring lonjakan, dan rem
  deactivate/pause. Risiko CheckIn/OnChain 10.000 poin adalah **tepat
  residual AR-3 yang sudah diterima itu** — bukan residual baru yang
  diperkenalkan pengecualian ini. Kebijakan threshold tidak pernah menjadi
  kontrol atas creator (creator memilih threshold); ia adalah kontrol atas
  kompromi verifier (T-ATT-01). Mencampur kedua aktor itu adalah kesalahan
  kategori yang mendasari proposal penegakan universal.
- **T-ATT-01** (`NEW_THREAT_MODEL.md:23`): satu-satunya ancaman yang
  dikendalikan threshold, Attested-only — tercakup penuh oleh kebijakan
  Phase 8.
- **T-VAL-01 / T-VAL-02** (`NEW_THREAT_MODEL.md:56, 70`): ancaman OnChain
  dikendalikan proses approval validator + STATICCALL + revocasi live —
  tidak satu pun melibatkan threshold.
- **Cap pertahanan berlapis yang kind-agnostik tetap berlaku:**
  `MAX_REWARD_POINTS = 10.000` per quest (`QuestManager.sol:56`) dan
  `MAX_POINTS_PER_EVENT = 10.000` per event di lapisan award
  (`Reputation.sol:19, 71`) — lapisan kedua ini berlaku untuk semua kind
  tanpa kecuali.

---

## 5. Keputusan desain formal (PH7-L08 / PH7-I07)

**D-9-WS1-1 (kebijakan threshold).** Kebijakan threshold — reward

> 1.000 poin atau badge high-value → `attestationThreshold ≥ 2` — berlaku
> **hanya untuk quest Attested**, ditegakkan on-chain di `createQuest`
> (`QuestManager.sol:196–200, 209–213`). Ini bukan celah, melainkan
> konsekuensi dari semantik field: threshold adalah jumlah minimum
> signature verifier berbeda yang ditegakkan saat completion, dan hanya
> jalur Attested yang memverifikasi signature.

**D-9-WS1-2 (CheckIn boleh membawa reward besar).** Quest CheckIn
**boleh** membawa reward sampai cap per-quest 10.000 poin pada threshold

1. Besaran reward CheckIn adalah keputusan produk/kampanye yang dibatasi
   oleh kontrol yang sudah ada (creator multisig, cap per-quest +
   per-event, monitoring lonjakan, deactivate/pause) — bukan oleh threshold.
   Tidak ada per-kind reward cap on-chain: angka berapa pun bersifat
   kebijakan arbitrer (argumen yang sama dengan penerimaan PH7-L01), dan
   cap yang salah berisiko memblokir kampanye sah.

**D-9-WS1-3 (OnChain).** Quest OnChain **boleh** membawa reward sampai
10.000 poin pada threshold 1. Integritasnya berasal dari validator yang
disetujui admin + revocasi live, bukan dari threshold.

**D-9-WS1-4 (badge).** Aturan badge high-value → threshold ≥ 2 juga
Attested-only, dengan alasan yang sama. Pertanyaan "badge high-value
pada quest CheckIn" adalah masalah pembatasan kind, ditangani lewat
rekomendasi R-9-WS1-1 (§7), bukan lewat threshold.

**Syarat yang harus tetap dipenuhi** (bila satu saja dilanggar,
keputusan ini harus ditinjau ulang):

1. `QUEST_CREATOR_ROLE` tetap dipegang Safe multisig tervalidasi
   (PH7-M03) — seluruh argumen "rogue creator" bertumpu pada ini.
2. Proses approval validator tetap berlaku (review sumber penuh,
   per-instance, timelock) + revocasi live berfungsi — satu-satunya
   kontrol atas integritas OnChain.
3. UI tetap melabeli kind dengan jujur (CheckIn tidak pernah "verified";
   threshold hanya ditampilkan untuk Attested —
   `QuestCardLive.tsx:56–59`, desain §3).
4. Monitoring lonjakan completion (SOP §8) tetap berjalan; deactivate +
   pause tetap siap sebagai rem.
5. Dokumentasi NatSpec ruang lingkup threshold
   (`IQuestManager.sol:53–56`, `QuestManager.sol:30–41`) tetap akurat
   bila kode berubah — integrator mengandalkan ini, bukan nilai mentah.
6. Tidak ada jalur completion baru yang membaca `attestationThreshold`
   tanpa melalui `_verifyAttestations` — bila ada, keputusan ini batal
   dan kebijakan harus ditinjau ulang.

---

## 6. Penutupan temuan

| ID               | Disposisi                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PH7-L08          | **DITUTUP sebagai keputusan desain** (D-9-WS1-1). Rekomendasi Phase 7 ("simpan threshold 1 untuk non-Attested, atau dokumentasikan") sudah dipenuhi lewat dokumentasi: NatSpec `IQuestManager.Quest` (`IQuestManager.sol:53–56`: "Only Attested quests use it; other kinds store it but never enforce it"), `QUEST_VALIDATION_DESIGN.md` §2.3, SOP §6.1, dan UI yang hanya merender threshold untuk Attested (`QuestCardLive.tsx:57`). Opsi "paksa threshold 1" dipertimbangkan dan ditolak (§7) — churn tanpa keuntungan keamanan. |
| PH7-I07          | **DITUTUP sebagai keputusan desain** (D-9-WS1-2, D-9-WS1-3). Pertanyaan eksplisitnya ("bolehkah CheckIn membawa reward besar?") dijawab: ya, sampai cap 10.000, dengan kontrol yang sudah ada; tidak ada per-kind reward cap.                                                                                                                                                                                                                                                                                                       |
| PH7-H01, PH7-M02 | Tetap **ditutup oleh Phase 8** (penegakan on-chain Attested + test). Review ini mengonfirmasi ruang lingkup Attested-only-nya sah dan tidak mempersempit cakupan yang dimaksud Phase 7: rekomendasi H01 sendiri berbunyi "Putuskan eksplisit apakah aturan berlaku hanya untuk Attested" — keputusan itu kini dibuat dan dibuktikan di sini.                                                                                                                                                                                        |

**Test yang mengunci keputusan ini** (sudah ada, tidak diubah):
`PolicyEnforcement.t.sol:300` (`test_CheckInHighRewardExemptFromPolicy`),
`:313` (`test_OnChainHighRewardExemptFromPolicy`),
`:320` (`test_CheckInHighValueBadgeExemptFromPolicy`).
Seluruh suite Phase 8 (Foundry 321/321, fuzz 10k seed 42) tetap berlaku
tanpa perubahan — tidak ada kode yang diubah oleh workstream ini.

---

## 7. Alternatif yang dipertimbangkan dan ditolak + rekomendasi

**Ditolak:**

- **(B) Penegakan universal threshold ≥ 2.** Nilai keamanan marginal nol
  (§2.2–2.4); menambah false confidence — mode kegagalan yang sama
  dengan yang dikritik H01.
- **Paksa threshold = 1 untuk non-Attested saat creation** (opsi pertama
  L08). Keuntungan hanya higienis label; kerugiannya nyata: memecah
  invarian "uniform 1–3", mengubah test yang sudah mengunci perilaku,
  dan menutup pintu desain multi-validator masa depan. Dokumentasi +
  gating UI sudah menyelesaikan kebingungan yang ditakutkan L08.
- **Per-kind reward cap on-chain** (mis. CheckIn maks 100 poin). Angka
  arbitrer; argumen penolakan yang sama dengan PH7-L01. Dapat ditinjau
  ulang bila ada penyalahgunaan nyata.
- **M-of-N validator untuk OnChain.** Mekanisme nyata tetapi fitur baru
  penuh (desain + review + test); tidak dituntut ancaman mana pun saat
  ini karena validator sudah di bawah kontrol timelock + revocasi live.

**Rekomendasi tindak lanjut (di luar workstream ini, bukan blocker):**

- **R-9-WS1-1 — SOP badge high-value per kind.** Tambahkan ke SOP/badge
  runbook: badge high-value sebaiknya hanya dilekatkan pada quest
  Attested (atau OnChain dengan validator ketat); pelekatan pada CheckIn
  memerlukan review eksplisit dan dicatat. Bila tim menghendaki jaminan
  lebih kuat, pertimbangkan pembatasan kind on-chain di fase mendatang
  (perubahan desain tersendiri, bukan bagian dari kebijakan threshold).
- **R-9-WS1-2 — PH7-L04 tetap relevan.** Perilaku validator yang berubah
  pasca-approval adalah jalur serangan OnChain yang nyata (§2.3);
  pencatatan codehash + SOP approval yang tertunda itu adalah mitigasi
  yang benar — bukan threshold.
- **R-9-WS1-3 — Jangan ulangi pola ini.** Bila kebijakan baru ditambahkan
  ke `createQuest`, uji dulu dengan pertanyaan: "pihak ketiga mana yang
  diikat parameter ini di jalur completion?" Bila jawabannya "tidak ada",
  itu bukan kontrol keamanan.

---

## 8. Perubahan file

Tidak ada file kode yang berubah. Satu-satunya artefak workstream ini
adalah dokumen ini:
`agenthub-phase9-readiness/workstreams/01-reward-policy-review.md`.
Tidak ada commit yang dibuat (koordinator yang memutuskan commit/push
artefak Phase 9). Tidak ada deploy, broadcast, atau private key yang
digunakan. Tidak ada test yang dihapus/dilemahkan; tidak ada regresi
yang perlu dijalankan karena tidak ada kode yang berubah (baseline
Phase 8: Foundry 321/321, fuzz 10k seed 42, gas T1 244.840 / T2 255.766 /
T3 266.911 — semuanya tetap berlaku apa adanya).
