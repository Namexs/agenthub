# AGENTHUB — Architecture Overview (for the auditor)

> **Sourced, not invented.** Everything below is condensed from the repo's
> own documents at the audit commit: `docs/ARCHITECTURE.md`,
> `README.md`, `docs/SECURITY_THREAT_MODEL.md` (§5 design decisions),
> `agenthub-next-phase-validation/THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md`,
> and the Phase 6/7/8 reports in `reports/`. Where a detail matters,
> the source file is cited. This overview does not add claims beyond
> those sources.

## 1. What AGENTHUB is

An Agent ID-native activity and reputation platform on BNB Chain, built
for the Binance Wallet Agent ID Hackathon (60,000 USDC total rewards).
It answers one question for Binance Agent ID holders: _what have I done,
and can anyone verify it?_ Every answer is an on-chain record.

- **Quest marketplace** — quests users complete for reputation points.
- **On-chain reputation** — a points ledger with a public event history.
- **Soulbound achievement badges** — non-transferable ERC-721 proof of
  completion.
- **Transparent leaderboard** — derived from on-chain events,
  recomputable by anyone.

**Quality standard (repo-wide):** a feature is done only when a user can
point at a transaction and say "that happened". The UI never displays a
state it cannot read from the chain.

**Status at the audit commit:** contracts implemented, internally
reviewed (Phase 7), remediated (Phase 8). **Nothing is deployed yet and
nothing has been submitted to the hackathon.** Final deployment targets
BSC mainnet (chain 56), source-verified on BscScan; BSC testnet
(chain 97) is staging only. Submission deadline: 9 December 2026,
08:00 UTC (15:00 WIB).

## 2. System diagram

```
                ┌─────────────────────────┐
                │  Binance Agent ID (ERC-721 soulbound)
                │  0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F (BSC mainnet)
                └────────────┬────────────┘
                             │ balanceOf(account) > 0
                ┌────────────▼────────────┐
                │  1. AgentGate           │  identity verification
                └────────────┬────────────┘
                             │ only Agent ID holders
                ┌────────────▼────────────┐
                │  2. QuestManager        │  quests + validated completions
                └──────┬──────────┬───────┘
                       │          │
          ┌────────────▼──┐  ┌────▼────────────┐
          │ 3. Reputation │  │ 4. Achievement  │
          │ points/levels │  │ soulbound badges│
          └───────────────┘  └─────────────────┘
                       │          │
                ┌──────▼──────────▼───────┐
                │  Next.js frontend       │
                │  reads events + state,  │
                │  never holds custody    │
                └─────────────────────────┘
```

(Source: `docs/ARCHITECTURE.md` §1.)

## 3. Contracts

