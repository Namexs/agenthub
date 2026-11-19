# AGENTHUB — Security Remediation

> How each fixed finding was remediated, with before/after code. Only the
> three fixed findings (SEC-001, SEC-002, SEC-003) have code changes; the
> accepted/false-positive findings (SEC-004, SEC-005, SEC-006) are
> documented in `SECURITY_FINDINGS.md` and need no remediation.

## SEC-001 — AgentGate fail-closed returndata parsing (High, fixed in `a597a2d`)

**File:** `packages/contracts/src/AgentGate.sol`, `isAgentHolder(address)`
(lines 44–55 after the fix).

**Before** (never committed — written, proven broken by
`test_GarbageReturnFailsClosed`, and fixed in the same commit):

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

Why it was wrong: `try/catch` catches reverts from the external call, but
ABI-decoding of the returndata happens in the _caller_ — a short or
malformed return (fewer than 32 bytes) reverts the decoding itself, outside
the `try` region, so `isAgentHolder` reverted instead of returning `false`.

**After:**

```solidity
function isAgentHolder(address account) public view returns (bool) {
    if (account == address(0)) return false;
    (bool success, bytes memory data) = agentIdContract.staticcall(
        abi.encodeWithSelector(IERC721Balance.balanceOf.selector, account)
    );
    if (!success || data.length < 32) return false;
    uint256 holderBalance;
    assembly {
        holderBalance := mload(add(data, 32))
    }
    return holderBalance > 0;
}
```

Why it is right: the low-level `staticcall` never ABI-decodes in the
caller — the raw bytes are length-checked first, then the first word is
read with a single `mload`. Any failure mode (revert, short return,
garbage) returns `false`. `staticcall` additionally guarantees the trusted
contract cannot change state through this call.

**Verification:** `test_GarbageReturnFailsClosed`,
`test_RevertingAgentIdFailsClosed` (AgentGate suite),
`test_MaliciousAgentIdFailsClosed` (attack sim). Full suite 120/120.

## SEC-002 — Least-privilege constructors (Medium, fixed in `aadf24f`)

**Files:** `packages/contracts/src/QuestManager.sol` (constructor, lines
45–57) and `packages/contracts/src/Achievement.sol` (constructor, lines
36–41).

**Before** (QuestManager):

```solidity
constructor(address gate_, address reputation_, address achievement_, address admin_) {
    // ... zero-address checks, immutable assignments ...
    _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    _grantRole(PAUSER_ROLE, admin_);
}
```

**Before** (Achievement):

```solidity
constructor(address admin_) ERC721("AGENTHUB Achievement", "AGH-ACH") {
    if (admin_ == address(0)) revert ZeroAddress();
    _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    _grantRole(BADGE_MANAGER_ROLE, admin_);
}
```

Why it was wrong: renouncing `DEFAULT_ADMIN_ROLE` (the production handover
to the TimelockController) does not renounce the operational roles, so the
deployer EOA silently kept pause/badge-definition power forever.

**After** (QuestManager — Achievement is analogous):

```solidity
constructor(address gate_, address reputation_, address achievement_, address admin_) {
    // ... zero-address checks, immutable assignments ...
    // Least privilege: the constructor grants ONLY DEFAULT_ADMIN_ROLE.
    // Operational roles (QUEST_CREATOR_ROLE, PAUSER_ROLE) MUST be
    // granted explicitly during setup. Granting them here would let
    // the deployer keep pausing/creating quests after renouncing admin
    // (SEC-002) — a retained-privilege footgun.
    _grantRole(DEFAULT_ADMIN_ROLE, admin_);
}
```

Setup now grants operational roles explicitly (multisig gets `PAUSER_ROLE`,
badge manager gets `BADGE_MANAGER_ROLE`), and the deployer renounces any
setup-only role it held — modelled in `test/Integration.t.sol` setUp.

**Verification:** `test_PauseUnpauseRoleMatrix` (admin cannot pause
without the role), `test_DeployerLostAdminAfterRenounce` (deployer holds
zero operational roles after renounce). Full suite 120/120.

## SEC-003 — Badge token id in the completion event (Low, fixed in `ee7592e`)

**Files:** `packages/contracts/src/QuestManager.sol` (`completeQuest`,
lines 135–138) and `packages/contracts/src/interfaces/IQuestManager.sol`
(`QuestCompleted` event, lines 46–49).

**Before:**

```solidity
// QuestManager.completeQuest
reputation.addPoints(msg.sender, quest.rewardPoints, questId);
if (quest.badgeId != 0 && !achievement.hasBadge(msg.sender, quest.badgeId)) {
    achievement.issue(msg.sender, quest.badgeId); // return value discarded
}
emit QuestCompleted(questId, msg.sender, quest.rewardPoints);
```

```solidity
// IQuestManager
event QuestCompleted(uint256 indexed questId, address indexed account, uint256 rewardPoints);
```

**After:**

```solidity
// QuestManager.completeQuest
reputation.addPoints(msg.sender, quest.rewardPoints, questId);
// Capture the minted badge token id and expose it in the event
// (Slither unused-return SEC-003): indexers can link the completion
// to the badge token without a second lookup. 0 = no badge issued.
uint256 badgeTokenId = quest.badgeId != 0 && !achievement.hasBadge(msg.sender, quest.badgeId)
    ? achievement.issue(msg.sender, quest.badgeId)
    : 0;
emit QuestCompleted(questId, msg.sender, quest.rewardPoints, badgeTokenId);
```

```solidity
// IQuestManager
/// @notice badgeTokenId is the minted Achievement token id, or 0 when the
/// quest carries no badge or the completer already held it.
event QuestCompleted(
    uint256 indexed questId, address indexed account, uint256 rewardPoints, uint256 badgeTokenId
);
```

**Verification:** `test_QuestCompletedEventCarriesBadgeTokenId`,
`test_QuestCompletedEventHasZeroTokenIdWithoutBadge`. Slither re-run:
`unused-return` gone (one `uninitialized-local` report on the new
variable is a Slither false positive — see SEC-005).

## Remediation summary

| Finding | Severity | Remediation                                               | Commit    | Regression test                               |
| ------- | -------- | --------------------------------------------------------- | --------- | --------------------------------------------- |
| SEC-001 | High     | Low-level staticcall + length check + `mload`             | `a597a2d` | `test_GarbageReturnFailsClosed`               |
| SEC-002 | Medium   | Constructors grant admin role only; explicit setup grants | `aadf24f` | `test_DeployerLostAdminAfterRenounce`         |
| SEC-003 | Low      | Capture `issue()` return, emit in `QuestCompleted`        | `ee7592e` | `test_QuestCompletedEventCarriesBadgeTokenId` |
