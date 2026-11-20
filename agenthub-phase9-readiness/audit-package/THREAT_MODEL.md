# AGENTHUB — Threat Model (for the auditor)

> **Sourced, not invented.** This is a condensed restatement of
> `docs/SECURITY_THREAT_MODEL.md` (v1.0, 2026-11-19, updated in Phase 8
> for AR-3 and the solc version) at the audit commit. Attack-tree
> verdicts (FAILS / MITIGATED / ACCEPTED) are quoted from that document.
> The full document (368 lines) is the authoritative source; read it
> before disputing any summary here.

## 1. Scope

AGENTHUB smart contracts (`AgentGate`, `QuestManager`, `Reputation`,
`Achievement`), their deployment configuration, and the trust boundary
with the Next.js frontend. Covers BSC mainnet (competition target),
BSC testnet (staging), and local Anvil development.

## 2. Assets

| Asset                    | Value                                                                                                                                                      | Where it lives                           |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| Reputation points        | Integrity of the leaderboard; the product's core claim. Points have no monetary value by design, but inflated points destroy trust and hackathon standing. | `Reputation._points`                     |
| Achievement badges       | Non-transferable proof of completion. Duplicated or forged badges destroy verifiability.                                                                   | `Achievement` ERC-721                    |
| Quest completion records | Proof that a user did something. Falsified completions poison points + badges downstream.                                                                  | `QuestManager` mappings + events         |
| Agent ID gating          | The guarantee that only real Agent ID holders participate. If bypassed, Sybil resistance collapses.                                                        | `AgentGate` + official Agent ID contract |
| Admin roles              | Power to create quests, define badges, pause. Compromise = arbitrary quest/reward injection (but NOT arbitrary points — no such function exists).          | `AccessControl` roles on each contract   |
| Deployment configuration | Wrong addresses/chain = wrong trust root. Immutable after deploy by design.                                                                                | Constructor args (immutable vars)        |
| User funds               | **None held.** Contracts move no assets. The only asset at risk from a contract bug is reputation integrity, never money.                                  | N/A (non-custodial)                      |

## 3. Trust boundaries

```
[User wallet] ──signs tx──▶ [AGENTHUB contracts] ──reads──▶ [Agent ID contract]
      │                              │  ▲                          (trusted,
      │                              │  │                           immutable
      │                         events │  │                           address)
      ▼                              ▼  │
[Frontend / BscScan] ──reads only───┘  └── admin (multisig + timelock)
```

- **Trusted:** the Agent ID contract address configured at deploy; the
  BSC chain itself; OpenZeppelin 5.0.2 (audited library, pinned
  submodule).
- **Untrusted:** all user input (addresses, strings, quest parameters);
  any contract that is NOT the configured Agent ID contract; the
  frontend (it can lie in the UI — the chain is the source of truth,
  verifiable on BscScan); RPC responses (untrusted until the user
  verifies on-chain).
- **Semi-trusted:** admin key holders (multisig reduces single-key
  risk; timelock gives users time to react to config changes).

## 4. Threat actors

| Actor                               | Capability                                                              | Goal                                                                                                                     |
| ----------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| A1 Malicious user (EOA)             | Sends arbitrary transactions; owns ≥0 Agent IDs; may control many EOAs. | Inflate own points/badges; complete quests without doing them; grief others.                                             |
| A2 Malicious contract deployer      | Deploys arbitrary contracts; can make contracts that hold an Agent ID.  | Reentrancy / callback attacks; fake identity contracts; gas griefing.                                                    |
| A3 Compromised admin key            | Holds one admin/creator key (not the multisig threshold).               | Create malicious quests; define fake badges; pause the system (DoS).                                                     |
| A4 Compromised multisig (threshold) | Controls the admin multisig.                                            | Full admin power except functions that do not exist (no arbitrary points, no fund movement — there is nothing to steal). |
| A5 Front-runner / MEV searcher      | Observes mempool; orders transactions.                                  | Steal a completion slot (e.g. last slot of a capped quest); sandwich nothing (no value transfer exists).                 |
| A6 Malicious dependency / toolchain | Compromised npm package, git submodule, or build tool.                  | Inject backdoors into contracts or frontend.                                                                             |
| A7 Frontend attacker                | Compromises Vercel/hosting or DNS.                                      | Phish users into signing wrong transactions; display false data.                                                         |

## 5. Threats and attack trees

Verdicts as recorded in the threat model. **FAILS** = the attack cannot
succeed against the code; **MITIGATED** = reduced by a control;
**ACCEPTED** = residual risk consciously accepted (see §6).

### T1 — Fake identity (bypass Agent ID gating)

- Deploy a fake ERC-721 returning `balanceOf = 1` for everyone →
  **FAILS**: AgentGate reads ONLY the immutable configured address.
- Point the frontend at a fake Agent ID address → **MITIGATED**:
  `env.ts` consistency rules (56 ⇒ official address only; 97 ⇒
  official address forbidden); chain allowlist.
- Deploy AgentGate with a fake address (deployer error / insider) →
  **MITIGATED**: constructor requires code at the address + matching
  chainId; deployment checklist requires BscScan verification of the
  configured address; address is immutable.
