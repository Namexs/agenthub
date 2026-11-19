# AGENTHUB — Security Threat Model

**Version:** 1.0 — 2026-11-19 (Security Engineering phase)
**Scope:** AGENTHUB smart contracts (`AgentGate`, `QuestManager`, `Reputation`,
`Achievement`), their deployment configuration, and the trust boundary with the
Next.js frontend. Covers BSC mainnet (competition target), BSC testnet
(staging), and local Anvil development.
**Status:** Living document. Updated whenever a contract, role, or trust
assumption changes.

---

## 0. Pre-implementation review (directive §9 prerequisite)

Before any implementation, the Phase 1 architecture, interfaces, and audit
were reviewed. This section records what the review found; implementation
decisions in §5–§6 follow from it.

### 0.1 What was reviewed

- `docs/ARCHITECTURE.md` — 4-contract dependency order, data flow, environments.
- `docs/SECURITY.md` — principles, red lines, layered defense, roles, procedures.
- `PHASE1_AUDIT.md` — validation results + findings M1–M5, L1–L9.
- Interfaces: `IAgentGate`, `IQuestManager`, `IReputation`, `IAchievement`.
- `MockAgentId`, `DeployMock.s.sol`, `foundry.toml`, `.env.example`, `ci.yml`.
- OpenZeppelin 5.0.2 sources in `lib/` (verified by reading, not assumed).

### 0.2 Review verdict

The architecture is sound for a non-custodial reputation system: identity is a
single source of truth (`AgentGate`), points have no admin mint path by design,
badges are soulbound, and no contract ever holds user assets. The interfaces
are well specified (custom errors, events, NatSpec). The review found **gaps
to close during implementation, not reasons to redesign**:

| # | Review finding | Disposition |
|---|---|---|
| R1 | `IAgentGate.AgentHolderVerified` event exists but no non-view function can emit it (both functions are `view`). | Add `verify()` (non-view): holder proves ownership on-chain, emits the event. |
| R2 | No specified behavior when the trusted Agent ID contract's `balanceOf` reverts or returns malformed data. | Gate must fail closed: `isAgentHolder` returns `false` on any external-call failure (`try/catch`); `requireAgentHolder` reverts. |
| R3 | `IQuestManager`: semantics of `maxCompletions == 0` undefined; `Community` quest completion semantics undefined. | Document + implement: `0` = unlimited; `Community` = one completion per account (like `OneTime`). |
| R4 | `IQuestManager`: no string-length limits — unbounded `title`/`description` is a gas/DoS vector at creation. | Cap: title ≤ 128 bytes, description ≤ 1024 bytes. |
| R5 | `IQuestManager`: no way to validate `badgeId` at quest creation (a quest could reference a badge that never exists). | Add `IAchievement.isBadgeDefined()`; `createQuest` reverts for undefined non-zero badge ids. |
| R6 | `IReputation`: no per-event points cap in the interface. | Implement `MAX_POINTS_PER_EVENT = 10_000`, enforced in `addPoints` and mirrored in `QuestManager.MAX_REWARD_POINTS`. |
| R7 | `MockAgentId` blocks transfers via `_update` but approvals still succeed (harmless yet misleading). | `Achievement` explicitly reverts `approve`/`setApprovalForAll` as well. |
| R8 | Phase 1 audit M2: `evm_version` unpinned. Verified from OZ 5.0.2 source that `ReentrancyGuard` is **storage-based** (`uint256 _status`); no `ReentrancyGuardTransient` exists in 5.0.2 — so the transient-storage (EIP-1153) concern does **not** apply to our guard usage. Still pin `evm_version = "cancun"` explicitly (M2) and verify Cancun opcodes on BSC testnet before mainnet. | Fixed in this phase (see `SECURITY_REMEDIATION.md`). |
| R9 | Phase 1 audit M5: frontend `env.ts` has no chain allowlist, accepts zero addresses, and never checks chain ↔ Agent ID address consistency. | Fixed in this phase: chain allowlist {56, 97, 31337}, zero-address rejection, consistency rules (see §5.6). |
| R10 | Phase 1 audit L4: `DeployMock` guard is a denylist (blocks only chain 56). | Fixed: allowlist {97, 31337}. |
| R11 | Phase 1 audit M3/L1/L5/L6: CI foundry toolchain unpinned; `.gitignore` misses `.env.production`; CI lacks format/audit/secret-scan steps; web build lacks a memory cap. | Fixed in this phase where safe; `pnpm audit` in CI added (runs on GitHub runners, not in this VM). |
| R12 | `IAchievement`: no `isBadgeDefined` view; `defineBadge` has no duplicate/empty-input errors. | Added (see §5.4). |

