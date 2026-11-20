# AGENTHUB — Known Limitations + Open Findings

> **Sources.** Phase 8 report §3 (still-open findings) and §10
> (limitations); Phase 7 report §10 (limitations) and §11 (pre-mainnet
> list); `docs/SECURITY_THREAT_MODEL.md` §6 (accepted risks). This file
> states plainly what the audit package does NOT claim, so the external
> auditor starts from an honest baseline.

## 1. What this package does NOT claim

1. **No external audit has been performed.** The Phase 7 review and
   Phase 8 remediation were done by agents in the same environment as
   the implementation. R-012 (commissioned external security review)
   is still open — this package exists to enable it, not to replace it.
2. **No live-chain testing has happened.** All evidence is Foundry
   local, Anvil, and dry forks. Behaviour on BSC testnet — including
   interaction with a real Safe, the 2-day timelock, and public RPCs —
   is unproven. That is the function of the testnet smoke test.
3. **Green tests are not proof of security.** 321 tests + fuzz + E2E
   prove the code behaves per the tested specification — not that the
   specification is complete or that no bug class exists outside test
   coverage.
4. **Untested trust assumptions:** honesty of admin/timelock and the
   creator multisig, security of verifier keys, correctness of the
   official Agent ID contract, and security of OpenZeppelin
   dependencies. (Slither findings in `lib/` — 1 High + 8 Medium in
   Phase 7 — are OpenZeppelin code, out of scope, noted only.)
5. **solc 0.8.39 was 1 day old at evaluation** (released 19 Nov 2026).
   Full validation was re-run on it, but exposure to undiscovered
   compiler bugs is in principle higher than for a long-circulating
   release.
6. **Local JS verification ran on a stale tree** (Next 14.2.35 +
   React 18.3.1 installed vs Next 15.5.29 + React 19.3.1 pinned).
   Authority for the pinned tree is CI (10/10 green), not the local
   battery.
7. **Scope of prior review:** Phase 7 focused on the Phase 6 diff and
   its interactions. A full from-scratch audit of all four contracts,
   a full frontend audit, and a JS dependency audit beyond OSV were
   not part of it. Phase 8 closed only the P0/P1 findings in its
   defined scope.

## 2. Open findings (from Phase 8 §3)

No High or Medium finding is fully open. The open items are Low/Info
findings deliberately deferred (out of Phase 8 scope) or
procedural/operational items needing human decisions, external review,
or a live chain. Full per-finding detail: `FINDINGS.md`.

### 2.1 Procedural / decision items (need a human decision before mainnet)

| Item                                    | What is open                                                                                                                                                                                                                                             |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **PH7-M03 (procedural part)**           | Review window / two-step flow for high-value quests undecided. The code part (creator must be a validated Safe) is CLOSED. The team must decide: accept the risk with deactivate+pause as the remedy, or implement a review window before mainnet.       |
| **PH7-L01 (accepted)**                  | No on-chain cap on TOTAL reputation one creator can issue (cap is per-quest only). Accepted with evidence (trusted creator role + spike monitoring + deactivate/pause) — but there is no on-chain cap. The auditor should pressure-test this acceptance. |
| **PH7-L08 / PH7-I07 (design decision)** | Threshold is stored but not enforced for non-Attested quests — an explicit Phase 8 design decision (policy only meaningful for Attested). Tested and documented; the auditor may disagree with the decision.                                             |
| **PH7-L06**                             | Global per-account nonce (attestations go stale across quests). Documented UX limitation; per-quest nonce is a deferred design change.                                                                                                                   |

### 2.2 Open Low findings (documentation / SOP / tooling)