| Contract       | Responsibility                                                                                                                                       | Key invariants (from `docs/SECURITY_THREAT_MODEL.md` §5)                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AgentGate`    | Single source of truth for "does this address hold an Agent ID". Reads `balanceOf` on the trusted Agent ID contract, validates the expected chainId. | Trusted address + expected chainId immutable, set once in the constructor; constructor requires code at the address and `expectedChainId == block.chainid`. `isAgentHolder` **fails closed**: wrong chain, zero account, or any external-call failure ⇒ `false` (never reverts). `verify()` lets a holder record an on-chain verification (`AgentHolderVerified` event).                                                                                                                         |
| `QuestManager` | Quest creation (role-gated), completion recording, cooldowns, duplicate prevention. Calls Reputation + Achievement on validated completion.          | `completeQuest` is `nonReentrant` + `whenNotPaused`, checks-effects-interactions; all state updated before external calls. Validation: holder, active, time window, cap, one-time/duplicate, cooldown. Reward capped at 10,000 points per quest. Strings capped (title ≤ 128 bytes, description ≤ 1024 bytes). Badge must exist. Badge issuance skipped (not reverted) if the user already holds the badge.                                                                                      |
| `Reputation`   | Points ledger. Points increase ONLY via authorized callers (QuestManager).                                                                           | **No admin score function exists, by design.** Points only via `SCORE_SOURCE_ROLE` (QuestManager), capped per event (10,000). Full event history (`PointsAdded` with quest id) — every point traceable. Pausable (admin only).                                                                                                                                                                                                                                                                   |
| `Achievement`  | ERC-721 soulbound badges. Issued only by authorized callers after validated completion.                                                              | Transfers revert (`_update`), approvals revert (`approve`, `setApprovalForAll`). Issuance only via `ISSUER_ROLE` (QuestManager), one badge per (account, badgeId), badge must be defined first. Uses `_mint`, **not** `_safeMint`: no `onERC721Received` callback, so no reentrancy surface at mint time (documented trade-off: badges can be minted to contracts that do not implement the ERC-721 receiver — accepted because badges are soulbound and ownership is verifiable via `ownerOf`). |
| `MockAgentId`  | Local/testnet stand-in for the official Agent ID contract (not deployed on testnet). Mirrors soulbound behaviour.                                    | **Never deployed to mainnet.** `DeployMock` allowlist {97, 31337}.                                                                                                                                                                                                                                                                                                                                                                                                                               |

Supporting code (in scope): `src/interfaces/` (`IAgentGate`,
`IQuestManager`, `IReputation`, `IAchievement`, `IQuestValidator`),
`src/validators/` (OnChain validation), `src/mocks/`.
Dependencies: OpenZeppelin Contracts 5.0.2 (pinned submodule, `lib/`),
notably `AccessControl`, `ReentrancyGuard` (storage-based in 5.0.2 —
no `ReentrancyGuardTransient`), `TimelockController`, `ECDSA`,
`EIP712`.

## 4. Quest validation kinds

(Source: `README.md`, `docs/QUEST_VALIDATION_DESIGN.md`,
`THRESHOLD_ATTESTATION_REMEDIATION_PLAN.md`.)

1. **CheckIn** — explicit self-check-in by the holder.
2. **OnChain** — validated by a validator contract (e.g. token-balance
   check).
3. **Attested** — EIP-712 verifier attestation, **threshold M-of-N**
   (Phase 6, R-010): each quest declares how many distinct verifier
   signatures it requires (1–3, immutable after creation).

### Threshold attestation design (Phase 6)

- Attestation struct (unchanged from single-verifier):
  `Attestation(address account, uint256 questId, uint256 nonce,
uint256 deadline)`. All M signers sign the **same digest**; no new
  EIP-712 type, no domain change.
- `completeQuestWithAttestation(questId, deadline, bytes[] signatures)`
  requires at least M **distinct** `VERIFIER_ROLE` signers over that
  digest. Distinctness enforced by pairwise comparison (O(M²), M ≤ 3).
  A duplicate signer **reverts** (`DuplicateAttestationSigner`).
- Nonce consumed exactly once per completion regardless of M; a failed
  completion reverts the whole tx, so the nonce is not burned.
- Extra signatures beyond M are allowed but ignored for counting (each
  must still recover to a valid `VERIFIER_ROLE` signer — junk anywhere
  reverts). Array length capped at `MAX_ATTESTATION_SIGNATURES = 5`.
- Events: `AttestationUsed(account, questId, nonce, signer)` once per
  distinct signer.
- `attestationThreshold` (uint8) is set at creation, **immutable**
  afterwards; bounds 1–3 (`AttestationThresholdOutOfRange` otherwise).
- **Deliberate ABI break:** the old single-`bytes` entry point was
  replaced, not kept alongside — two completion paths for the same
  quest would invite bypass (a threshold-2 quest completable through
  a legacy single-sig path would silently void the threshold).

### Phase 8 policy enforcement (on-chain, new in this audit commit)

- **PH7-H01:** Attested quest with `rewardPoints > 1,000` **must** have
  `attestationThreshold ≥ 2` (enforced in `createQuest`).
- **PH7-M02:** `Badge.highValue` flag + `setBadgeHighValue`; `createQuest`
  rejects threshold 1 for a high-value badge. The flag is only read at
  creation, so re-flagging does not change live quests.
- **PH7-M01:** verifier-revoke guardrail — `_grantRole`/`_revokeRole`
  overrides maintain `verifierCount` and per-threshold live-quest
  counters; revoke (incl. `renounceRole`) is rejected if it would drop
  below the highest live threshold (`RevocationWouldBrickQuest`);
  `createQuest` Attested is rejected if `verifierCount < threshold`.
- **PH7-L07:** `supersedes` mechanism — `setSupersedes(newQuestId,
oldQuestId)` (admin-only), `QuestSuperseded` event, completion guard
  `AlreadyCompletedSupersededQuest`; single-hop by design, no clear
  function (fail-safe).
- **PH7-L05:** the `provided < threshold` check moved before the
  digest/loop (gas saving on doomed submissions).

## 5. Data flow

(Source: `docs/ARCHITECTURE.md` §4.)

1. User connects an EVM wallet (injected connector; no QR login, no
   server session).
2. Frontend reads `balanceOf(user)` on the Agent ID contract (or
   `isAgentHolder` on AgentGate once deployed) and shows holder status.
3. User completes a quest → one user-confirmed transaction to
   `QuestManager.completeQuest(questId)` (or
   `completeQuestWithAttestation` for Attested quests).
4. QuestManager validates (holder, active window, cooldown, not already
   completed) then calls `Reputation.addPoints` and, when applicable,
   `Achievement.issue` — all inside the same transaction.
5. Frontend reads `QuestCompleted` / `PointsAdded` / `BadgeIssued`
   events and contract state to render dashboard, profile, leaderboard,
   and history.

## 6. Environments

| Environment             | Chain                | Agent ID contract          | Purpose                         |
| ----------------------- | -------------------- | -------------------------- | ------------------------------- |
| Local                   | Anvil (31337)        | MockAgentId                | Development + integration tests |
| Staging                 | BSC Testnet (97)     | MockAgentId                | Public testing, hackathon demo  |
| **Production (target)** | **BSC Mainnet (56)** | **Official `0x60B9…022F`** | **Competition submission**      |

## 7. Privilege model (production)

(Source: `docs/SECURITY_THREAT_MODEL.md` §5.5; enforced by
`script/DeployAgentHub.s.sol` + `_verifyWiring` post-deploy checks.)

| Power                                 | Holder (production)                                                                                                                                                                                     |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` on all contracts | `TimelockController` (minDelay 2 days)                                                                                                                                                                  |
| Timelock proposers / executors        | Admin multisig (Safe, threshold ≥ 2)                                                                                                                                                                    |
| `QUEST_CREATOR_ROLE`                  | Campaign multisig — **must be a validated Safe** (Phase 8, PH7-M03: `SafeValidation.validate`, same check as admin multisig, canonical singleton + proxy codehash + threshold ≥ 2; distinct from admin) |
| `PAUSER_ROLE`                         | Admin multisig (pause fast; unpause via admin)                                                                                                                                                          |
| `SCORE_SOURCE_ROLE` / `ISSUER_ROLE`   | `QuestManager` contract only                                                                                                                                                                            |
| `VERIFIER_ROLE`                       | Named verifiers (≥ 3 required before the first threshold-2 quest on mainnet; deploy script grants at most 1 — the rest via timelock)                                                                    |
| Deployer                              | Renounces all admin roles after setup (script-enforced); MockAgentId ownership transferred to the admin multisig (Phase 8, PH7-M04)                                                                     |

