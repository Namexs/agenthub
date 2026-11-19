# AGENTHUB — Frontend Final Acceptance (Phase F)

**Date:** 2026-11-19. **Phase:** F — Frontend & wallet audit.
**Scope:** the complete Next.js app (8 routes, 9 hooks, 12
components, 5 lib modules) — 11 areas, plus a new real-browser
wallet E2E suite that covers the connected flows the unconnected
smoke test explicitly excluded.
**Verdict: GATE F — PASSED.** All 11 areas verified. Wallet E2E
**25/25** in a real Chromium against a live anvil chain, including
a full attested-quest completion. Zero console errors, zero page
errors. No fake live data, no hardcoded production addresses. Two
test-infrastructure bugs were found and fixed in this phase (both
in the runners, not the app).

## 1. The 11 areas — verdicts

| #   | Area                           | Verdict | Evidence                                                                                                                                                                                                                                                                                                                                    |
| --- | ------------------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Wallet connection              | PASS    | wagmi `injected()` connector only (Binance Wallet / MetaMask / any EVM wallet); `ConnectButton` connects/disconnects, shows the truncated address. Proven live: wallet E2E connects bob's injected test wallet and the address renders (`0x3C44…93BC`).                                                                                     |
| 2   | Chain detection (BNB Testnet)  | PASS    | `env.ts` allowlist is exactly {56, 97, 31337}, default 97; M5 chain↔Agent ID consistency enforced at startup (mainnet requires the official Agent ID; testnet forbids it). `wagmi.ts` chains follow the validated env chain id.                                                                                                            |
| 3   | Network switching              | PASS    | `useChainGuard` + global `ChainGuard` banner: wrong chain shows a plain banner with a one-click `switchChain` to the expected chain; reads/writes are disabled (`isSupported`) until the chain matches. Covered by hook tests; the switch itself needs a real multi-chain wallet (see §5).                                                  |
| 4   | Agent ID verification          | PASS    | `useAgentId` reads `AgentGate.isAgentHolder` — the same check the contracts enforce — with a direct `balanceOf` fallback only when the gate is undeployed. Honest states: not-connected / not-configured / checking / verified / not-found (with the checked address + source). Proven live: bob verified in the wallet E2E.                |
| 5   | Quest listing / completion     | PASS    | `useQuests` reads `questCount` + `getQuest` per id (multicall) + `hasCompleted`/`nextCompletionAt` per quest; `questEligibility` mirrors the contract's checks and disables the button with the right reason. Proven live: all 3 on-chain quests listed; q1 completed in-browser with on-chain verification (hasCompleted true, 50 points). |
| 6   | Attestation submission         | PASS    | Full flow proven live in the wallet E2E: toggle → paste signature + deadline → client-side verify (signer holds VERIFIER_ROLE) → submit → confirmed; on-chain `hasCompleted(bob, q3)` true, points 150. See also Phase E (12/12 lifecycle points).                                                                                          |
| 7   | Reputation updates             | PASS    | `useReputation` reads points/level/totalEvents directly + `PointsAdded` history; no write path by design (points only via validated completions). Proven live: dashboard shows 50 pts after q1 (150 after q3 on-chain). `computeLevel` is 1-based and matches the contract (anvil caught the 0-based bug earlier).                          |
| 8   | Badge display                  | PASS    | `useAchievements` builds the catalogue from `BadgeDefined` events and ownership from `BadgeIssued` events (soulbound ⇒ event history IS ownership). Issued-but-undefined badges show with an honest `Badge #N` placeholder name. No transfer function exists anywhere in the app.                                                           |
| 9   | Leaderboard event aggregation  | PASS    | `aggregateLeaderboard` deduplicates by (txHash, logIndex), takes points from `PointsAdded` (authoritative) and counts from `QuestCompleted`, sorts points desc + address asc (stable), paginates 10/page, shows the last-fetch time as the snapshot time. Unit-tested in `events.test.ts`.                                                  |
| 10  | Tx history                     | PASS    | `useTxHistory` merges 4 event types for the account, newest first, every entry keeping its tx hash for the BscScan link; same-transaction logs appear as separate rows (correct — they are separate logs). Empty state: "No transactions yet…".                                                                                             |
| 11  | Loading / error / empty states | PASS    | Every data page implements the full ladder: not-deployed → loading → error (with the message) → empty → data. Verified by reading all 8 pages + components; no page renders a spinner forever or a blank list without explanation.                                                                                                          |

