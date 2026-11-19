# AGENTHUB — Security

## 1. Principles

- **Security first, non-custodial always.** AGENTHUB holds no user assets.
  There is no vault, no deposit, no pooled fund to drain.
- **Verify, don't trust.** Every feature is provable on-chain. The frontend
  displays only what the chain says.
- **Least privilege.** Roles are narrow; admin powers are documented and
  minimal; production admin actions require multisig.
- **No secrets in the repo.** Keys live in environment/CI secrets only.

## 2. Hackathon red lines (from the Binance announcement)

These are hard rules, enforced by architecture — not policy:

| Red line                                           | How AGENTHUB complies                                                                                                                                                  |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No web-based QR login for Agentic Wallet           | Wallet connects via the injected provider in the user's own wallet app. No QR, no pairing code, no third-party login page.                                             |
| No bypassing user transaction confirmation         | Every state-changing action is a transaction the user reviews and confirms in their wallet.                                                                            |
| No unauthorized asset transfers                    | The contracts move no assets at all (no token/NFT transfers except soulbound badge mints to the completing user). No scheduled collection, no bundled extra transfers. |
| No unlimited approvals                             | The frontend never requests token approvals. There is no approval flow in the product.                                                                                 |
| Contracts open-source, owner permissions disclosed | Source is public, verified on BscScan; roles and permissions are documented here and in `ARCHITECTURE.md`.                                                             |
| No Binance brand impersonation                     | The name AGENTHUB and its domains do not use "Binance"/"BNB" as a brand. "BNB Chain" is named only as the deployment network.                                          |
| No collection of sensitive credentials             | No seed phrase, private key, API secret, or pairing code is ever requested, stored, or transmitted.                                                                    |
| No promised returns                                | Quests award reputation points and badges — recognition, not income. No "passive income" or earnings claims anywhere.                                                  |

## 3. Layered defense

| Threat                  | Protection                                                                                                                                      |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Reentrancy              | OpenZeppelin `ReentrancyGuard` on state-changing external functions; checks-effects-interactions ordering.                                      |
| Fake Agent ID           | AgentGate trusts exactly one immutable contract address per chain (official on mainnet, mock on testnet/local); chainId validated at deploy.    |
| Sybil / fake accounts   | One profile per Agent ID-holding address; Agent IDs themselves are one-per-person, soulbound, and Binance-issued.                               |
| Replay attack           | Any signed off-chain action (Phase 2, if added) uses EIP-712 with nonce + domain separation. On-chain actions need no signatures.               |
| Reputation manipulation | Points increase only via `QuestManager` after validated completion. No admin score function exists. All changes emit events.                    |
| Spam transactions       | Cooldowns (daily 24h, weekly 7d), one-time quest rules, `maxCompletions` caps.                                                                  |
| Admin abuse             | Role separation (`DEFAULT_ADMIN_ROLE`, `QUEST_CREATOR_ROLE`, issuer roles); production admin = multisig + timelock for upgrades.                |
| Contract bugs           | Unit + fuzz + invariant tests per contract; build order AgentGate → QuestManager → Reputation → Achievement; independent review before mainnet. |
| Frontend compromise     | Frontend holds no secrets and no signing power; worst case is a misleading UI, which users can cross-check on BscScan.                          |
| Service outage          | Frontend is static hosting (Vercel); chain data remains valid and readable via any explorer or RPC.                                             |

## 4. Roles and permissions

The full role matrix is `docs/ROLE_MATRIX.md` (single source of truth).
Summary of the production default:

| Role                       | Powers                                | Held by (production)                                           |
| -------------------------- | ------------------------------------- | -------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE`       | Grant/revoke roles, unpause           | TimelockController (2-day delay; multisig proposes + executes) |
| `PAUSER_ROLE`              | Emergency pause (no delay)            | Admin multisig (verified Safe)                                 |
| `QUEST_CREATOR_ROLE`       | Create/deactivate quests              | Campaign team / vetted creators                                |
| `VERIFIER_ROLE`            | Sign EIP-712 attestations (off-chain) | Named verifiers (see `VERIFIER_ROLE_SOP.md`)                   |
| `SCORE_SOURCE_ROLE`        | `Reputation.addPoints`                | QuestManager contract only                                     |
| `ISSUER_ROLE`              | `Achievement.issue`                   | QuestManager contract only                                     |
| `BADGE_MANAGER_ROLE`       | `Achievement.defineBadge`             | Admin multisig                                                 |
| Timelock proposer/executor | Schedule/execute timelock proposals   | Admin multisig                                                 |
| Any role                   | —                                     | **Deployer: NONE after deployment**                            |

There is intentionally **no role that can set an arbitrary reputation score**,
transfer badges, or move user assets. Unpause is deliberately slow
(timelock, 2 days) so a compromised pauser can stop the platform but
cannot resume it alone.

## 5. Emergency procedures

- **Pause (fast path):** `QuestManager.pause()` via `PAUSER_ROLE`
  (admin multisig, no timelock delay). Pausing stops new completions —
  and therefore all new points and badges, since both flow only through
  completions. Reads (points, badges, leaderboard) keep working.
  `Reputation` and `Achievement` are also pausable, but their
  `pause()`/`unpause()` are admin-only (timelock, 2-day delay).
- **Unpause is slow on purpose:** `QuestManager.unpause()` needs
  `DEFAULT_ADMIN_ROLE` (the timelock), so a compromised pauser cannot
  resume the platform alone. Worst case ~4 days paused in a
  pause → revoke → unpause incident sequence (see
  `VERIFIER_ROLE_SOP.md` §4).
- **Incident response:** pause first, disclose what happened, fix, and only then
  unpause. Post-mortems are public in the repo.
- **Upgrade policy:** Phase 1 contracts are non-upgradeable by design. If an
  upgrade path is ever added, it requires multisig + timelock + public notice.

## 6. What Phase 1 does NOT yet cover

- Full contract implementations and their test suites (Phase 2).
- Independent security review / audit before mainnet (required — see
  `docs/DEPLOYMENT.md` checklist).
- Bug bounty / responsible disclosure channel (to be added before mainnet).
- Monitoring and alerting for abnormal on-chain activity (Phase 2+).

## 7. Reporting a vulnerability

Until a dedicated channel exists, report via the repository's issue tracker
with the `security` label. Do not exploit a suspected vulnerability to
demonstrate it — report it and let the team reproduce it on testnet.