## 8. Deployment order

(Source: `script/DeployAgentHub.s.sol` header; `docs/DEPLOYMENT_PLAN.md`.)

MockAgentId (testnet/local only, when no Agent ID address is given) →
AgentGate → TimelockController → Reputation → Achievement →
QuestManager, then role wiring and handover of admin to the timelock.
See `deployment/DeployAgentHub.s.sol` (verbatim copy) and
`docs/DEPLOYMENT_PLAN.md` in the repo.

## 9. Trust assumptions

(Source: `docs/ARCHITECTURE.md` §8; `docs/SECURITY_THREAT_MODEL.md`
§2, §6.)

- **Agent ID contract is trusted.** AgentGate trusts exactly one
  address per chain (official on mainnet, mock on testnet/local).
  The address is immutable at deploy time.
- **BNB Chain liveness.** Reads/writes assume the chain is available.
- **User's wallet is the signer.** AGENTHUB never signs for users and
  never sees private keys.
- **No oracle / no backend.** All state is on-chain. No server can lie
  about points or badges — but also no server can recover anything.
  On-chain mistakes are permanent.
- **Admin roles are human-operated** (multisig + timelock in
  production).
- **Contracts hold no user funds** (non-custodial). The only asset at
  risk from a contract bug is reputation integrity, never money.
- **OpenZeppelin 5.0.2** (pinned submodule) and the **solc 0.8.39**
  toolchain are trusted; see `BUILD_REPRODUCTION.md` and
  `KNOWN_LIMITATIONS.md` (solc 0.8.39 was 1 day old at evaluation).