## 2. Cross-cutting checks

- **No fake live data.** While undeployed, the quests page shows
  the static launch catalogue with the honest label "Launch
  catalogue preview — these quests go on-chain with the testnet
  deploy." The deployed label ("Live quests from QuestManager")
  appears only when the contracts are configured. The E2E smoke
  asserts the undeployed page does NOT claim live data; the wallet
  E2E asserts the deployed page shows the live label and NOT the
  preview label.
- **No hardcoded production addresses.** A grep over `app/`,
  `components/`, `hooks/`, `lib/` (excluding tests + generated
  ABIs) finds exactly one hardcoded address: the official Agent
  ID `0x60B926…B022F` in `lib/env.ts` — the M5 consistency
  constant, identical to the contract's, not a deployment address.
  All deployment addresses come from `NEXT_PUBLIC_*` env vars
  (validated by zod: 0x format, non-zero). The shared
  `AGENT_ID_TESTNET_ADDRESS_PLACEHOLDER` is the zero address and
  unused outside its definition + tests.
- **ABI correct.** Phase E verified the committed frontend ABIs
  are byte-identical to the current forge build output
  (re-export produced zero diff), including
  `completeQuestWithAttestation(uint256, uint256, bytes)` and all
  5 event signatures used by `EVENT_SIGNATURES`.
- **Event indexing correct.** `useContractLogs` queries from
  `NEXT_PUBLIC_DEPLOY_BLOCK` (never genesis — public RPCs refuse
  large ranges); when the deploy block is unset it reports a
  configuration error instead of guessing. Aggregation dedupes by
  (txHash, logIndex). One-shot fetch (not a live subscription) —
  refetch on mount + manual refresh; documented as a later
  addition, not a defect.
- **Chain config correct.** See area 2. The anvil transport is
  hardcoded to `http://127.0.0.1:8545` (local only); BSC chains
  use viem's default `http()` transports.
- **Tx error handling correct.** `useCompleteQuest` exposes the
  full lifecycle (pending → confirming → success / failed) and
  the UI never shows "done" at submit time. A failing completion
  surfaces the error text in the card. Proven live: bob's q2
  attempt (validator rejects him — 0 TEST tokens) shows no false
  success and leaves on-chain state unchanged.
- **Mobile responsive.** 38 responsive (`sm:`/`md:`/`lg:`)
  utilities across all 8 pages + Navbar (separate scrollable nav
  row on small screens) + ChainGuard. Wallet E2E at 375×667:
  zero horizontal overflow on /quests, wallet button visible.
- **0 console errors.** E2E smoke 23/23 (Phase C) and wallet E2E
  25/25 both assert zero page errors and zero console errors.
- **Build warnings (pre-existing, non-blocking).** `next build`
  warns about two unresolvable optional modules from wagmi's
  transitive deps (`encoding` via @metamask/sdk,
  `pino-pretty` via @walletconnect/logger). The build succeeds
  (8 routes, all static). These come from connector packages the
  app does not use (only `injected()` is configured); silencing
  them would mean webpack aliases for unused code — not worth
  touching for testnet.

## 3. Wallet E2E — the new suite (this phase)

The unconnected smoke test (`e2e-smoke.mjs`) explicitly excluded
wallet flows ("no wallet in headless Chromium"). Phase F closes
that gap with `apps/web/scripts/wallet-e2e.mjs` +
`run-wallet-e2e.sh`:

- **Method:** anvil + local test-stack deploy → production build
  against the anvil deployment → `next start` → Playwright with
  a minimal injected EIP-1193 provider (`page.addInitScript`)
  bridging `window.ethereum` to a Node-side viem account holding
  bob's **throwaway anvil test key**. The script refuses to run
  against any chain other than 31337. It exercises the app's
  REAL wagmi `injected()` connector path (connect, chain read,
  sendTransaction, receipt waiting). It is NOT MetaMask/Binance
  Wallet — see §5.
- **Result: 25 passed, 0 failed** (log:
  `logs/phase-f-wallet-e2e.log`). Coverage: connect + address
  display; Agent ID verified; live quest list (3 quests) + no
  preview label; q1 CheckIn completion in-browser with on-chain
  verification (50 pts); dashboard 50 pts; full q3 attestation
  flow (sign in Node → paste → verify role → submit → 150 pts
  on-chain); q2 negative test (no false success, on-chain stays
  false); mobile 375px (no overflow, wallet button visible); 0
  page/console errors.
