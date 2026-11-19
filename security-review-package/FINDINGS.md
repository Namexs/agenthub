# AGENTHUB — Security Findings (Review Package)

> Consolidated findings with file, function, and **line numbers** (code at
> commit `c666878`), technical exploit scenarios, and before/after code for
> every fix. Fixed and open findings are separated. Canonical detail lives
> in `reports/SECURITY_FINDINGS.md` and `reports/SECURITY_REMEDIATION.md`.

## Part A — FIXED findings (3)

### SEC-001 — AgentGate reverted instead of failing closed on malformed returndata

- **Severity:** High · **Status:** FIXED (`a597a2d`)
- **File / function / lines:** `packages/contracts/src/AgentGate.sol` ·
  `isAgentHolder(address)` · lines 44–55 (fixed code)
- **Root cause:** Solidity `try/catch` does not catch ABI-decoding errors
  of malformed returndata. The original high-level
  `IERC721Balance(...).balanceOf(account)` call decoded its return in the
  caller, so a short/garbage return reverted `isAgentHolder` instead of
  returning `false`.
- **Exploit scenario:** No attacker needed. Any deployment where the
  configured Agent ID address returns malformed data — a misconfigured
  address pointing at a non-ERC-721 contract, or an upstream change to the
  trusted contract — makes every `isAgentHolder` call revert.
  `QuestManager.completeQuest` calls `requireAgentHolder` first, so **all
  quest completions platform-wide brick** (total DoS of the core function)
  until redeployment.
- **Impact:** Complete loss of the platform's core function (quest
  completion) from a single misconfiguration. No fund loss (contracts hold
  no funds).
- **Prerequisites:** A deployment pointing at an address whose `balanceOf`
  returndata is malformed, or a change in the trusted contract's behavior.
- **PoC:** `test/AgentGate.t.sol` `test_GarbageReturnFailsClosed` — a mock
  Agent ID whose fallback returns 1 byte of garbage. Failed (revert)
  against the original code; passes against the fix.
- **Before:**
  ```solidity
  function isAgentHolder(address account) public view returns (bool) {
      if (account == address(0)) return false;
      try IERC721Balance(agentIdContract).balanceOf(account) returns (uint256 holderBalance) {
          return holderBalance > 0;
      } catch {
          return false;
      }
  }
  ```
- **After:**
  ```solidity
  function isAgentHolder(address account) public view returns (bool) {
      if (account == address(0)) return false;
      if (block.chainid != expectedChainId) return false;
      (bool success, bytes memory data) =
          agentIdContract.staticcall(abi.encodeWithSelector(IERC721Balance.balanceOf.selector, account));
      if (!success || data.length < 32) return false;
      uint256 holderBalance;
      assembly {
          holderBalance := mload(add(data, 32))
      }
      return holderBalance > 0;
  }
  ```
- **Regression test:** `test_GarbageReturnFailsClosed`,
  `test_RevertingAgentIdFailsClosed`,
  `test_MaliciousAgentIdFailsClosed` (attack sim).
- **Verification:** tests pass; full suite 120/120.

### SEC-002 — Constructors granted operational roles that survived admin renounce

- **Severity:** Medium · **Status:** FIXED (`aadf24f`)
- **File / function / lines:** `packages/contracts/src/QuestManager.sol` ·
  constructor · lines 45–57 (fixed code; the removed grant was at line 54);
  `packages/contracts/src/Achievement.sol` · constructor · lines 36–41
  (fixed code; the removed grant was at line 39)
- **Root cause:** Both constructors granted an operational role to the
  deployer alongside `DEFAULT_ADMIN_ROLE` (`PAUSER_ROLE` in QuestManager,
  `BADGE_MANAGER_ROLE` in Achievement). Renouncing admin (the production
  handover to a TimelockController) does not renounce operational roles,
  so the deployer EOA silently kept them forever.
- **Exploit scenario:** A compromised or rogue deployer key — the very key
  the renounce flow is meant to remove from the trust model — pauses
  QuestManager indefinitely: every timelock unpause (2-day delay) is
  followed by an immediate re-pause, griefing the platform into permanent
  downtime. It could also define arbitrary badge metadata.
- **Impact:** Availability (indefinite pause griefing) + integrity of badge
  definitions. No fund loss (contracts hold no funds).
- **Prerequisites:** Access to the deployer key after deployment (a
  standing privilege without the fix, not a one-time window).
- **PoC:** `test/AccessControl.t.sol` `test_PauseUnpauseRoleMatrix` failed
  with "next call did not revert as expected" — the test asserted the
  admin could not pause, but the admin held `PAUSER_ROLE` from
  construction.
- **Before (QuestManager; Achievement analogous):**
  ```solidity
  _grantRole(DEFAULT_ADMIN_ROLE, admin_);
  _grantRole(PAUSER_ROLE, admin_);
  ```
- **After (QuestManager; Achievement analogous):**
  ```solidity
  // Least privilege: the constructor grants ONLY DEFAULT_ADMIN_ROLE.
  // Operational roles (QUEST_CREATOR_ROLE, PAUSER_ROLE) MUST be
  // granted explicitly during setup. Granting them here would let
  // the deployer keep pausing/creating quests after renouncing admin
  // (SEC-002) — a retained-privilege footgun.
  _grantRole(DEFAULT_ADMIN_ROLE, admin_);
  ```
