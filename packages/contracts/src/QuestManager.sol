// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IAgentGate} from "./interfaces/IAgentGate.sol";
import {IQuestManager} from "./interfaces/IQuestManager.sol";
import {IQuestValidator} from "./interfaces/IQuestValidator.sol";
import {IReputation} from "./interfaces/IReputation.sol";
import {IAchievement} from "./interfaces/IAchievement.sol";

/// @title QuestManager
/// @notice Creates quests and records validated completions. Only Agent ID
/// holders (verified via AgentGate) may complete quests. Completions award
/// reputation points and (optionally) soulbound badges through the trusted
/// Reputation and Achievement contracts — QuestManager never mints reputation
/// or badges itself.
/// @dev REMEDIATION (TEMUAN 1): a completion is only as credible as its
/// proof. Every quest declares a ValidationKind at creation:
/// - CheckIn: self-service; proves ONLY that the holder called the function.
///   Honest label for streaks/attendance — never proof of external activity.
/// - OnChain: completion calls the quest's validator contract, which checks
///   an on-chain condition for the completer.
/// - Attested: completion requires an EIP-712 attestation from a VERIFIER_ROLE
///   signer, bound to account + questId + nonce + deadline. The ONLY kind
///   that may represent off-chain activity.
/// @dev Security properties: role-gated creation, checks-effects-interactions,
/// nonReentrant completions, per-account cooldowns, duplicate prevention,
/// capped rewards, bounded strings, pausable, replay-protected attestations.
/// See QUEST_VALIDATION_DESIGN.md and SECURITY_THREAT_MODEL.md.
contract QuestManager is IQuestManager, AccessControl, Pausable, ReentrancyGuard, EIP712 {
    bytes32 public constant QUEST_CREATOR_ROLE = keccak256("QUEST_CREATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Attestation signers for off-chain quests. Grant/revoke via
    /// AccessControl (admin = timelock in production). Revoking the role
    /// invalidates that signer's outstanding attestations immediately.
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @notice EIP-712 typehash for off-chain quest attestations.
    bytes32 public constant ATTESTATION_TYPEHASH =
        keccak256("Attestation(address account,uint256 questId,uint256 nonce,uint256 deadline)");

    /// @notice Maximum reputation points a single quest may award.
    uint256 public constant MAX_REWARD_POINTS = 10_000;
    /// @notice Maximum quest title length (DoS protection against giant strings).
    uint256 public constant MAX_TITLE_BYTES = 128;
    /// @notice Maximum quest description length.
    uint256 public constant MAX_DESCRIPTION_BYTES = 1024;
    uint256 public constant DAILY_COOLDOWN = 1 days;
    uint256 public constant WEEKLY_COOLDOWN = 7 days;
    /// @notice An attestation may not be valid for more than 7 days from
    /// submission. Bounds the damage window of a compromised verifier key;
    /// revoking VERIFIER_ROLE invalidates outstanding attestations at once.
    uint256 public constant MAX_ATTESTATION_LIFETIME = 7 days;

    IAgentGate public immutable gate;
    IReputation public immutable reputation;
    IAchievement public immutable achievement;

    uint256 private _questCount;
    mapping(uint256 => Quest) private _quests;
    /// @dev Ever completed (all quest types).
    mapping(address => mapping(uint256 => bool)) private _completed;
    mapping(address => mapping(uint256 => uint256)) private _lastCompletedAt;
    mapping(address => mapping(uint256 => uint256)) private _completionCount;
    /// @notice Next attestation nonce per account (replay protection).
    /// Verifiers sign the current nonce; it increments on every attested
    /// completion. The nonce is global per account, not per quest: a
    /// verifier must read it before signing (see QUEST_VALIDATION_DESIGN.md).
    mapping(address => uint256) public nonces;

    constructor(address gate_, address reputation_, address achievement_, address admin_)
        EIP712("AGENTHUB QuestManager", "1")
    {
        if (gate_ == address(0) || reputation_ == address(0) || achievement_ == address(0) || admin_ == address(0)) {
            revert ZeroAddress();
        }
        // TEMUAN 3: dependencies must be contracts, not just non-zero.
        // NOTE: a code-length check proves an address IS a contract, not
        // that it is the RIGHT contract — that trust comes from the
        // deployment process (see DEPLOYMENT_PLAN.md).
        if (gate_.code.length == 0) revert NoCodeAtDependency(gate_);
        if (reputation_.code.length == 0) revert NoCodeAtDependency(reputation_);
        if (achievement_.code.length == 0) revert NoCodeAtDependency(achievement_);
        gate = IAgentGate(gate_);
        reputation = IReputation(reputation_);
        achievement = IAchievement(achievement_);
        // Least privilege: the constructor grants ONLY DEFAULT_ADMIN_ROLE.
        // Operational roles (QUEST_CREATOR_ROLE, PAUSER_ROLE, VERIFIER_ROLE)
        // MUST be granted explicitly during setup. Granting them here would
        // let the deployer keep pausing/creating quests after renouncing
        // admin (SEC-002) — a retained-privilege footgun.
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @inheritdoc IQuestManager
    function createQuest(
        string calldata title,
        string calldata description,
        QuestType questType,
        ValidationKind validationKind,
        address validator,
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
        // Validation-kind rules (TEMUAN 1): OnChain quests REQUIRE a
        // validator contract (code must exist); CheckIn and Attested
        // quests REQUIRE validator == address(0).
        if (validationKind == ValidationKind.OnChain) {
            if (validator == address(0) || validator.code.length == 0) revert InvalidValidator(validator);
        } else if (validator != address(0)) {
            revert InvalidValidator(validator);
        }
        questId = ++_questCount;
        _quests[questId] = Quest({
            id: questId,
            creator: msg.sender,
            title: title,
            description: description,
            questType: questType,
            validationKind: validationKind,
            validator: validator,
            rewardPoints: rewardPoints,
            badgeId: badgeId,
            startTime: startTime,
            endTime: endTime,
            maxCompletions: maxCompletions, // 0 = unlimited
            completions: 0,
            active: true
        });
        emit QuestCreated(questId, msg.sender, questType, validationKind, rewardPoints);
    }

    /// @inheritdoc IQuestManager
    /// @dev Order: kind gate → shared checks (gate, active, window, cap,
    /// duplicate, cooldown, validator) → effects → interactions → event.
    /// Guarded by nonReentrant + whenNotPaused.
    function completeQuest(uint256 questId) external nonReentrant whenNotPaused {
        Quest storage quest = _quests[questId];
        if (quest.id == 0) revert QuestNotFound(questId);
        // Attested quests MUST go through completeQuestWithAttestation: a
        // bare call is not proof of external activity (TEMUAN 1).
        if (quest.validationKind == ValidationKind.Attested) revert AttestationRequired(questId);
        _completeQuest(quest, questId);
    }

    /// @inheritdoc IQuestManager
    /// @dev Order: kind gate → attestation verification (deadline, EIP-712
    /// signature, verifier role, nonce consumption) → shared completion.
    /// The nonce is consumed inside _verifyAttestation; if the completion
    /// then reverts, the whole transaction reverts and the nonce is NOT
    /// consumed, so the same attestation can be retried.
    function completeQuestWithAttestation(uint256 questId, uint256 deadline, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
    {
        Quest storage quest = _quests[questId];
        if (quest.id == 0) revert QuestNotFound(questId);
        if (quest.validationKind != ValidationKind.Attested) revert QuestNotAttested(questId);
        _verifyAttestation(msg.sender, questId, deadline, signature);
        _completeQuest(quest, questId);
    }

    /// @notice Verify an EIP-712 attestation and consume the signer's nonce.
    /// @dev The domain separator binds chainId + this contract (cross-chain
    /// and cross-contract replay are impossible); the struct binds account +
    /// questId + nonce + deadline. ECDSA.tryRecover rejects malleable
    /// signatures (s > n/2) — see OpenZeppelin ECDSA.
    function _verifyAttestation(address account, uint256 questId, uint256 deadline, bytes calldata signature) internal {
        if (deadline < block.timestamp) revert AttestationExpired(deadline, block.timestamp);
        if (deadline > block.timestamp + MAX_ATTESTATION_LIFETIME) {
            revert AttestationDeadlineTooFar(deadline, block.timestamp + MAX_ATTESTATION_LIFETIME);
        }
        uint256 nonce = nonces[account];
        bytes32 structHash = keccak256(abi.encode(ATTESTATION_TYPEHASH, account, questId, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer == address(0)) {
            revert InvalidAttestationSignature();
        }
        if (!hasRole(VERIFIER_ROLE, signer)) revert UnauthorizedVerifier(signer);
        // Consume the nonce BEFORE the completion effects: a replayed
        // attestation signs a stale nonce and recovers a different signer.
        unchecked {
            nonces[account] = nonce + 1;
        }
        emit AttestationUsed(account, questId, nonce);
    }

    /// @notice Shared completion path for both entry points.
    /// @dev Order: checks (gate, active, window, cap, duplicate, cooldown,
    /// on-chain validator) → effects (all state) → interactions (Reputation,
    /// Achievement) → event.
    function _completeQuest(Quest storage quest, uint256 questId) internal {
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
        // On-chain validation runs in the CHECKS phase, before any state
        // change. A false result reverts; a reverting validator reverts too
        // (fail-closed). Reentrancy from the validator is blocked by
        // nonReentrant on the entry points.
        if (quest.validationKind == ValidationKind.OnChain) {
            if (!IQuestValidator(quest.validator).validate(msg.sender, questId)) {
                revert OnChainValidationFailed(questId, msg.sender);
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
