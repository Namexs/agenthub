// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IQuestManager — Step 2 of the AGENTHUB contract build order.
/// @notice Creates quests and records validated completions. Only Agent ID
/// holders (verified via AgentGate) may complete quests. Completions are
/// recorded on-chain so every feature is provable by transaction, not by UI.
/// @dev Reputation points and badges are awarded through IReputation /
/// IAchievement — QuestManager never mints reputation itself.
interface IQuestManager {
    enum QuestType {
        DailyCheckIn,
        OneTime,
        Weekly,
        Community
    }

    struct Quest {
        uint256 id;
        address creator;
        string title;
        string description;
        QuestType questType;
        uint256 rewardPoints;
        /// @dev 0 = no badge awarded on completion.
        uint256 badgeId;
        uint256 startTime;
        uint256 endTime;
        uint256 maxCompletions;
        uint256 completions;
        bool active;
    }

    error QuestNotFound(uint256 questId);
    error QuestNotActive(uint256 questId);
    error QuestNotStarted(uint256 questId);
    error QuestEnded(uint256 questId);
    error QuestFull(uint256 questId);
    error AlreadyCompleted(address account, uint256 questId);
    error CooldownActive(address account, uint256 questId, uint256 readyAt);
    error InvalidQuestParams();

    event QuestCreated(uint256 indexed questId, address indexed creator, QuestType questType, uint256 rewardPoints);
    event QuestCompleted(uint256 indexed questId, address indexed account, uint256 rewardPoints);
    event QuestDeactivated(uint256 indexed questId);

    /// @notice Create a quest. Only QUEST_CREATOR_ROLE. Returns the new quest id.
    function createQuest(
        string calldata title,
        string calldata description,
        QuestType questType,
        uint256 rewardPoints,
        uint256 badgeId,
        uint256 startTime,
        uint256 endTime,
        uint256 maxCompletions
    ) external returns (uint256 questId);

    /// @notice Complete a quest. Caller must hold an Agent ID. Enforces
    /// one-time rules and cooldowns (daily/weekly). Awards points + badge.
    function completeQuest(uint256 questId) external;

    /// @notice Deactivate a quest (creator or admin). No new completions after this.
    function deactivateQuest(uint256 questId) external;

    function getQuest(uint256 questId) external view returns (Quest memory quest);
    function hasCompleted(address account, uint256 questId) external view returns (bool);
    /// @return readyAt Unix timestamp when `account` may next complete `questId` (0 = now).
    function nextCompletionAt(address account, uint256 questId) external view returns (uint256 readyAt);
    function questCount() external view returns (uint256);
}