### 0.3 Interface amendments (all documented here, applied in this phase)

- `IAgentGate`: + `verify()`, + errors `NoCodeAtAgentId`, `InvalidChainId`.
- `IQuestManager`: + errors `ZeroAddress`, `NotQuestCreatorOrAdmin`; NatSpec
  clarifies `maxCompletions == 0` = unlimited, `Community` = one-time per account.
- `IReputation`: + errors `ZeroAddress`, `InvalidLevel`.
- `IAchievement`: + `isBadgeDefined()`, + errors `ZeroAddress`,
  `InvalidBadgeId`, `InvalidBadgeMetadata`, `BadgeAlreadyDefined`.

No interface function signature was changed in a way that breaks the Phase 1
frontend ABI stubs (`isAgentHolder`, `agentIdContract` unchanged).

---

## 1. Assets

| Asset | Value | Where it lives |
|---|---|---|
| Reputation points | Integrity of the leaderboard; the product's core claim. Points have no monetary value by design, but inflated points destroy trust and hackathon standing. | `Reputation._points` |
| Achievement badges | Non-transferable proof of completion. Duplicated or forged badges destroy verifiability. | `Achievement` ERC-721 |
| Quest completion records | Proof that a user did something. Falsified completions poison points + badges downstream. | `QuestManager` mappings + events |
| Agent ID gating | The guarantee that only real Agent ID holders participate. If bypassed, Sybil resistance collapses. | `AgentGate` + official Agent ID contract |
| Admin roles | Power to create quests, define badges, pause. Compromise = arbitrary quest/reward injection (but NOT arbitrary points — no such function exists). | `AccessControl` roles on each contract |
| Deployment configuration | Wrong addresses/chain = wrong trust root. Immutable after deploy by design. | Constructor args (immutable vars) |
| User funds | **None held.** Contracts move no assets. The only asset at risk from a contract bug is reputation integrity, never money. | N/A (non-custodial) |

## 2. Trust boundaries

```
[User wallet] ──signs tx──▶ [AGENTHUB contracts] ──reads──▶ [Agent ID contract]
      │                              │  ▲                          (trusted,
      │                              │  │                           immutable
      │                         events │  │                           address)
      ▼                              ▼  │
[Frontend / BscScan] ──reads only───┘  └── admin (multisig + timelock)
```

- **Trusted:** the Agent ID contract address configured at deploy; the BSC
  chain itself; OpenZeppelin 5.0.2 (audited library, pinned submodule).
- **Untrusted:** all user input (addresses, strings, quest parameters);
  any contract that is NOT the configured Agent ID contract; the frontend
  (it can lie in the UI — the chain is the source of truth, verifiable on
  BscScan); RPC responses (untrusted until the user verifies on-chain).
- **Semi-trusted:** admin key holders (multisig reduces single-key risk;
  timelock gives users time to react to config changes).

## 3. Threat actors

| Actor | Capability | Goal |
|---|---|---|
| A1 Malicious user (EOA) | Sends arbitrary transactions; owns ≥0 Agent IDs; may control many EOAs. | Inflate own points/badges; complete quests without doing them; grief others. |
| A2 Malicious contract deployer | Deploys arbitrary contracts; can make contracts that hold an Agent ID (an Agent ID can be held by a contract address if minted to it — the official contract mints to the wallet that claims it). | Reentrancy / callback attacks; fake identity contracts; gas griefing. |
| A3 Compromised admin key | Holds one admin/creator key (not the multisig threshold). | Create malicious quests; define fake badges; pause the system (DoS). |
| A4 Compromised multisig (threshold) | Controls the admin multisig. | Full admin power except functions that do not exist (no arbitrary points, no fund movement — there is nothing to steal). |
| A5 Front-runner / MEV searcher | Observes mempool; orders transactions. | Steal a completion slot (e.g. last slot of a capped quest); sandwich nothing (no value transfer exists). |
| A6 Malicious dependency / toolchain | Compromised npm package, git submodule, or build tool. | Inject backdoors into contracts or frontend. |
| A7 Frontend attacker | Compromises Vercel/hosting or DNS. | Phish users into signing wrong transactions; display false data. |

