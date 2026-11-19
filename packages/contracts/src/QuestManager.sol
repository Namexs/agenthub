// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAgentGate} from "./interfaces/IAgentGate.sol";
import {IQuestManager} from "./interfaces/IQuestManager.sol";
import {IReputation} from "./interfaces/IReputation.sol";
import {IAchievement} from "./interfaces/IAchievement.sol";

/// @title QuestManager
/// @notice Creates quests and records validated completions. Only Agent ID
/// holders (verified via AgentGate) may complete quests. Completions award
/// reputation points and (optionally) soulbound badges through the trusted
/// Reputation and Achievement contracts — QuestManager never mints reputation
/// or badges itself.
/// @dev Security properties: role-gated creation, checks-effects-interactions,
/// nonReentrant completions, per-account cooldowns, duplicate prevention,
/// capped rewards, bounded strings, pausable. See SECURITY_THREAT_MODEL.md.
contract QuestManager is IQuestManager, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant QUEST_CREATOR_ROLE = keccak256("QUEST_CREATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Maximum reputation points a single quest may award.
    uint256 public constant MAX_REWARD_POINTS = 10_000;
    /// @notice Maximum quest title length (DoS protection against giant strings).
    uint256 public constant MAX_TITLE_BYTES = 128;
    /// @notice Maximum quest description length.
    uint256 public constant MAX_DESCRIPTION_BYTES = 1024;
    uint256 public constant DAILY_COOLDOWN = 1 days;
    uint256 public constant WEEKLY_COOLDOWN = 7 days;

    IAgentGate public immutable gate;
    IReputation public immutable reputation;
    IAchievement public immutable achievement;

    uint256 private _questCount;
    mapping(uint256 => Quest) private _quests;
    /// @dev Ever completed (all quest types).
    mapping(address => mapping(uint256 => bool)) private _completed;
    mapping(address => mapping(uint256 => uint256)) private _lastCompletedAt;
    mapping(address => mapping(uint256 => uint256)) private _completionCount;

    constructor(address gate_, address reputation_, address achievement_, address admin_) {
        if (gate_ == address(0) || reputation_ == address(0) || achievement_ == address(0) || admin_ == address(0)) {
            revert ZeroAddress();
        }
        gate = IAgentGate(gate_);
        reputation = IReputation(reputation_);
        achievement = IAchievement(achievement_);
        // Least privilege: the constructor grants ONLY DEFAULT_ADMIN_ROLE.
        // Operational roles (QUEST_CREATOR_ROLE, PAUSER_ROLE) MUST be
        // granted explicitly during setup. Granting them here would let
        // the deployer keep pausing/creating quests after renouncing admin
        // (SEC-002) — a retained-privilege footgun.
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @inheritdoc IQuestManager
    function createQuest(
        string calldata title,
        string calldata description,
        QuestType questType,
        uint256 rewardPoints,
        uint256 badgeId,
        uint256 startTime,
        uint256 endTime,
        uint256 maxCompletions
    ) external onlyRole(QUEST_CREATOR_ROLE) returns (uint256 questId) {
        if (bytes(title).length == 0 || bytes(title).length > MAX_TITLE_BYTES) {
            revert InvalidQuestParams();
        }
        if (bytes(description).length > MAX_DESCRIPTION_BYTES) revert InvalidQuestParams();
        if (rewardPoints == 0 || rewardPoints > MAX_REWARD_POINTS) revert InvalidQuestParams();
        if (startTime >= endTime || endTime <= block.timestamp) revert InvalidQuestParams();
        if (badgeId != 0 && !achievement.isBadgeDefined(badgeId)) {
            revert IAchievement.BadgeNotDefined(badgeId);
        }
        questId = ++_questCount;
        _quests[questId] = Quest({
            id: questId,
            creator: msg.sender,
            title: title,
            description: description,
            questType: questType,
            rewardPoints: rewardPoints,
            badgeId: badgeId,
            startTime: startTime,
            endTime: endTime,
            maxCompletions: maxCompletions, // 0 = unlimited
            completions: 0,
            active: true
        });
        emit QuestCreated(questId, msg.sender, questType, rewardPoints);
    }

    /// @inheritdoc IQuestManager
    /// @dev Order: checks (gate, active, window, cap, duplicate, cooldown) →
    /// effects (all state) → interactions (Reputation, Achievement) →
    /// event. Guarded by nonReentrant + whenNotPaused.
    function completeQuest(uint256 questId) external nonReentrant whenNotPaused {
        Quest storage quest = _quests[questId];
        if (quest.id == 0) revert QuestNotFound(questId);
        gate.requireAgentHolder(msg.sender);
        if (!quest.active) revert QuestNotActive(questId);
        if (block.timestamp < quest.startTime) revert QuestNotStarted(questId);
        if (block.timestamp > quest.endTime) revert QuestEnded(questId);
        if (quest.maxCompletions != 0 && quest.completions >= quest.maxCompletions) {
            revert QuestFull(questId);
        }
        if (quest.questType == QuestType.OneTime || quest.questType == QuestType.Community) {
            if (_completed[msg.sender][questId]) revert AlreadyCompleted(msg.sender, questId);
        } else {
            uint256 cooldown = quest.questType == QuestType.DailyCheckIn ? DAILY_COOLDOWN : WEEKLY_COOLDOWN;
            if (_completionCount[msg.sender][questId] > 0) {
                uint256 readyAt = _lastCompletedAt[msg.sender][questId] + cooldown;
                if (block.timestamp < readyAt) {
                    revert CooldownActive(msg.sender, questId, readyAt);
                }
            }
        }

        // Effects.
        quest.completions += 1;
        _completed[msg.sender][questId] = true;
        _lastCompletedAt[msg.sender][questId] = block.timestamp;
        _completionCount[msg.sender][questId] += 1;

        // Interactions (trusted contracts only).
        reputation.addPoints(msg.sender, quest.rewardPoints, questId);
        // Capture the minted badge token id and expose it in the event
        // (Slither unused-return SEC-003): indexers can link the completion
        // to the badge token without a second lookup. 0 = no badge issued.
        uint256 badgeTokenId = quest.badgeId != 0 && !achievement.hasBadge(msg.sender, quest.badgeId)
            ? achievement.issue(msg.sender, quest.badgeId)
            : 0;
        emit QuestCompleted(questId, msg.sender, quest.rewardPoints, badgeTokenId);
    }

    /// @inheritdoc IQuestManager
    function deactivateQuest(uint256 questId) external {
        Quest storage quest = _quests[questId];
        if (quest.id == 0) revert QuestNotFound(questId);
        if (msg.sender != quest.creator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotQuestCreatorOrAdmin(msg.sender, questId);
        }
        quest.active = false;
        emit QuestDeactivated(questId);
    }

    /// @notice Emergency pause. PAUSER_ROLE can pause; only DEFAULT_ADMIN_ROLE
    /// may unpause (controlled recovery).
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @inheritdoc IQuestManager
    function getQuest(uint256 questId) external view returns (Quest memory quest) {
        if (_quests[questId].id == 0) revert QuestNotFound(questId);
        return _quests[questId];
    }

    /// @inheritdoc IQuestManager
    function hasCompleted(address account, uint256 questId) external view returns (bool) {
        return _completed[account][questId];
    }

    /// @inheritdoc IQuestManager
    function nextCompletionAt(address account, uint256 questId) external view returns (uint256 readyAt) {
        Quest storage quest = _quests[questId];
        if (quest.id == 0) revert QuestNotFound(questId);
        if (quest.questType == QuestType.OneTime || quest.questType == QuestType.Community) {
            return _completed[account][questId] ? type(uint256).max : 0;
        }
        uint256 cooldown = quest.questType == QuestType.DailyCheckIn ? DAILY_COOLDOWN : WEEKLY_COOLDOWN;
        if (_completionCount[account][questId] == 0) return 0;
        uint256 ready = _lastCompletedAt[account][questId] + cooldown;
        return block.timestamp >= ready ? 0 : ready;
    }

    /// @inheritdoc IQuestManager
    function questCount() external view returns (uint256) {
        return _questCount;
    }
}