| ID                               | What is open                                                                                                                                          |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| PH7-L02                          | Asymmetric pause coupling — runbook documentation not written (behaviour proven correct).                                                             |
| PH7-L03                          | Grant-side TOCTOU — SOP mitigation (7-day re-grant pause) not written into the SOP.                                                                   |
| PH7-L04                          | Validator behaviour change post-approval — SOP approval + codehash logging not applied.                                                               |
| PH7-L09                          | No quest-creation UI — no human defence layer; fail-closed checks on the team's creation script not added.                                            |
| PH7-L11                          | `anvil-integration.mjs` reads ABI from `out/`, not `lib/abis/` (drift still caught by parity test + `--check`).                                       |
| PH7-L12                          | Inline minimal ABI + hand-written EIP-712 constants in 6 places not centralised (all currently match).                                                |
| PH7-L14                          | No `[rpc_endpoints]` in `foundry.toml` (operator convenience).                                                                                        |
| PH7-L17                          | `_verifyWiring` does not check `CANCELLER_ROLE` (one-line missing assertion; on-chain state correct).                                                 |
| PH7-L18                          | Deploy script writes no deployment artifact JSON (address recording manual).                                                                          |
| PH7-L19                          | No timelock-proposal helper post-deploy (verifiers 2–3 granted manually via Safe UI/`cast`).                                                          |
| PH7-L20                          | Stale chain-97 broadcast artifacts not cleaned/labelled.                                                                                              |
| PH7-L21                          | Supplied `AGENT_ID_ADDRESS` on chain 97 not validated (default mock path safe).                                                                       |
| PH7-L22                          | Manual BscScan verification lacks a constructor-args table (automatic path correct).                                                                  |
| PH7-L23                          | 3 hidden operational prerequisites (tested RPC URL, Safe already created, test wallet funded) not in checklist §1.                                    |
| PH7-L24, L26, L28, L29, L30, L31 | Historical Phase 6 evidence/documentation accuracy notes (lint warnings, JSON provenance, log paths, duplicate logs). None affects material security. |
| PH7-L25                          | No Phase 8 disposition recorded (Slither count note; current figures in `TEST_RESULTS.md`).                                                           |
| PH7-I01–I06, I08, I10–I17        | Informational — no action required (see `FINDINGS.md` §4 for each).                                                                                   |

### 2.3 Operational / external items

| Item                                                     | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **O4 — real wallet app never tested**                    | wagmi uses only `injected()`, no WalletConnect. Closes only at live testnet validation. A frontend-scope item the contract auditor should be aware of, not a contract finding.                                                                                                                                                                                                                                                                                                 |
| **R-012 — external security review**                     | **Not commissioned.** Mandatory before mainnet. This package is the preparation for it.                                                                                                                                                                                                                                                                                                                                                                                        |
| **R-010 — threshold attestation**                        | IMPLEMENTED, not CLOSED. Closure needs: (1) live testnet smoke — threshold-1 and threshold-2 quests created and completed on live testnet, duplicate/insufficient reverts observed on-chain, plus the new on-chain policy checks (checklist §5.1 steps 9–11: createQuest 1,001/T1 revert, revoke guardrail, supersedes procedure); (2) the diff included in the commissioned external review (R-012); (3) ≥ 3 verifiers granted before the first threshold-2 quest on mainnet. |
| **≥ 3 verifiers before first mainnet threshold-2 quest** | Operational, at deploy time. Note (Phase 8): `DeployAgentHub` grants at most 1 verifier, so a threshold-2 quest cannot be created on a fresh stack until verifier 2 is granted via timelock (2-day delay — start early).                                                                                                                                                                                                                                                       |
| **8 user deployment inputs + broadcast approval**        | External blockers for testnet broadcast: tBNB (≥ 0.05), dedicated testnet deployer key, testnet Safe address (threshold ≥ 2), quest creator (must be a Safe, threshold ≥ 2, distinct from admin), first verifier (optional), pauser (optional), BscScan API key, explicit broadcast approval — plus the 3 prerequisites in PH7-L23.                                                                                                                                            |

## 3. Pre-mainnet checklist (Phase 7 §11, updated with Phase 8 status)

| #   | Item                                                                    | Status after Phase 8                        |
| --- | ----------------------------------------------------------------------- | ------------------------------------------- |
| 1   | PH7-H01 on-chain threshold policy                                       | ✅ Closed                                   |
| 2   | PH7-M02 "real-world badge" defined in code                              | ✅ Closed                                   |
| 3   | PH7-M01 on-chain revoke guardrail                                       | ✅ Closed                                   |
| 4   | PH7-M03 creator Safe + review window                                    | ⚠️ Code closed; review-window decision open |
| 5   | PH7-L01 total emission cap or documented monitoring mitigation          | ⚠️ Accepted with evidence (no on-chain cap) |
| 6   | PH7-L13 solc upgrade evaluation                                         | ✅ Closed (0.8.39)                          |
| 7   | PH7-M07/M08/M09 ABI detection gaps                                      | ✅ Closed                                   |
| 8   | External security review (R-012) commissioned, critical findings closed | ❌ Not commissioned — **this package**      |
| 9   | O4 real wallet-app test                                                 | ❌ Open (testnet validation)                |
| 10  | ≥ 3 verifiers before first mainnet threshold-2 quest                    | ❌ Open (at deploy)                         |

## 4. Residual accepted risks (threat model §6)

AR-1 Agent ID contract compromise · AR-2 multisig threshold compromise ·
AR-3 rogue creator (per-quest cap only) · AR-4 front-running of capped
slots · AR-5 frontend/DNS compromise · AR-6 no external audit yet ·
AR-7 Cancun-opcode assumption (now a real MCOPY dependency — see
`BYTECODE.md`). Full text: `THREAT_MODEL.md` §6.