## 4. Threats and attack trees

### T1 — Fake identity (bypass Agent ID gating)

```
Goal: interact without a real Agent ID
├── Deploy a fake ERC-721 that returns balanceOf = 1 for everyone
│   └── FAILS: AgentGate reads ONLY the immutable configured address.
├── Point the frontend at a fake Agent ID address (M5)
│   └── MITIGATED: env.ts consistency rules (56 ⇒ official address only;
│       97 ⇒ official address forbidden); chain allowlist.
├── Deploy AgentGate with a fake address (deployer error / insider)
│   └── MITIGATED: constructor requires code at the address + matching
│       chainId; deployment checklist requires BscScan verification of the
│       configured address; address is immutable (cannot be swapped later).
└── Agent ID contract itself is malicious/compromised
    └── ACCEPTED: the official contract is Binance-operated and soulbound;
        if it is compromised, the entire Agent ID ecosystem is — out of scope.
```

### T2 — Reputation inflation

```
Goal: points without validated completion
├── Call Reputation.addPoints directly
│   └── FAILS: only SCORE_SOURCE_ROLE (QuestManager) can call it.
├── Become QuestManager (impersonate the caller)
│   └── FAILS: role is granted to one contract address; attacker cannot
│       deploy at that address.
├── Complete the same one-time quest twice
│   └── FAILS: _completed mapping; AlreadyCompleted revert.
├── Farm a repeatable quest faster than intended
│   └── FAILS: per-account cooldowns (24h daily / 7d weekly) enforced
│       on-chain; CooldownActive revert.
├── Create a quest with absurd rewards (needs QUEST_CREATOR_ROLE)
│   └── MITIGATED: reward capped at MAX_REWARD_POINTS (10_000) per quest
│       and per addPoints event; role is multisig-held in production.
├── Reenter completeQuest via a callback during badge mint
│   └── FAILS: Achievement uses _mint (no onERC721Received callback) AND
│       completeQuest + issue are nonReentrant; checks-effects-interactions.
├── Replay another user's completion transaction
│   └── FAILS: completion is bound to msg.sender; there is no delegated /
│       signature-based completion. Replaying a tx only completes for the
│       replaying address (which must itself hold an Agent ID and pass
│       all checks).
└── Overflow points arithmetic
    └── FAILS: Solidity 0.8 checked arithmetic reverts on overflow;
        realistic totals are far below 2^256 (invariant test asserts
        points == Σ rewards × completions).
```

### T3 — Badge forgery / duplication

```
Goal: hold a badge without earning it, or duplicate it
├── Call Achievement.issue directly
│   └── FAILS: only ISSUER_ROLE (QuestManager).
├── Complete two quests awarding the same badge
│   └── FAILS: hasBadge check — second issuance is skipped, not duplicated.
├── Transfer a badge to another account
│   └── FAILS: _update reverts for any transfer; approve/setApprovalForAll
│       revert; soulbound by construction.
├── Define a badge that mimics an official one
│   └── MITIGATED: defineBadge is BADGE_MANAGER_ROLE (multisig); badge ids
│       are namespaced per deployment; duplicate definition reverts.
└── Mint to a contract that cannot handle ERC-721 (locking)
    └── ACCEPTED: _mint records ownership regardless of receiver code;
        badges are soulbound and need no receiver handling. Owner can
        always be verified via ownerOf.
```

### T4 — Admin abuse / privilege escalation

```
Goal: gain powers beyond the intended role
├── Self-grant a role
│   └── FAILS: only DEFAULT_ADMIN_ROLE can grant roles; role admin is
│       DEFAULT_ADMIN_ROLE for all roles.
├── Compromised QUEST_CREATOR_ROLE key creates reward-farming quests
│   └── MITIGATED: per-quest reward cap (10_000); quests are public and
│       auditable; admin can deactivate; pause stops all completions.
│       Residual risk accepted: a rogue creator can still create junk
│       quests (visible, reversible, capped).
├── Compromised PAUSER_ROLE key pauses the system (DoS)
│   └── MITIGATED: pause is reversible by DEFAULT_ADMIN_ROLE (multisig +
│       timelock); reads keep working while paused; no funds at risk.
├── Compromised deployer key (post-deploy)
│   └── MITIGATED: deployer renounces DEFAULT_ADMIN_ROLE after granting
│       it to the TimelockController (deployment script + checklist).
├── Timelock bypass (execute without delay)
│   └── FAILS: TimelockController enforces minDelay on-chain; executor
│       cannot execute before the ETA.
└── Multisig threshold compromise (A4)
    └── ACCEPTED (residual): threshold compromise gives full admin power,
        but the damage surface is bounded — no fund movement, no arbitrary
        points, no badge transfers. Worst case: junk quests + pause + role
        churn, all public and reversible by redeploying the suite.
```

