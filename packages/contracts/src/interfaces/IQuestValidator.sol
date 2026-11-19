// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IQuestValidator
/// @notice Validates an on-chain quest completion for one account.
/// @dev Called by QuestManager.completeQuest for OnChain quests, AFTER the
/// cheap checks (gate, window, cap, duplicate, cooldown) and BEFORE any
/// state change. A validator MUST be a view function: it may read state
/// but must not change it. Returning false reverts the completion; a
/// reverting validator reverts the completion too (fail-closed).
/// @dev TRUST: the quest creator chooses the validator at creation time.
/// A validator that always returns true is equivalent to a CheckIn quest,
/// so QUEST_CREATOR_ROLE is trusted to pick honest validators, and
/// governance should review validator contracts before creators use them
/// (see QUEST_VALIDATION_DESIGN.md). The code-existence check at creation
/// proves an address IS a contract — it does NOT prove it is trustworthy.
interface IQuestValidator {
    /// @return valid True when `account` has satisfied the quest's on-chain
    /// condition for `questId`.
    function validate(address account, uint256 questId) external view returns (bool valid);
}
