# AGENTHUB — Phase 9.1, Workstream Dokumen: Constructor Arguments & Verifikasi BscScan

**Menutup temuan:** PH7-L22 — "Verifikasi BscScan manual kekurangan
constructor args per kontrak" (`agenthub-phase7-review/
PHASE7_INDEPENDENT_SECURITY_REVIEW.md` §PH7-L22, sumber 08/L-09).
**Tanggal:** 20 November 2026.
**Repo HEAD:** `81947ce` (`chore(phase-9): regenerate PACKAGE_MANIFEST.md
for final commit`).
**Target:** BNB Testnet, chain 97.
**Ruang lingkup:** dokumen saja — tidak ada perubahan kode, tidak ada
deployment, tidak ada broadcast.

> **⚠️ PRIVATE KEY TIDAK PERNAH DIKIRIM KE CHAT, LAPORAN, ATAU REPO.**
> Dokumen ini tidak memuat dan tidak membutuhkan private key apa pun.
> Semua alamat yang belum ada ditandai **TBD** — jangan isi dengan
> tebakan.

## 0. Ringkasan

PH7-L22 mencatat jalur verifikasi otomatis sudah benar
(`foundry.toml`, `--verifier etherscan` + `--chain 97`), tetapi jalur
manual kekurangan satu hal: **tidak ada daftar constructor args per
kontrak di dokumen mana pun**. Dokumen ini menutup celah itu:

1. Urutan deploy nyata, diverifikasi terhadap deploy script (§1).
2. Setelan kompilasi yang harus identik saat verifikasi (§2).
3. Tabel constructor args untuk keenam kontrak (§3).
4. Per kontrak: signature dari source aktual, nilai argumen yang
   dipakai deploy script, template encoding, dan perintah
   `forge verify-contract` lengkap (§4).
5. Sumber otoritatif nilai args pasca-deploy (§5) dan cara
   verifikasi manual — CLI maupun form web BscScan (§6).
6. Daftar nilai TBD dan alasannya (§7).

Semua signature di bawah ini dibaca dari source di
`packages/contracts/src/` dan dicocokkan dengan ABI hasil kompilasi
di `packages/contracts/out/` (HEAD `81947ce`) — keduanya identik.
Nilai argumen dibaca dari `packages/contracts/script/
DeployAgentHub.s.sol`. Tidak ada nilai yang dikarang.

## 1. Urutan deploy — terverifikasi terhadap deploy script

Urutan yang dipakai dokumen ini adalah urutan nyata
`DeployAgentHub.deploy()` (`script/DeployAgentHub.s.sol`, langkah 1–5
di `deploy()`), **bukan** singkatan lama "AgentGate → QuestManager →
Reputation → Achievement" (singkatan itu tidak dapat di-deploy —
QuestManager butuh alamat ketiga kontrak lain di constructornya;
koreksi ini sudah dicatat Phase 9 WS4).

| #   | Kontrak            | Langkah di `DeployAgentHub.s.sol`                                                           | Bergantung pada    |
| --- | ------------------ | ------------------------------------------------------------------------------------------- | ------------------ |
| 1   | MockAgentId        | §1 — `new MockAgentId()` bila `AGENT_ID_ADDRESS` unset                                      | —                  |
| 2   | AgentGate          | §2 — `new AgentGate(agentId, block.chainid)`                                                | #1 (alamat mock)   |
| 3   | TimelockController | §3 — `new TimelockController(TIMELOCK_DELAY, proposers, executors, address(0))`             | — (hanya env)      |
| 4   | Reputation         | §4 — `new Reputation(deployer)`                                                             | — (hanya deployer) |
| 5   | Achievement        | §4 — `new Achievement(deployer)`                                                            | — (hanya deployer) |
| 6   | QuestManager       | §5 — `new QuestManager(address(gate), address(reputation), address(achievement), deployer)` | #2, #4, #5         |

Total: **6 CREATE + 12 wiring CALL** (13 bila `VERIFIER` di-set).
Urutan ini dikonfirmasi juga oleh fork dry-run Phase 9 WS4
(8.307.890 gas, dua run identik) dan `docs/DEPLOYMENT.md` §4.

**Catatan tentang `DeployMock.s.sol`:** script itu adalah deployer
standalone untuk MockAgentId (dipakai bila mock perlu di-deploy
terpisah, mis. untuk pengujian lokal). Dalam alur deployment-day
yang sebenarnya, MockAgentId di-deploy **oleh `DeployAgentHub`
sendiri** sebagai CREATE pertama — tidak ada langkah terpisah.
Constructor-nya sama di kedua jalur: `MockAgentId()` tanpa argumen.

**Catatan mainnet (di luar ruang lingkup dokumen ini):** di chain 56
tidak ada mock — `AgentGate` menerima alamat Agent ID resmi
`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` dan deploy script
menolak nilai lain. Mainnet adalah NO-GO sampai gate §7 checklist
terpenuhi; dokumen ini hanya membahas testnet chain 97.

## 2. Setelan kompilasi — HARUS identik saat verifikasi

Verifikasi BscScan mengulang kompilasi dari source + metadata.
Satu setelan berbeda → "bytecode mismatch". Setelan deployment
(dari `packages/contracts/foundry.toml`, HEAD `81947ce`):

| Setelan       | Nilai                                | Sumber                                                                                                  |
| ------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| solc          | **0.8.39**                           | `foundry.toml` `solc_version` (naik dari 0.8.24 di Phase 8, PH7-L13)                                    |
| Pragma source | `^0.8.24` (semua kontrak app + mock) | `src/*.sol` baris 2                                                                                     |
| via-IR        | **true — WAJIB**                     | `foundry.toml` `via_ir = true` (Phase 6, R-010)                                                         |
| Optimizer     | enabled, **200 runs**                | `foundry.toml` `optimizer = true`, `optimizer_runs = 200`                                               |
| EVM version   | **cancun**                           | `foundry.toml` `evm_version = "cancun"` (dependensi nyata: MCOPY 1× di QuestManager, 1× di Achievement) |
| OpenZeppelin  | **5.0.2**                            | `lib/openzeppelin-contracts/package.json`                                                               |
| License       | MIT                                  | `SPDX-License-Identifier: MIT` di semua source                                                          |

> **⚠️ Verifikasi dari checkout yang sama.** Jalankan
> `forge verify-contract` dari checkout repo yang sama dengan yang
> dipakai deploy (HEAD `81947ce`, working tree bersih,
> `git log -1 --oneline` menunjukkan `81947ce`). Verifikasi dari
> checkout lain dengan `foundry.toml` berbeda gagal dengan
> "bytecode mismatch" — ini adalah catatan via-IR di PH7-L22
> sendiri. Bila ragu, verifikasi ulang dengan
> `forge build` dan bandingkan bytecode dengan artefak `out/`.

## 3. Tabel ringkas constructor args

`<...>` = placeholder — isi dengan nilai deployment-day yang
sebenarnya (lihat §5). Nilai yang sudah pasti dari source dicetak
tebal.

| #   | Kontrak            | Constructor signature                                                                    | Argumen yang dipakai deploy script                                                                                                                                                                                 |
| --- | ------------------ | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | MockAgentId        | `constructor()`                                                                          | — (tidak ada argumen)                                                                                                                                                                                              |
| 2   | AgentGate          | `constructor(address agentId_, uint256 expectedChainId_)`                                | `agentId_` = `<MOCK_AGENT_ID>` (TBD, alamat CREATE #1); `expectedChainId_` = **97**                                                                                                                                |
| 3   | TimelockController | `constructor(uint256 minDelay, address[] proposers, address[] executors, address admin)` | `minDelay` = **172800** (2 hari, `TIMELOCK_DELAY`); `proposers` = `[<ADMIN_MULTISIG>]` (TBD, input user); `executors` = `[<ADMIN_MULTISIG>]` (TBD, sama); `admin` = **0x0000000000000000000000000000000000000000** |
| 4   | Reputation         | `constructor(address admin_)`                                                            | `admin_` = `<DEPLOYER>` (TBD, alamat deployer; admin sementara — di-renounce pasca-deploy, admin akhir = timelock)                                                                                                 |
| 5   | Achievement        | `constructor(address admin_)`                                                            | `admin_` = `<DEPLOYER>` (TBD, sama)                                                                                                                                                                                |
| 6   | QuestManager       | `constructor(address gate_, address reputation_, address achievement_, address admin_)`  | `gate_` = `<AGENT_GATE>` (TBD, alamat CREATE #2); `reputation_` = `<REPUTATION>` (TBD, alamat CREATE #4); `achievement_` = `<ACHIEVEMENT>` (TBD, alamat CREATE #5); `admin_` = `<DEPLOYER>` (TBD, sama)            |

Tidak ada constructor arg lain: role-role operasional
(`QUEST_CREATOR_ROLE`, `PAUSER_ROLE`, `VERIFIER_ROLE`,
`SCORE_SOURCE_ROLE`, `ISSUER_ROLE`, `BADGE_MANAGER_ROLE`) diberikan
lewat wiring CALL pasca-deploy, bukan lewat constructor — jadi
alamat Safe creator, pauser, dan verifier **tidak muncul** di
constructor args mana pun.

## 4. Per kontrak

Konvensi: perintah di bawah memakai placeholder `<...>` dan
dijalankan dari `packages/contracts/`. Template perintah `cast
abi-encode` di bawah sudah divalidasi sintaksnya dengan `cast`
lokal (20 Nov 2026, nilai placeholder) — tetapi **nilai encoding
yang dicetak di sini hanya template**; encoding sebenarnya baru ada
setelah alamat deployment-day diketahui (lihat §5).

### 4.1 MockAgentId — `src/mocks/MockAgentId.sol:19`

```solidity
constructor() ERC721("Mock Agent ID", "MOCKAI") Ownable(msg.sender) {}
```

- **Argumen:** tidak ada. Encoding constructor args: kosong
  (byte string kosong).
- **Nilai dari deploy script:** tidak ada — `new MockAgentId()`
  (`DeployAgentHub.s.sol` §1; juga `DeployMock.s.sol`).
- **Verifikasi:**
  ```bash
  forge verify-contract <MOCK_AGENT_ID> src/mocks/MockAgentId.sol:MockAgentId \
    --chain 97 --verifier etherscan
  ```
  Tanpa flag `--constructor-args` (tidak ada argumen).

### 4.2 AgentGate — `src/AgentGate.sol:37`

```solidity
constructor(address agentId_, uint256 expectedChainId_)
```

| Argumen            | Nilai deployment-day        | Asal nilai                                                                                                                                                                  |
| ------------------ | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agentId_`         | `<MOCK_AGENT_ID>` — **TBD** | Alamat MockAgentId hasil CREATE #1 (`DeployAgentHub.s.sol` §2: `new AgentGate(agentId, block.chainid)`; `agentId` = alamat mock karena `AGENT_ID_ADDRESS` unset di testnet) |
| `expectedChainId_` | **97**                      | `block.chainid` di testnet; constructor menolak nilai ≠ chain aktif (`WrongChain`) dan menolak chain di luar {56, 97, 31337}                                                |

- **Encoding:**
  ```bash
  cast abi-encode "constructor(address,uint256)" <MOCK_AGENT_ID> 97
  ```
  Bentuk encoding: 32 byte alamat (left-padded) + 32 byte nilai
  `0x61` (97).
- **Verifikasi:**
  ```bash
  forge verify-contract <AGENT_GATE> src/AgentGate.sol:AgentGate \
    --chain 97 --verifier etherscan \
    --constructor-args $(cast abi-encode "constructor(address,uint256)" <MOCK_AGENT_ID> 97)
  ```

### 4.3 TimelockController — OpenZeppelin 5.0.2, `lib/openzeppelin-contracts/contracts/governance/TimelockController.sol:115`

```solidity
constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
```

| Argumen     | Nilai deployment-day                           | Asal nilai                                                                                                                                                |
| ----------- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `minDelay`  | **172800** (2 hari)                            | `TIMELOCK_DELAY = 2 days` (`DeployAgentHub.s.sol`); diverifikasi pasca-deploy lewat `getMinDelay()`                                                       |
| `proposers` | `[<ADMIN_MULTISIG>]` — **TBD**                 | `ADMIN_MULTISIG` dari env (input user §1 item 3 checklist); array 1 elemen                                                                                |
| `executors` | `[<ADMIN_MULTISIG>]` — **TBD**                 | Sama — array 1 elemen, alamat yang sama                                                                                                                   |
| `admin`     | **0x0000000000000000000000000000000000000000** | `address(0)` — sengaja: tidak ada optional admin; timelock mengadministrasi dirinya sendiri (per panduan OZ; `DEFAULT_ADMIN_ROLE` milik timelock sendiri) |

- **Encoding:**
  ```bash
  cast abi-encode "constructor(uint256,address[],address[],address)" \
    172800 "[<ADMIN_MULTISIG>]" "[<ADMIN_MULTISIG>]" 0x0000000000000000000000000000000000000000
  ```
- **Verifikasi** (path source OZ — verifikasi dari checkout yang
  sama agar remapping `@openzeppelin/` terpecahkan):
  ```bash
  forge verify-contract <TIMELOCK> lib/openzeppelin-contracts/contracts/governance/TimelockController.sol:TimelockController \
    --chain 97 --verifier etherscan \
    --constructor-args $(cast abi-encode "constructor(uint256,address[],address[],address)" \
      172800 "[<ADMIN_MULTISIG>]" "[<ADMIN_MULTISIG>]" 0x0000000000000000000000000000000000000000)
  ```
  Alternatif: `forge verify-contract <TIMELOCK>
TimelockController --chain 97 ...` bila nama kontrak tidak ambigu
  di proyek.

### 4.4 Reputation — `src/Reputation.sol:36`

```solidity
constructor(address admin_)
```

| Argumen  | Nilai deployment-day   | Asal nilai                                                                                                                                                                                                                                                                              |
| -------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `admin_` | `<DEPLOYER>` — **TBD** | Alamat deployer, diturunkan dari `DEPLOYER_PRIVATE_KEY` (`vm.addr(deployerKey)`). Admin **sementara**: pasca-deploy admin diberikan ke timelock dan deployer me-renounce (`DeployAgentHub.s.sol` §7) — jadi alamat ini hanya tercatat di creation args, bukan pemegang privilege akhir. |

- **Encoding:**
  ```bash
  cast abi-encode "constructor(address)" <DEPLOYER>
  ```
- **Verifikasi:**
  ```bash
  forge verify-contract <REPUTATION> src/Reputation.sol:Reputation \
    --chain 97 --verifier etherscan \
    --constructor-args $(cast abi-encode "constructor(address)" <DEPLOYER>)
  ```

### 4.5 Achievement — `src/Achievement.sol:42`

```solidity
constructor(address admin_) ERC721("AGENTHUB Achievement", "AGH-ACH")
```

| Argumen  | Nilai deployment-day   | Asal nilai                                                                                                                                                                                               |
| -------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `admin_` | `<DEPLOYER>` — **TBD** | Sama seperti Reputation: alamat deployer, admin sementara, di-renounce pasca-deploy. Nama/symbol ERC-721 (`"AGENTHUB Achievement"`, `"AGH-ACH"`) adalah konstanta di source, **bukan** constructor args. |

- **Encoding:**
  ```bash
  cast abi-encode "constructor(address)" <DEPLOYER>
  ```
- **Verifikasi:**
  ```bash
  forge verify-contract <ACHIEVEMENT> src/Achievement.sol:Achievement \
    --chain 97 --verifier etherscan \
    --constructor-args $(cast abi-encode "constructor(address)" <DEPLOYER>)
  ```

### 4.6 QuestManager — `src/QuestManager.sol:138`

```solidity
constructor(address gate_, address reputation_, address achievement_, address admin_)
    EIP712("AGENTHUB QuestManager", "1")
```

| Argumen        | Nilai deployment-day      | Asal nilai                                                                                                                                                                 |
| -------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gate_`        | `<AGENT_GATE>` — **TBD**  | Alamat AgentGate hasil CREATE #2                                                                                                                                           |
| `reputation_`  | `<REPUTATION>` — **TBD**  | Alamat Reputation hasil CREATE #4                                                                                                                                          |
| `achievement_` | `<ACHIEVEMENT>` — **TBD** | Alamat Achievement hasil CREATE #5                                                                                                                                         |
| `admin_`       | `<DEPLOYER>` — **TBD**    | Alamat deployer, admin sementara, di-renounce pasca-deploy. Nama/domain EIP-712 (`"AGENTHUB QuestManager"`, `"1"`) adalah konstanta di source, **bukan** constructor args. |

Constructor menolak dependensi yang bukan kontrak
(`NoCodeAtDependency`) — inilah alasan QuestManager di-deploy
terakhir.

- **Encoding:**
  ```bash
  cast abi-encode "constructor(address,address,address,address)" \
    <AGENT_GATE> <REPUTATION> <ACHIEVEMENT> <DEPLOYER>
  ```
- **Verifikasi:**
  ```bash
  forge verify-contract <QUEST_MANAGER> src/QuestManager.sol:QuestManager \
    --chain 97 --verifier etherscan \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address)" \
      <AGENT_GATE> <REPUTATION> <ACHIEVEMENT> <DEPLOYER>)
  ```

## 5. Sumber otoritatif nilai args pasca-deploy

Setelah broadcast, **jangan mengetik ulang args dari ingatan**.
Sumber kebenaran, berurutan:

1. **Broadcast JSON** (utama): `packages/contracts/broadcast/
DeployAgentHub.s.sol/97/run-latest.json`, field
   `transactions[].arguments` per CREATE — inilah args yang
   benar-benar dipakai on-chain. (Sudah dicatat di Phase 9 WS4
   langkah S1.4.)
2. **Deployment record** `docs/DEPLOYMENT_RECORD.md` (dibuat saat
   deployment-day) — salinan alamat + tx hash.
3. **Derivasi ulang dengan `cast abi-encode`** memakai alamat dari
   (1)/(2) — berguna sebagai cross-check; hasilnya harus identik
   dengan `arguments` di broadcast JSON.

Bila (1) dan (3) berbeda, percayai (1) dan selidiki perbedaannya
sebelum verifikasi — args yang salah menghasilkan "bytecode
mismatch" meskipun source-nya benar.

## 6. Cara verifikasi BscScan testnet

### 6.1 Jalur utama — otomatis saat broadcast (sudah benar)

```bash
forge script script/DeployAgentHub.s.sol --fork-url $BSC_TESTNET_RPC_URL \
  --broadcast --verify
```

`--verify` memverifikasi keenam kontrak sekaligus memakai args
dari broadcast. Jalur ini sudah benar sejak Phase H (PH7-L22
mengonfirmasi) — dokumen ini hanya menutup jalur manual di bawah.

### 6.2 Jalur manual — `forge verify-contract` (per kontrak)

Gunakan perintah di §4 per kontrak yang gagal terverifikasi
otomatis. Catatan (terverifikasi 2026-11-19, `docs/DEPLOYMENT.md`
§5):

- Verifier adalah `etherscan` — BscScan kompatibel Etherscan.
  `--verifier bscscan` **bukan** nilai foundry yang valid dan
  langsung gagal.
- `--chain 97` memecahkan URL API BscScan testnet dari konfigurasi
  bawaan foundry; tidak perlu `--verifier-url`.
- API key berasal dari `BSCSCAN_API_KEY` lewat pemetaan
  `[etherscan]` di `foundry.toml` (`bsc-testnet = { key =
"${BSCSCAN_API_KEY}" }`). Foundry TIDAK membaca `BSCSCAN_API_KEY`
  sendiri — tanpa pemetaan itu verifikasi gagal dengan
  "ETHERSCAN_API_KEY must be set". Alternatif: export
  `ETHERSCAN_API_KEY=$BSCSCAN_API_KEY` atau flag
  `--etherscan-api-key "$BSCSCAN_API_KEY"`.
- Key dimasukkan lewat env dari secret manager — **tidak pernah di
  chat, tidak pernah di repo, tidak pernah di command line terminal
  bersama**.
- Jalankan dari `packages/contracts/` di checkout yang sama dengan
  deploy (§2).

### 6.3 Jalur manual — form web BscScan testnet

Bila CLI tidak dapat dipakai, verifikasi lewat form web di
testnet.bscscan.com (alamat kontrak → tab Contract → Verify and
Publish). **Karena build memakai `viaIR: true`, form single-file
tidak cukup** — setelan lanjutan seperti `viaIR` hanya dapat
diakses lewat metode **Solidity (Standard-JSON-Input)**
(dokumentasi BscScan: "advanced settings (e.g. bytecodeHash:
'none' or viaIR: 'true') can be accessed via Solidity
(Standard-Json-Input) verification method"). Langkahnya:

1. Hasilkan Standard JSON Input dari checkout yang sama:
   ```bash
   forge verify-contract <ALAMAT> <Kontrak> --chain 97 \
     --show-standard-json-input > /tmp/<kontrak>-standard-json.json
   ```
   (Flag ini hanya mencetak JSON — tidak mengirim apa pun.)
2. Di form BscScan pilih **Solidity (Standard-JSON-Input)**,
   tempel isi file JSON tersebut.
3. Compiler version: **v0.8.39** (pilih versi persis yang dipakai
   build; setelan lain — optimizer 200, cancun, via-IR — sudah
   terkandung di dalam JSON).
4. License: **MIT**.
5. Constructor Arguments: tempel hasil `cast abi-encode` dari §4
   **tanpa prefix `0x`**. Untuk MockAgentId kolom ini dikosongkan.
6. Submit dan tunggu hasil kompilasi; "bytecode mismatch" berarti
   setelan atau args tidak cocok — periksa kembali §2 dan §5,
   jangan mengubah source untuk "memaksa cocok".

Catatan: BscScan dapat menampilkan "Similar Match" untuk kontrak
yang bytecode-nya cocok dengan kontrak terverifikasi lain — itu
**bukan** verifikasi penuh (constructor args tidak dikonfirmasi).
Keenam kontrak AGENTHUB harus mencapai verifikasi penuh
masing-masing (target checklist: 6/6).

## 7. Nilai TBD — daftar lengkap

| Nilai                            | Alasan TBD                                                                                              | Kapan diketahui                                                                     |
| -------------------------------- | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `<MOCK_AGENT_ID>`                | Alamat hasil CREATE #1 — baru ada setelah broadcast                                                     | Deployment-day, dari output script / broadcast JSON                                 |
| `<AGENT_GATE>`                   | Alamat hasil CREATE #2                                                                                  | Sama                                                                                |
| `<TIMELOCK>`                     | Alamat hasil CREATE #3                                                                                  | Sama                                                                                |
| `<REPUTATION>`                   | Alamat hasil CREATE #4                                                                                  | Sama                                                                                |
| `<ACHIEVEMENT>`                  | Alamat hasil CREATE #5                                                                                  | Sama                                                                                |
| `<QUEST_MANAGER>`                | Alamat hasil CREATE #6                                                                                  | Sama                                                                                |
| `<DEPLOYER>`                     | Alamat deployer — diturunkan dari deployer key user, yang **tidak pernah** dikirim ke Asta/chat/laporan | User memberitahu ALAMATNYA (publik) saat mendanai deployer; key tetap di mesin user |
| `<ADMIN_MULTISIG>`               | Alamat Safe admin — input user checklist §1 item 3, belum diterima                                      | User membuat Safe testnet lalu mengirim alamatnya                                   |
| Encoding ABI lengkap per kontrak | Semua encoding bergantung pada ≥1 nilai TBD di atas (kecuali MockAgentId yang kosong)                   | Setelah nilai-nilai di atas diketahui — derivasi dengan perintah §4                 |

Nilai yang **sudah pasti** dari source dan tidak TBD:
`expectedChainId_ = 97`, `minDelay = 172800`,
`admin` Timelock = `0x000…0`, dan semua nama/symbol/domain
konstanta (bukan constructor args).

## 8. Penutup PH7-L22

| Yang diminta rekomendasi L22                                                       | Status di dokumen ini                                                                                |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Tabel constructor args per kontrak                                                 | §3 (ringkas) + §4 (per kontrak, dengan sumber baris source)                                          |
| Perintah `forge verify-contract` lengkap per kontrak                               | §4.1–§4.6 (template dengan placeholder TBD) + §6.2 (catatan verifier/key)                            |
| Peringatan verifikasi harus dari checkout yang sama                                | §2 (kotak peringatan) + §6.2                                                                         |
| Koreksi: L22 menyebut solc 0.8.24 — sejak Phase 8 solc adalah **0.8.39** (PH7-L13) | §2 memakai 0.8.39; angka 0.8.24 di laporan Phase 7 sudah kedaluwarsa untuk verifikasi build saat ini |

**Status: PH7-L22 DITUTUP** — dokumen ini adalah artefak
penutupnya. Sisa pekerjaan adalah operasional, bukan dokumentasi:
isi placeholder TBD saat deployment-day (§7) dan verifikasi 6/6
kontrak (checklist §4.2 langkah 7).

---

_Sumber utama: `packages/contracts/script/DeployAgentHub.s.sol`,
`packages/contracts/script/DeployMock.s.sol`,
`packages/contracts/src/{AgentGate,Reputation,Achievement,
QuestManager}.sol`, `packages/contracts/src/mocks/MockAgentId.sol`,
`packages/contracts/lib/openzeppelin-contracts/contracts/governance/
TimelockController.sol` (v5.0.2), `packages/contracts/foundry.toml`,
`packages/contracts/out/*/abi` (cross-check constructor),
`docs/DEPLOYMENT.md` §4–§5, Phase 9 WS4
(`agenthub-phase9-readiness/workstreams/
04-live-testnet-test-plan.md` langkah S1), BscScan Information
Center "Verifying Contracts" (Standard-JSON-Input untuk viaIR)._