- **Regression test:** `test_DeployerLostAdminAfterRenounce` (asserts the
  deployer holds zero operational roles after renounce) +
  `test_PauseUnpauseRoleMatrix`.
- **Verification:** tests pass; full suite 120/120.

### SEC-003 — QuestManager ignored the minted badge token id (Slither unused-return)

- **Severity:** Low (Slither rated Medium; assessed Low — observability
  only, no state/funds/access impact) · **Status:** FIXED (`ee7592e`)
- **File / function / lines:** `packages/contracts/src/QuestManager.sol` ·
  `completeQuest(uint256)` · lines 135–138 (fixed code);
  `packages/contracts/src/interfaces/IQuestManager.sol` · `QuestCompleted`
  event · lines 46–49
- **Root cause:** `completeQuest` called `achievement.issue(...)` and
  discarded its `uint256 tokenId` return value.
- **Exploit scenario:** None exploitable. Indexers and the frontend could
  not learn the badge token id from the completion event and needed a
  second lookup (`hasBadge` / `BadgeIssued` event).
- **Impact:** Event observability only.
- **Prerequisites:** N/A (not exploitable).
- **PoC:** Slither 0.11.6, detector `unused-return`, first run.
- **Before:**
  ```solidity
  reputation.addPoints(msg.sender, quest.rewardPoints, questId);
  if (quest.badgeId != 0 && !achievement.hasBadge(msg.sender, quest.badgeId)) {
      achievement.issue(msg.sender, quest.badgeId); // return value discarded
  }
  emit QuestCompleted(questId, msg.sender, quest.rewardPoints);
  ```
  ```solidity
  event QuestCompleted(uint256 indexed questId, address indexed account, uint256 rewardPoints);
  ```
- **After:**
  ```solidity
  reputation.addPoints(msg.sender, quest.rewardPoints, questId);
  uint256 badgeTokenId = quest.badgeId != 0 && !achievement.hasBadge(msg.sender, quest.badgeId)
      ? achievement.issue(msg.sender, quest.badgeId)
      : 0;
  emit QuestCompleted(questId, msg.sender, quest.rewardPoints, badgeTokenId);
  ```
  ```solidity
  event QuestCompleted(
      uint256 indexed questId, address indexed account, uint256 rewardPoints, uint256 badgeTokenId
  );
  ```
- **Regression test:** `test_QuestCompletedEventCarriesBadgeTokenId`,
  `test_QuestCompletedEventHasZeroTokenIdWithoutBadge`.
- **Verification:** tests pass; Slither re-run: `unused-return` gone.

## Part B — OPEN findings (2 accepted, 0 exploitable)

### SEC-004 — Quest windows and cooldowns depend on `block.timestamp` (Slither timestamp ×3)

- **Severity:** Low · **Status:** OPEN — accepted risk (documented, no code
  change)
- **File / function / lines:** `packages/contracts/src/QuestManager.sol` ·
  `createQuest` line 76; `completeQuest` lines 107–108, 118;
  `nextCompletionAt` line 183
- **Exploit scenario:** A block producer shifts timestamps by seconds; a
  user completes a daily quest a few seconds before the cooldown truly
  expires, or enters a quest a few seconds early.
- **Impact:** Seconds of early access to a capped reward (≤ 10,000 points
  per completion). No fund loss, no double award (one-time quests stay
  one-time). Windows/cooldowns are measured in days; the gain is seconds.
- **Prerequisites:** Control of block production, or luck, for a
  seconds-level gain.
- **Why accepted:** Any on-chain time source has this property; block
  numbers are worse on BSC (variable block times). No remediation preserves
  the feature.

### SEC-006 — Slither Informational findings (reviewed, intentional)

- **Severity:** Informational · **Status:** OPEN — accepted (4 detectors)
- **Findings:**
  1. `assembly` — `AgentGate.isAgentHolder`, lines 51–53. Intentional: the
     single `mload` is the SEC-001 fix; safe (length-checked first).
  2. `low-level-calls` — `AgentGate.isAgentHolder`, lines 47–48.
     Intentional: the `staticcall` is the SEC-001 fix; return fully
     checked; `staticcall` cannot change state.
  3. `pragma` — `^0.8.20` (OpenZeppelin) vs `^0.8.24` (our files). Not an
     issue: `foundry.toml` pins solc 0.8.24 and CI pins Foundry 1.9.0.
  4. `cyclomatic-complexity` — `QuestManager.completeQuest`, complexity 12.
     Linear guard clauses, each independently tested (32 tests).

## Part C — CLOSED as false positive (1)

### SEC-005 — Slither `uninitialized-local` on `badgeTokenId`

- **Severity:** Informational · **Status:** CLOSED — false positive.
  Reported in intermediate runs, reviewed as a false positive, and
  **absent from the final run** (verified twice: 7 detectors, 0 Medium).
- **File / function / lines:** `packages/contracts/src/QuestManager.sol` ·
  `completeQuest(uint256)` · line 135
- **Proof:** The variable is initialized in its declaration (ternary, both
  branches produce a value); Solidity value types are zero-initialized by
  default; both branches are covered by tests asserting the emitted value.
  No code change was made to silence the detector.
