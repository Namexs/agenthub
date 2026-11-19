# AGENTHUB — User Guide

> Phase 1 note: the contracts are not deployed yet, so quests, points, and
> badges are previews. This guide describes the product as it will work after
> the Phase 2 testnet deploy.

## 1. What is AGENTHUB?

AGENTHUB is the activity and reputation hub for Binance Agent ID holders.
Complete quests, earn on-chain reputation points, collect soulbound badges,
and climb a leaderboard that anyone can audit — all on BNB Chain.

## 2. Before you start

- An EVM wallet (Binance Wallet, MetaMask, or similar).
- A Binance Agent ID (claim it in the Binance App: Wallet → Agent ID banner).
  Only Agent ID holders can complete quests.
- A little BNB for gas (testnet: tBNB from the faucet; mainnet: real BNB).
  Quests themselves are free — you only pay gas.

## 3. Connect and verify

1. Open the app and click **Connect Wallet**.
2. Approve the connection in your wallet. AGENTHUB never asks for your seed
   phrase or private key — if something does, it is a scam.
3. The dashboard shows your Agent ID status, read live from the Agent ID
   contract (`balanceOf > 0`). No Agent ID → quests stay locked.

## 4. Complete a quest

1. Go to **Quests** and pick one (daily check-in, one-time, weekly, or
   community).
2. Click to complete it. Your wallet asks you to confirm **one transaction**.
   Review it — it calls only `QuestManager.completeQuest`.
3. Once confirmed, your points and any badge update on-chain. The transaction
   link takes you to BscScan for proof.

Rules: one-time quests can be completed once per wallet; daily quests have a
24-hour cooldown; each quest shows its time window and reward before you start.

**Attested quests** (marked "Verified by an AGENTHUB verifier") work
differently: the task happens off-chain, so one or more verifiers must
sign that you did it. The quest shows how many signatures it requires —
"Requires 2 verifier signatures", for example. Contact the verifiers
out-of-band (there is no request button in the app); each verifier signs
the same deadline for your address, you paste all the signatures into the
form, and the app verifies every signer before the submit button enables.
All signatures must be from different verifiers and share one deadline —
if you complete another attested quest first, the signatures go stale and
must be re-collected.

## 5. Reputation and levels

Points come only from validated quest completions. Levels:

| Level | Points needed |
| ----- | ------------- |
| 1     | 0             |
| 2     | 100           |
| 3     | 300           |
| 4     | 700           |
| 5     | 1,500         |

Nobody — not even an admin — can grant points by hand. Your history is public
and permanent.

## 6. Badges

Badges are soulbound ERC-721 tokens: they cannot be transferred or sold.
Anyone can verify you hold one via the contract (`hasBadge`) or BscScan.
Losing access to your wallet means losing access to your badges — keep your
wallet safe.

## 7. Leaderboard

Ranked by validated activity (points, then quests completed). The ranking is
recomputed from on-chain events, so it cannot be gamed by refreshing a page
or editing a profile.

## 8. Campaigns

Project teams run campaigns with their own quests. Joining a campaign works
like any other quest — one confirmed transaction, points and badges on-chain.

## 9. FAQ

**Does AGENTHUB hold my crypto?** No. It is non-custodial; it never takes
deposits or holds assets.

**Why do I need an Agent ID?** Agent ID is the identity layer — one per
person, non-transferable — which keeps reputation meaningful and Sybil-resistant.

**I completed a quest but my points did not change.** Check the transaction on
BscScan: if it succeeded, the points are on-chain and the UI will catch up on
refresh. If it reverted, the quest rules (cooldown, window, already completed)
explain why.

**Can I delete my profile?** On-chain records are permanent by design. You can
simply stop using the app; nothing further is recorded.

**Is this affiliated with Binance?** No. AGENTHUB is an independent project
built for the Binance Agent ID Hackathon. It uses the official Agent ID
contract as its identity source.