- Agent ID contract itself is malicious/compromised → **ACCEPTED**:
  the official contract is Binance-operated and soulbound; if it is
  compromised, the entire Agent ID ecosystem is — out of scope.

### T2 — Reputation inflation

- Call `Reputation.addPoints` directly → **FAILS**: only
  `SCORE_SOURCE_ROLE` (QuestManager).
- Impersonate QuestManager → **FAILS**: role granted to one contract
  address; attacker cannot deploy at that address.
- Complete the same one-time quest twice → **FAILS**: `_completed`
  mapping; `AlreadyCompleted` revert.
- Farm a repeatable quest faster than intended → **FAILS**: per-account
  cooldowns (24h daily / 7d weekly) enforced on-chain.
- Create a quest with absurd rewards (needs `QUEST_CREATOR_ROLE`) →
  **MITIGATED**: reward capped at `MAX_REWARD_POINTS` (10,000) per quest
  and per `addPoints` event; role is multisig-held in production.
  (Note: the cap is PER QUEST ONLY — see AR-3 / PH7-L01.)
- Reenter `completeQuest` via a callback during badge mint →
  **FAILS**: `Achievement` uses `_mint` (no `onERC721Received`
  callback) AND `completeQuest` + `issue` are `nonReentrant`;
  checks-effects-interactions.
- Replay another user's completion transaction → **FAILS**: completion
  is bound to `msg.sender`; there is no delegated/signature-based
  completion. (Attested completions bind the attestation to the
  account + nonce + deadline via EIP-712; replay vectors were
  PoC-tested in Phase 7 — see `FINDINGS.md`.)
- Overflow points arithmetic → **FAILS**: Solidity 0.8 checked
  arithmetic; invariant test asserts points == Σ rewards × completions.

### T3 — Badge forgery / duplication

- Call `Achievement.issue` directly → **FAILS**: only `ISSUER_ROLE`
  (QuestManager).
- Complete two quests awarding the same badge → **FAILS**: `hasBadge`
  check — second issuance is skipped, not duplicated.
- Transfer a badge → **FAILS**: `_update` reverts for any transfer;
  `approve`/`setApprovalForAll` revert; soulbound by construction.
- Define a badge mimicking an official one → **MITIGATED**:
  `defineBadge` is `BADGE_MANAGER_ROLE` (multisig); duplicate
  definition reverts.
- Mint to a contract that cannot handle ERC-721 (locking) →
  **ACCEPTED**: `_mint` records ownership regardless of receiver code;
  badges are soulbound and need no receiver handling.

### T4 — Admin abuse / privilege escalation

- Self-grant a role → **FAILS**: only `DEFAULT_ADMIN_ROLE` can grant
  roles; role admin is `DEFAULT_ADMIN_ROLE` for all roles.
- Compromised `QUEST_CREATOR_ROLE` key creates reward-farming quests →
  **MITIGATED**: per-quest reward cap (10,000); quests are public and
  auditable; admin can deactivate; pause stops all completions.
  **Residual risk accepted (Phase 7 PH7-L01, corrected):** the cap is
  PER QUEST ONLY — there is no on-chain cap on the TOTAL points one
  creator can issue (many quests, or one unlimited repeatable quest).
  Accepted because the creator role is trusted (campaign multisig in
  production — now enforced on-chain, PH7-M03), issuance is public and
  monitored (completion spikes), and deactivate + pause bound the
  damage window. See `docs/QUEST_VALIDATION_DESIGN.md` §5.
- Compromised `PAUSER_ROLE` key pauses the system (DoS) →
  **MITIGATED**: pause is reversible by `DEFAULT_ADMIN_ROLE`
  (multisig + timelock); reads keep working while paused; no funds at
  risk.
- Compromised deployer key (post-deploy) → **MITIGATED**: deployer
  renounces `DEFAULT_ADMIN_ROLE` after granting it to the
  TimelockController (deployment script + checklist).
- Timelock bypass → **FAILS**: TimelockController enforces minDelay
  on-chain.
- Multisig threshold compromise (A4) → **ACCEPTED** (residual):
  threshold compromise gives full admin power, but the damage surface
  is bounded — no fund movement, no arbitrary points, no badge
  transfers. Worst case: junk quests + pause + role churn, all public
  and reversible by redeploying the suite.

### T5 — Transaction ordering (MEV / front-running)

- Front-run the last slot of a capped quest → **ACCEPTED**: the slot
  goes to whoever's tx lands first; the victim loses nothing but the
  slot (no funds). No value is extractable.
- Sandwich a completion → N/A: completions move no assets and change
  no prices.
- Censor a completion (validator-level) → **ACCEPTED**: out of scope
  for an application contract; user can retry.

### T6 — Denial of service

- Agent ID contract's `balanceOf` reverts/misbehaves → **MITIGATED**:
  gate fails closed (returns `false`) — the system halts safely rather
  than mis-granting access. Recovery requires a redeploy with a fixed
  address (documented; low-probability event).
- Giant strings at quest creation (gas griefing) → **FAILS**: title ≤
  128 bytes, description ≤ 1024 bytes.
