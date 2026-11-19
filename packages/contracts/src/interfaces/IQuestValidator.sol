// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IQuestValidator
/// @notice Validates an on-chain quest completion for one account.
/// @dev Called by QuestManager.completeQuest for OnChain quests, AFTER the
/// cheap checks (gate, window, cap, duplicate, cooldown) and BEFORE any
/// state change. A validator MUST be a view function: it may read state
/// but must not change it. Returning false reverts the completion; a
/// reverting validator reverts the completion too (fail-closed).
/// @dev TRUST (PRE-TESTNET CLEANUP, item 6): a quest creator can only
/// attach a validator the admin has approved (QuestManager.approvedValidators).
/// The admin reviews each validator instance before approving it, so an
/// always-true rubber-stamp validator cannot be smuggled into a quest by
/// a compromised creator. Approval is per instance, and revocation is
/// checked at completion time too, so it takes effect immediately.
interface IQuestValidator {
    /// @return valid True when `account` has satisfied the quest's on-chain
    /// condition for `questId`.
    function validate(address account, uint256 questId) external view returns (bool valid);
}