### T5 — Transaction ordering (MEV / front-running)

```
Goal: profit from ordering
├── Front-run the last slot of a capped quest
│   └── ACCEPTED: the slot goes to whoever's tx lands first; the victim
│       loses nothing but the slot (no funds). No value is extractable.
├── Sandwich a completion
│   └── N/A: completions move no assets and change no prices.
└── Censor a completion (validator-level)
    └── ACCEPTED: out of scope for an application contract; user can retry.
```

### T6 — Denial of service

```
Goal: make the system unusable
├── Revert the Agent ID contract's balanceOf (if trusted contract misbehaves)
│   └── MITIGATED: gate fails closed (returns false) — the system halts
│       safely rather than mis-granting access. Recovery requires a
│       redeploy with a fixed address (documented; the official contract
│       is Binance-operated and this is a low-probability event).
├── Create quests with giant strings (gas griefing at creation)
│   └── FAILS: title ≤ 128 bytes, description ≤ 1024 bytes.
├── Fill a capped quest with Sybil completions
│   └── MITIGATED: every completion needs an Agent ID (one per person,
│       Binance-issued, soulbound). Mass Sybil requires mass real Agent IDs.
├── Pause griefing (see T4)
│   └── MITIGATED: see T4.
├── Block gas: completeQuest gas is bounded (no unbounded loops)
│   └── VERIFIED: no loops over user-controlled collections anywhere;
│       gas report recorded in SECURITY_TEST_PLAN.md.
└── Front-end outage (Vercel/DNS)
    └── ACCEPTED: contracts remain usable via BscScan / direct RPC;
        no backend dependency.
```

### T7 — Dependency / supply-chain compromise

```
Goal: backdoor via a dependency
├── Compromised OpenZeppelin submodule
│   └── MITIGATED: pinned tag v5.0.2 + foundry.lock commit hash; any
│       change shows in git diff; OZ is a widely audited library.
├── Compromised npm package (frontend)
│   └── MITIGATED: exact-pinned versions + pnpm-lock.yaml + --frozen-lockfile
│       in CI; pnpm audit in CI (blocked in this VM — see gate doc).
├── Compromised toolchain (solc / forge)
│   └── MITIGATED: solc 0.8.24 pinned in foundry.toml; forge 1.9.0 pinned
│       in CI (M3 fix); reproducible builds.
└── Compromised GitHub Action
    └── MITIGATED: pinned major versions; no third-party actions with
        write access; permissions block added (L5 fix).
```

### T8 — Frontend / UX trust

```
Goal: trick users into wrong actions
├── Fake UI claiming a user completed a quest (no tx)
│   └── MITIGATED: UI reads chain state; every claim links to BscScan.
├── Malicious frontend swapping the contract address (phishing clone)
│   └── ACCEPTED: users must verify the domain + contract addresses
│       (documented in USER_GUIDE.md); out of contract scope.
└── Env misconfiguration (wrong chain / wrong Agent ID address)
    └── MITIGATED: env.ts validation + consistency rules (M5 fix).
```

## 5. Security design decisions (binding)

### 5.1 AgentGate

- Trusted Agent ID address + expected chainId are **immutable**, set once in
  the constructor; constructor requires code at the address and
  `expectedChainId == block.chainid`.
