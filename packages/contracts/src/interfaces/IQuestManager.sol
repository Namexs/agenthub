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
    error ZeroAddress();
    error NotQuestCreatorOrAdmin(address account, uint256 questId);

    event QuestCreated(uint256 indexed questId, address indexed creator, QuestType questType, uint256 rewardPoints);
    /// @notice badgeTokenId is the minted Achievement token id, or 0 when the
    /// quest carries no badge or the completer already held it.
    event QuestCompleted(uint256 indexed questId, address indexed account, uint256 rewardPoints, uint256 badgeTokenId);
    event QuestDeactivated(uint256 indexed questId);

    /// @notice Create a quest. Only QUEST_CREATOR_ROLE. Returns the new quest id.
    /// @dev Rules (review R3/R4/R5): title 1–128 bytes, description ≤ 1024 bytes,
    /// 0 < rewardPoints ≤ MAX_REWARD_POINTS, startTime < endTime, endTime in the
    /// future, maxCompletions == 0 means unlimited, and a non-zero badgeId must
    /// already be defined on the Achievement contract.
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
    /// @dev Community quests behave like OneTime: one completion per account.
    function completeQuest(uint256 questId) external;

    /// @notice Deactivate a quest (creator or admin). No new completions after this.
    function deactivateQuest(uint256 questId) external;

    function getQuest(uint256 questId) external view returns (Quest memory quest);
    function hasCompleted(address account, uint256 questId) external view returns (bool);
    /// @return readyAt Unix timestamp when `account` may next complete `questId` (0 = now).
    function nextCompletionAt(address account, uint256 questId) external view returns (uint256 readyAt);
    function questCount() external view returns (uint256);
}