- **Iterations (honest record):** run 1 went 18/20 — both
  failures were test bugs (the attestation form sits behind a
  "Submit attestation" toggle the test didn't click; the q2
  assertion counted a global 'Completed ✓' that legitimately
  belongs to q3). Run 2 failed at startup because run 1's
  server survived (trap bug, see §4). Run 3 went 24/25 (the q2
  assertion again — same root cause, fixed by scoping the check
  to q2's own button). Run 4: 25/25.

## 4. Fixes made in this phase

| Change                                                               | Why                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/web/scripts/wallet-e2e.mjs` + `run-wallet-e2e.sh` (new)        | Connected-wallet E2E coverage that did not exist. Runner has `pipefail` (a failing test must fail the runner) and a pre-flight port check.                                                                                                                                                                                                                                                                |
| Runner cleanup fix (both `run-wallet-e2e.sh` and `run-e2e-smoke.sh`) | `npx next start` spawns sh → next-server; killing only the npx PID orphaned next-server on the port (a stale :3100 server from an earlier run and a stale :3101 server were found and killed). Servers now start under `setsid` with their own process group, PID shared via pidfile (the piped block is a subshell), cleanup kills the whole group. Verified: no processes/listeners remain after run 4. |
| `.gitignore`: wallet-E2E runner logs                                 | Same pattern as the existing `.anvil.log` / `.e2e-server.log` entries.                                                                                                                                                                                                                                                                                                                                    |
| `e2e-smoke.mjs` header comment                                       | It still claimed playwright was "NOT in package.json" and symlinked — false since Phase C (declared devDependency).                                                                                                                                                                                                                                                                                       |

No application code (`app/`, `components/`, `hooks/`, `lib/`)
was changed in this phase — the audit found no app defect to fix.

## 5. Observations (non-blocking) + residual gaps

- **ConnectButton label vs connector.** The button says "Connect
  Binance Wallet" but the connector is generic `injected()` —
  MetaMask or any EVM wallet connects through it. A branding
  choice for the Binance hackathon, not a functional bug; the
  label could say "Connect wallet" if the team wants neutrality.
- **OnChain quests are not pre-validated off-chain.** The
  eligibility check does not call the validator, so a user who
  fails the on-chain condition sees an enabled button and gets a
  reverting attempt (surfaced as an error, no false success, no
  tx sent — gas estimation fails first). A pre-check via
  `eth_call` would be nicer UX; not required for testnet.
- **`NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` is accepted but
  unused.** WalletConnect is documented as a later addition; the
  env var is harmless. Only injected wallets are supported.
- **Real wallet-app check still outstanding.** The injected stub
  proves the wagmi path, not a real Binance Wallet / MetaMask
  build (extension popups, chain-switch prompts, mobile
  deep-links). A manual connected check with a real wallet app
  on BSC testnet remains a pre-mainnet item (testnet staging
  checklist, Phase H). No production wallet or key was used or
  touched in this phase.
- **No live event subscription.** Event features refetch on
  mount/refresh; a new completion elsewhere does not push into
  an open page. Documented as a later addition.
- **Network-switch click path** (`wallet_switchEthereumChain`)
  is unit-tested (hook tests) but was not exercised against a
  real multi-chain wallet in this phase — same manual-testnet
  item as above.

## 6. Evidence index

- `logs/phase-f-wallet-e2e.log` — wallet E2E 25/25 (run 4).
- `apps/web/scripts/wallet-e2e.mjs`, `run-wallet-e2e.sh` — the
  suite + runner (new files, this phase).
- `apps/web/scripts/run-e2e-smoke.sh`, `e2e-smoke.mjs` — runner
  cleanup fix + stale-comment fix.
- `.gitignore` — runner log entries.
- E2E smoke 23/23 + anvil integration 27/27 + 4/4 (Phase C
  clean-copy logs, unchanged by this phase).
- Web vitest 136 + 4 skip incl. 50 hook tests + 8
  `useContractLogs` tests (Phase C clean-copy run).

**Commits:** Phase F commit (this report + wallet E2E suite +
runner fixes + log).