- `isAgentHolder` **fails closed**: wrong chain, zero account, or any
  external-call failure ⇒ `false` (never reverts, so integrators cannot be
  DoS'd by a view call).
- `requireAgentHolder` reverts with `WrongChain` / `NotAgentHolder`.
- `verify()` lets a holder record an on-chain verification (emits
  `AgentHolderVerified`).

### 5.2 QuestManager

- Roles: `QUEST_CREATOR_ROLE` (create), creator-or-admin (deactivate),
  `PAUSER_ROLE` (pause), `DEFAULT_ADMIN_ROLE` (unpause + role admin).
- `completeQuest` is `nonReentrant` + `whenNotPaused`, checks-effects-
  interactions; all state is updated before external calls to
  `Reputation`/`Achievement`.
- Validation: holder, active, time window, cap, one-time/duplicate,
  cooldown. Reward capped at 10_000. Strings capped. Badge must exist.
- Badge issuance is skipped (not reverted) if the user already holds the badge.

### 5.3 Reputation

- **No admin score function exists, by design.** Points only via
  `SCORE_SOURCE_ROLE` (`QuestManager`), capped per event (10_000).
- Full event history (`PointsAdded` with quest id) — every point is traceable.
- Pausable (admin only).

### 5.4 Achievement

- ERC-721 soulbound: transfers revert (`_update`), approvals revert
  (`approve`, `setApprovalForAll`).
- Issuance only via `ISSUER_ROLE` (`QuestManager`), one badge per
  (account, badgeId), badge must be defined first.
- Uses `_mint`, **not** `_safeMint`: no `onERC721Received` callback, so
  there is no reentrancy surface at mint time. Documented trade-off:
  badges can be minted to contracts that do not implement the ERC-721
  receiver — acceptable because badges are soulbound and ownership is
  verifiable via `ownerOf` regardless.

### 5.5 Privilege model (production)

| Power | Holder (production) |
|---|---|
| `DEFAULT_ADMIN_ROLE` on all contracts | `TimelockController` (minDelay 2 days) |
| Timelock proposers / executors | Admin multisig (Safe, threshold ≥ 2) |
| `QUEST_CREATOR_ROLE` | Campaign multisig (or timelock-gated) |
| `PAUSER_ROLE` | Admin multisig (pause fast; unpause via admin) |
| `SCORE_SOURCE_ROLE` / `ISSUER_ROLE` | `QuestManager` contract only |
| Deployer | Renounces all admin roles after setup (script-enforced) |

### 5.6 Environment consistency (M5 fix, frontend)

`apps/web/lib/env.ts` enforces:
- `NEXT_PUBLIC_CHAIN_ID` ∈ {56, 97, 31337} (allowlist).
- All addresses must be valid `0x` addresses and non-zero.
- Chain 56 ⇒ Agent ID address MUST be the official
  `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`.
- Chain 97 ⇒ Agent ID address MUST NOT be the official address (it does not
  exist on testnet).
- Chain 31337 (local/Anvil, incl. mainnet forks) ⇒ any non-zero address allowed.

## 6. Accepted risks (residual)

| # | Risk | Why accepted |
|---|---|---|
| AR-1 | Official Agent ID contract misbehaves / is compromised. | Binance-operated, soulbound, ecosystem-wide; out of AGENTHUB's control. Gate fails closed. |
| AR-2 | Multisig threshold compromise. | Bounded damage (no funds, no arbitrary points); mitigated by threshold ≥ 2 + timelock delay. |
| AR-3 | Rogue quest creator makes junk/capped-reward quests. | Visible on-chain, capped at 10_000 pts/quest, deactivatable, pausable. |
| AR-4 | Front-running of capped-quest slots. | No value at stake; victim loses only a slot. |
| AR-5 | Frontend/DNS compromise misleads users. | Chain remains source of truth; users can verify on BscScan. No signing power in frontend. |
| AR-6 | No external audit yet. | Independent review is required before mainnet (see `SECURITY_DEPLOYMENT_GATE.md`); this phase is internal hardening, not a substitute. |
| AR-7 | BSC Cancun-opcode support assumed (evm_version `cancun` pinned). | Our contracts use no transient storage and no Cancun-only opcodes (storage-based `ReentrancyGuard` verified in OZ 5.0.2 source); a testnet smoke test is a deployment-gate item before mainnet. |

## 7. Out of scope

- Security of the Binance Agent ID contract itself.
- Security of the user's wallet / device.
- BNB Chain consensus / validator behavior.
- Economic value of points/badges (there is none by design).
- The `MockAgentId` test contract (test-only; must never reach mainnet —
  enforced by `DeployMock` allowlist + deployment checklist).