- Fill a capped quest with Sybil completions → **MITIGATED**: every
  completion needs an Agent ID (one per person, Binance-issued,
  soulbound).
- Pause griefing → **MITIGATED**: see T4.
- Block gas: `completeQuest` gas is bounded (no unbounded loops) →
  **VERIFIED**: no loops over user-controlled collections anywhere.
  (Note: the attestation signature array is capped at 5 — Phase 6.)
- Front-end outage (Vercel/DNS) → **ACCEPTED**: contracts remain usable
  via BscScan / direct RPC; no backend dependency.

### T7 — Dependency / supply-chain compromise

- Compromised OpenZeppelin submodule → **MITIGATED**: pinned tag v5.0.2
  - `foundry.lock` commit hash; any change shows in git diff.
- Compromised npm package (frontend) → **MITIGATED**: exact-pinned
  versions + `pnpm-lock.yaml` + `--frozen-lockfile` in CI; `pnpm
audit` in CI.
- Compromised toolchain (solc / forge) → **MITIGATED**: solc 0.8.39
  pinned in `foundry.toml`; forge 1.9.0 pinned in CI; reproducible
  builds.
- Compromised GitHub Action → **MITIGATED**: pinned major versions; no
  third-party actions with write access; permissions block added.

### T8 — Frontend / UX trust

- Fake UI claiming a completion (no tx) → **MITIGATED**: UI reads
  chain state; every claim links to BscScan.
- Malicious frontend swapping the contract address (phishing clone) →
  **ACCEPTED**: users must verify the domain + contract addresses
  (documented in `USER_GUIDE.md`); out of contract scope.
- Env misconfiguration (wrong chain / wrong Agent ID address) →
  **MITIGATED**: `env.ts` validation + consistency rules.

## 6. Accepted risks (residual)

| #    | Risk                                                                 | Why accepted                                                                                                                                                                                                                                                          |
| ---- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AR-1 | Official Agent ID contract misbehaves / is compromised.              | Binance-operated, soulbound, ecosystem-wide; out of AGENTHUB's control. Gate fails closed.                                                                                                                                                                            |
| AR-2 | Multisig threshold compromise.                                       | Bounded damage (no funds, no arbitrary points); mitigated by threshold ≥ 2 + timelock delay.                                                                                                                                                                          |
| AR-3 | Rogue quest creator makes junk/capped-reward quests.                 | Visible on-chain, capped at 10,000 pts/quest (PER-QUEST ONLY — no total cap; Phase 7 PH7-L01, accepted: trusted creator role + spike monitoring + deactivate/pause), deactivatable, pausable.                                                                         |
| AR-4 | Front-running of capped-quest slots.                                 | No value at stake; victim loses only a slot.                                                                                                                                                                                                                          |
| AR-5 | Frontend/DNS compromise misleads users.                              | Chain remains source of truth; users can verify on BscScan. No signing power in frontend.                                                                                                                                                                             |
| AR-6 | No external audit yet.                                               | Independent review is required before mainnet (see `SECURITY_DEPLOYMENT_GATE.md`); internal hardening is not a substitute. **This package exists to close AR-6.**                                                                                                     |
| AR-7 | BSC Cancun-opcode support assumed (`evm_version = "cancun"` pinned). | Phase 8 update: MCOPY is now a REAL codegen dependency (1× QuestManager, 1× Achievement — see `BYTECODE.md`), not just a pin. Cancun is proven active on BSC testnet and mainnet (Phase 5 validation); a testnet smoke test is a deployment-gate item before mainnet. |

## 7. Out of scope

- Security of the Binance Agent ID contract itself.
- Security of the user's wallet / device.
- BNB Chain consensus / validator behavior.
- Economic value of points/badges (there is none by design).
- The `MockAgentId` test contract (test-only; must never reach mainnet
  — enforced by `DeployMock` allowlist + deployment checklist).

## 8. Notes for the auditor (threat-model gaps found by prior reviews)

These items were raised against the threat model itself in Phase 7/8
and are recorded here so the auditor does not re-derive them from
scratch; dispositions are in `FINDINGS.md`:

- **PH7-L01 / AR-3 correction:** the old wording implied a total
  emission cap; the cap is per-quest only. Accepted with evidence
  (Phase 8), not fixed in code.
- **PH7-L03:** attestation signed BEFORE a `VERIFIER_ROLE` grant
  becomes valid AFTER the grant (grant-side TOCTOU) — SOP mitigation
  not yet written (open).
- **PH7-L04:** validator behaviour can change after approval — SOP
  approval + codehash logging not yet applied (open).
- **PH7-L06:** global per-account nonce makes attestations stale
  across quests — documented UX limitation; per-quest nonce is a
  deferred design change (open).
- **PH7-I06:** replay on a fork with the same `chainId` is
  theoretically possible — accepted risk.
- **Phase 6 plan §7 risk 2 (threshold footgun):** verifier set
  shrinking below a live quest's threshold bricks the quest. Phase 8
  closed the on-chain part with the revoke guardrail (PH7-M01); the
  SOP part (≥ threshold verifiers granted before creating a threshold
  quest) remains a process control.
