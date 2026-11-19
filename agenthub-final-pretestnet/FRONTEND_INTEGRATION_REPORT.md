# AGENTHUB — Frontend Integration Report (Phase 7)

**Date:** 2026-11-19. **Scope:** `apps/web` (Next.js 14 + wagmi 2.12 +
viem 2.21), `packages/shared` types, `packages/contracts/script`
(ABI export + local test stack).

## 1. What changed

The website no longer shows sample data. Every page now reads from the
real contracts when they are deployed, and says so honestly when they
are not:

| Page           | Before (Phase 1)                 | Now (Phase 7)                                                                                                                                                                                 |
| -------------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/` (home)     | Static copy + Agent ID balanceOf | Same layout; Agent ID check via AgentGate (balanceOf fallback); copy updated                                                                                                                  |
| `/quests`      | Static launch catalogue          | Live `questCount` + `getQuest` (multicall) + per-quest completion state; Complete button with full tx lifecycle; attestation form for Attested quests; static catalogue only while undeployed |
| `/dashboard`   | "— pts" placeholders             | Live points / level / scoring events / badges earned / completions + recent activity (5 latest txs)                                                                                           |
| `/profile`     | 4 hardcoded locked badges        | Live badge catalogue (BadgeDefined events) + ownership (BadgeIssued events) + live reputation                                                                                                 |
| `/leaderboard` | Empty table                      | Live ranking from QuestCompleted + PointsAdded events, deduplicated, paginated (10/page), last-updated time, refresh                                                                          |
| `/history`     | "No transactions yet"            | Merged QuestCompleted + PointsAdded + BadgeIssued + AttestationUsed history, newest first, BscScan links                                                                                      |
| `/campaigns`   | "No campaigns yet"               | Lists live Community-type quests with completion actions                                                                                                                                      |
| Global         | No chain guard                   | `ChainGuard` banner on every page when the wallet is on the wrong chain, with one-click switch                                                                                                |

## 2. Architecture

**Stack (unchanged, now fully used):** wagmi + viem + React Query.
Injected wallet only (Binance Wallet / MetaMask); the connect button is
labelled "Connect Binance Wallet". No backend, no session, no signature
login — pure on-chain reads + user-confirmed writes.

**ABIs:** exported from the Foundry build by
`packages/contracts/script/export-abis.mjs` into committed TypeScript
modules (`apps/web/lib/abis/*.ts`, `as const` — JSON imports cannot
carry the literal types wagmi needs for function-name inference,
TS1355). Regenerate after any contract change; the current export
includes the Phase 5/6 changes (validator registry,
`emergencyRevokeValidator`, `AttestationUsed` with signer).

**Pure lib modules (unit-testable, no React):**

- `lib/quests.ts` — `mapQuest` (on-chain struct → shared type),
  `questEligibility` (mirrors the contract's checks for the UI),
  `validationKindLabel` (honest labels per QUEST_VALIDATION_DESIGN.md §3).
- `lib/attestation.ts` — EIP-712 domain/types, `recoverAttestationSigner`,
  `checkAttestation` (shape, deadline bounds, recovery). Async: viem 2.x
  recovery is async (ERC-6492).
- `lib/events.ts` — `computeLevel` (1-based, mirrors the contract),
  `aggregateLeaderboard` (dedup by txHash+logIndex), `buildTxHistory`
  (merged, newest-first), explorer URL helpers, event signatures.

**Hooks:** `useAgentId` (AgentGate-first), `useChainGuard`,
`useQuests`, `useCompleteQuest` (both completion paths, full tx
lifecycle), `useAttestation` (client-side verify + on-chain role check),
`useReputation`, `useAchievements`, `useLeaderboard`,
`useTxHistory`, `useContractLogs` (shared one-shot log fetcher).

**Event queries start at `NEXT_PUBLIC_DEPLOY_BLOCK`** — never from
genesis, which public RPCs refuse over large ranges. Unset = the
event features show "not configured" instead of guessing.

**Shared types:** `Quest` gained `validationKind` + `validator`;
`ValidationKind` enum and `TxHistoryEntry` added.

## 3. Attestation flow (honest design)

There is deliberately **no "request attestation" backend**: the verifier
is off-chain by design (see VERIFIER_ROLE_SOP.md). The flow is:

1. The user obtains a signature + deadline from a verifier out-of-band.
2. They paste it into the `AttestationForm` on an Attested quest.
3. The frontend VERIFIES client-side: signature shape, deadline bounds
   (expired / > 7 days), signer recovery, current nonce, and the
   recovered signer's `VERIFIER_ROLE` on-chain.
4. Only a fully valid attestation enables Submit.
5. Submit calls `completeQuestWithAttestation`; the UI shows
   pending → confirming → confirmed (or failed). A submitted tx is
   NEVER shown as "done" before the receipt confirms success.
6. The contract re-verifies everything on-chain — the client-side check
   is a UX guard, not the security boundary.

## 4. What was tested — and what was NOT

**Tested (this phase):**

- **Anvil integration (live chain):** `apps/web/scripts/run-anvil-integration.sh`
  starts anvil, deploys a full stack (`DeployLocalTestStack.s.sol`:
  3 quests, 2 badges, approved validator, 2 Agent ID holders, alice
  completes all 3 quests incl. a real EIP-712 attestation), then runs
  **27/27 node checks** (viem, the exact RPC patterns the hooks use)
  and **4/4 vitest tests** importing the REAL frontend lib
  (`mapQuest`, `questEligibility`, `checkAttestation`,
  `aggregateLeaderboard`, `buildTxHistory`) against the live chain.
  Log: `logs/phase7-anvil-integration.log`.
- **Bug found by the anvil test:** `computeLevel` was 0-based while the
  contract's levels are 1-based (250 points = level 2, not 1). Fixed in
  `lib/events.ts`; the node check and the vitest test now assert the
  aggregated level against the contract's `level()` directly.
- **Web validation:** `tsc` clean, `next lint` clean, `vitest` 16/16
  (+ 4 anvil tests skipped without a live chain), `next build` 11/11
  static pages.
- **Foundry suite unchanged:** 255/255 after the Phase 7 contract-side
  changes (foundry.toml `fs_permissions` for the deploy script's JSON
  output; no contract code changed in this phase).

**NOT tested (honest gaps):**

- **No live testnet connection.** The contracts are not deployed to BSC
  testnet yet, so no page has ever read testnet state. The anvil test
  proves the integration layer against a local chain with the same
  contracts and the same RPC patterns — it does not prove testnet RPC
  behavior (rate limits, `getLogs` ranges, latency). The first testnet
  deploy must be followed by a live smoke test of every page.
- **No browser test.** There is no E2E (Playwright) run — see Phase 8
  for the environment assessment. The hooks are exercised through
  their RPC patterns (node checks) and their pure functions (vitest),
  not through a rendered browser.
- **No wallet-connection test.** The injected-wallet flow (Binance
  Wallet prompt, chain switch) cannot be tested without a real wallet
  in a browser. The chain guard and connect button are code-reviewed,
  not click-tested.

## 5. Configuration for testnet

When the contracts deploy to BSC testnet (97), set:

```env
NEXT_PUBLIC_CHAIN_ID=97
NEXT_PUBLIC_AGENT_ID_ADDRESS=<MockAgentId on 97>
NEXT_PUBLIC_AGENT_GATE_ADDRESS=<AgentGate on 97>
NEXT_PUBLIC_QUEST_MANAGER_ADDRESS=<QuestManager on 97>
NEXT_PUBLIC_REPUTATION_ADDRESS=<Reputation on 97>
NEXT_PUBLIC_ACHIEVEMENT_ADDRESS=<Achievement on 97>
NEXT_PUBLIC_DEPLOY_BLOCK=<block the contracts deployed at>
```

The env validation (M5) rejects a mainnet Agent ID on testnet and vice
versa. The local anvil setup (`NEXT_PUBLIC_CHAIN_ID=31337` + the
`.anvil-deployment.json` addresses) is for development only.

## 6. Files changed (Phase 7)

- New: `lib/abis/*.ts` (4 generated), `lib/attestation.ts`,
  `lib/events.ts`, `hooks/useChainGuard.ts`, `hooks/useCompleteQuest.ts`,
  `hooks/useAttestation.ts`, `hooks/useAchievements.ts`,
  `hooks/useLeaderboard.ts`, `hooks/useTxHistory.ts`,
  `hooks/useContractLogs.ts`, `components/ChainGuard.tsx`,
  `components/QuestCardLive.tsx`, `components/AttestationForm.tsx`,
  `components/TxHistoryList.tsx`, `lib/anvil-integration.test.ts`,
  `scripts/anvil-integration.mjs`, `scripts/run-anvil-integration.sh`,
  `packages/contracts/script/export-abis.mjs`,
  `packages/contracts/script/DeployLocalTestStack.s.sol`.
- Rewritten: `hooks/useAgentId.ts`, `hooks/useQuests.ts`,
  `hooks/useReputation.ts`, `app/quests|dashboard|profile|leaderboard|history|campaigns/page.tsx`,
  `lib/contracts.ts`, `lib/quests.ts` (extended), `components/QuestCard.tsx`
  (now the static-preview card), `components/AgentIdStatus.tsx`.
- Updated: `lib/env.ts` (deploy block), `lib/chains.ts` (anvil),
  `lib/wagmi.ts` (anvil), `lib/chains.test.ts` (3 chains),
  `packages/shared/src/types.ts`, `app/layout.tsx` (ChainGuard),
  `app/page.tsx` (copy), `components/ConnectButton.tsx` (label),
  `packages/contracts/foundry.toml` (fs_permissions),
  `.prettierignore` (generated ABIs), `.gitignore` (anvil artifacts).
