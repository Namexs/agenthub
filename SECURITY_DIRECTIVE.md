# AGENTHUB — ADVANCED SECURITY ENGINEERING DIRECTIVE

User order 2026-11-19 ~13:00 WIB. Role: principal smart contract security
engineer, offensive security researcher, Solidity auditor, blockchain protocol
security architect.

## Mission

Upgrade AGENTHUB from basic security testing to production-grade security
engineering. Discover, reproduce, document, and eliminate vulnerabilities
before deployment. Do not merely confirm that the code compiles.
Security is more important than feature completeness.

## 1. Threat model

Threats: malicious users, compromised admin accounts, malicious external
contracts, fake identity contracts, replayed signatures, transaction ordering
attacks, economic manipulation, denial of service, dependency compromise,
frontend/backend trust assumptions. Complete threat model with attack trees.

## 2. Static analysis

Integrate: Slither, Solidity compiler warnings, Foundry static checks,
dependency security scanning. Review every finding manually.

## 3. Advanced testing

Unit, integration, fuzz, stateful invariant, differential (where applicable),
adversarial contract, access-control, reentrancy, replay protection, economic
attack simulations. Never weaken assertions to pass tests.

## 4. Contract security

- **AgentGate:** verify trusted Agent ID contract; validate chain config;
  reject fake identity contracts; handle external contract failures safely.
- **QuestManager:** prevent duplicate completion; prevent unauthorized quest
  creation; protect reward/completion accounting; prevent malicious callback
  interactions; validate completion proofs.
- **Reputation:** prevent unauthorized score changes; prevent replayed
  completion events; prevent duplicate reward accounting; only authorized
  validated events affect reputation.
- **Achievement:** prevent unauthorized issuance; enforce non-transferability;
  prevent duplicate issuance; protect privileged admin functions.

## 5. Privilege and admin security

Least privilege, role separation, multisig administration for critical ops,
timelock for sensitive config changes, emergency pause + controlled recovery,
immutable trusted identity config where practical. Document all trust assumptions.

## 6. Attack simulation

Malicious test contracts simulating: reentrancy, malicious ERC721 behavior,
malicious external callbacks, unauthorized admin calls, replay attempts,
invalid signatures, duplicate quest claims, malformed external responses,
unexpected revert behavior, gas exhaustion. Isolated local env + testnet only.

## 7. Security gates (before deployment)

- Zero unresolved Critical findings.
- Zero unresolved High findings.
- Medium findings fixed or documented mitigations.
- All tests pass. Invariants hold. Static analysis findings reviewed.
- No exposed secrets. No unverified external dependencies.

## 8. Reporting (docs/)

- SECURITY_THREAT_MODEL.md
- SECURITY_TEST_PLAN.md
- SECURITY_FINDINGS.md
- SECURITY_REMEDIATION.md
- SECURITY_DEPLOYMENT_GATE.md

Every finding: unique ID, severity, affected contract + function, root cause,
reproducible PoC, impact, exploit prerequisites, recommended remediation,
regression test, verification status.

Never invent findings or claim an audit passed without evidence.

## 9. Rules

- Do NOT deploy mainnet. Do NOT access real user funds.
- Do NOT execute attacks against third-party systems.
- Local test environments and authorized BNB testnet only.
- **Do NOT begin implementation until the existing architecture and interfaces
  have been reviewed.**

## 10. Paket hasil audit untuk reviewer eksternal (user, 2026-11-19 ~13:02 WIB)

Setelah seluruh proses security audit selesai, jangan hanya berikan kesimpulan.
Siapkan paket hasil audit dalam satu folder: `security-review-package/`
(di repo root). Isi: seluruh laporan, bukti pengujian, dan daftar perubahan.

WAJIB:

1. Seluruh laporan audit dalam file Markdown.
2. Bukti perintah pengujian + hasil aktualnya (log perintah).
3. Nama file, fungsi, dan baris kode untuk setiap temuan.
4. Skenario eksploitasi secara teknis + dampaknya.
5. Pisahkan temuan yang sudah diperbaiki dan yang belum diperbaiki.
6. Kode sebelum dan sesudah perbaikan untuk setiap vulnerability yang diperbaiki.
7. Jangan klaim pengujian berhasil jika belum benar-benar dijalankan.
8. Jangan sembunyikan hasil pengujian yang gagal.
9. Jangan buat/tambah vulnerability palsu demi mendapatkan Critical Findings.
10. Jangan deploy mainnet atau pakai dana sungguhan.

Ringkasan akhir paket:

- Jumlah Critical, High, Medium, Low.
- Jumlah temuan yang sudah diperbaiki.
- Jumlah temuan yang masih terbuka.
- Pengujian yang berhasil dan gagal.
- Risiko yang belum dapat diuji.
- Rekomendasi apakah proyek boleh lanjut ke tahap berikutnya.

Seluruh hasil harus dapat diverifikasi dari kode dan log pengujian.
