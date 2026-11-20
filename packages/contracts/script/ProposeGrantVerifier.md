# ProposeGrantVerifier — grant verifier kedua via timelock

Script: `script/ProposeGrantVerifier.s.sol` (PH7-L19).

Menyiapkan proposal grant `VERIFIER_ROLE` ke verifier kedua (atau ketiga)
pada `QuestManager` **melalui `TimelockController`**. R-010 mensyaratkan
≥ 3 verifier sebelum quest threshold-2 pertama di mainnet; script ini
adalah cara menambah verifier tanpa merakit calldata manual.

**Tidak ada jalur direct-grant.** Script tidak pernah memanggil
`QuestManager.grantRole` secara langsung — calldata grant hanya dieksekusi
oleh timelock itu sendiri (satu-satunya pemegang `DEFAULT_ADMIN_ROLE` di
`QuestManager`). Siapa pun yang mencoba grant langsung akan revert
(`AccessControlUnauthorizedAccount`).

## Alur: propose → schedule → delay → execute

| Langkah | Siapa | Apa |
|---|---|---|
| 1. Propose (preview) | Operator | Jalankan script tanpa `--broadcast`: script memvalidasi state live (timelock adalah admin QM, verifier belum punya role, `minDelay` timelock persis 2 hari) lalu mencetak ringkasan: target, calldata, salt, operation id, dan waktu siap eksekusi. |
| 2. Schedule | Admin multisig (Safe) | Safe mengeksekusi `timelock.schedule(target, 0, calldata, 0x0, salt, 172800)` sebagai transaksi Safe, memakai argumen persis dari ringkasan. Hanya pemegang `PROPOSER_ROLE` (multisig) yang bisa schedule; yang lain revert. |
| 3. Delay | — | 2 hari (`minDelay` timelock). Selama jendela ini grant **belum efektif**: `execute()` revert, dan multisig masih bisa membatalkan via `CANCELLER_ROLE` (`timelock.cancel(operationId)`). |
| 4. Execute | Admin multisig (Safe) | Setelah delay, Safe mengeksekusi `timelock.execute(target, 0, calldata, 0x0, salt)`. Grant mendarat; verifikasi dengan `cast call <QM> "hasRole(bytes32,address)" <VERIFIER_ROLE> <verifier>` (atau `forge script` cek). |

Catatan penting: proposer adalah Safe — Safe tidak punya private key,
jadi script **tidak bisa** broadcast schedule sebagai Safe di jaringan
live. Karena itu `run()` default-nya preview-only. Opsi
`SCHEDULE=true` + `PROPOSER_PRIVATE_KEY` hanya untuk setup yang
proposer-nya EOA, atau simulasi fork dengan proposer yang di-unlock;
timelock sendiri akan revert bila key tersebut bukan proposer.

## Perintah

```bash
# 1. Preview (tidak mengirim apa pun; butuh RPC untuk membaca state live)
TIMELOCK_ADDRESS=<0x..> QUEST_MANAGER_ADDRESS=<0x..> VERIFIER=<0x..> \
  forge script script/ProposeGrantVerifier.s.sol --rpc-url <url>

# 2. Schedule via transaksi Safe dengan argumen dari ringkasan
#    (Safe UI: New transaction -> Contract interaction -> TimelockController.schedule)

# 3. Tunggu 2 hari (atau sampai waktu "Ready at" di ringkasan)

# 4. Execute via transaksi Safe: TimelockController.execute dengan argumen yang sama
```

Salt default diturunkan deterministik dari alamat verifier
(`keccak256("agenthub-grant-verifier" || verifier)`), jadi preview yang
diulang untuk verifier yang sama menghasilkan operation id yang sama.
Override bila perlu: `PROPOSAL_SALT=<bytes32>`.

## Verifikasi

Test: `test/ProposeGrantVerifier.t.sol` — membuktikan proposal terjadwal
dengan benar, grant tidak efektif sebelum delay (execute revert), grant
mendarat setelah delay + execute, non-proposer tidak bisa schedule,
grant langsung revert, dan cancel sebelum execute menggagalkan grant.
