// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IQuestManager — Step 2 of the AGENTHUB contract build order.
/// @notice Creates quests and records validated completions. Only Agent ID
/// holders (verified via AgentGate) may complete quests. Completions are
/// recorded on-chain so every feature is provable by transaction, not by UI.
/// @dev Reputation points and badges are awarded through IReputation /
/// IAchievement — QuestManager never mints reputation itself.
/// @dev REMEDIATION (TEMUAN 1): a completion is only as credible as its
/// proof. Every quest declares a ValidationKind at creation, and the kind
/// decides which completion path is valid:
/// - CheckIn: self-service; proves ONLY that the holder called the function.
///   Honest label for streaks/attendance — NEVER proof of external activity.
/// - OnChain: completion calls the quest's validator contract, which checks
///   an on-chain condition (e.g. a token balance) for the completer.
/// - Attested: completion requires an EIP-712 attestation signed by an
///   authorized verifier (VERIFIER_ROLE), bound to account + questId +
///   nonce + deadline. This is the ONLY kind that may represent off-chain
///   activity (e.g. "post on X").
interface IQuestManager {
    enum QuestType {
        DailyCheckIn,
        OneTime,
        Weekly,
        Community
    }

    enum ValidationKind {
        CheckIn,
        OnChain,
        Attested
    }

    struct Quest {
        uint256 id;
        address creator;
        string title;
        string description;
        QuestType questType;
        ValidationKind validationKind;
        /// @dev OnChain quests only: contract that validates completion.
        /// Must be address(0) for CheckIn and Attested quests.
        address validator;
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
    /// @dev TEMUAN 3: a QuestManager dependency has no code (not a contract).
    error NoCodeAtDependency(address dependency);
    /// @dev completeQuest called on an Attested quest — a bare call is not
    /// proof of external activity; use completeQuestWithAttestation.
    error AttestationRequired(uint256 questId);
    /// @dev completeQuestWithAttestation called on a non-Attested quest.
    error QuestNotAttested(uint256 questId);
    /// @dev The attestation deadline has passed.
    error AttestationExpired(uint256 deadline, uint256 currentTime);
    /// @dev The attestation deadline exceeds MAX_ATTESTATION_LIFETIME.
    error AttestationDeadlineTooFar(uint256 deadline, uint256 maxDeadline);
    /// @dev The attestation signature is malformed or unrecoverable.
    /// @notice Attestation signature is invalid (malleable, malformed, or
    /// unrecoverable). `errorArg` is OZ's error argument: the offending `s`
    /// for an invalid-S signature, the length for a bad-length signature,
    /// bytes32(0) otherwise.
    error InvalidAttestationSignature(bytes32 errorArg);
    /// @dev The attestation was not signed by a VERIFIER_ROLE holder.
    error UnauthorizedVerifier(address signer);
    /// @dev The on-chain validator rejected the completion.
    error OnChainValidationFailed(uint256 questId, address account);
    /// @dev Validator address mismatches the quest's validation kind:
    /// non-zero for CheckIn/Attested, or zero / code-less for OnChain.
    error InvalidValidator(address validator);

    event QuestCreated(
        uint256 indexed questId,
        address indexed creator,
        QuestType questType,
        ValidationKind validationKind,
        uint256 rewardPoints
    );
    /// @notice badgeTokenId is the minted Achievement token id, or 0 when the
    /// quest carries no badge or the completer already held it.
    event QuestCompleted(uint256 indexed questId, address indexed account, uint256 rewardPoints, uint256 badgeTokenId);
    event QuestDeactivated(uint256 indexed questId);
    /// @notice Emitted when an attested completion consumes a nonce.
    event AttestationUsed(address indexed account, uint256 indexed questId, uint256 nonce);

    /// @notice Create a quest. Only QUEST_CREATOR_ROLE. Returns the new quest id.
    /// @dev Rules (review R3/R4/R5): title 1–128 bytes, description ≤ 1024 bytes,
    /// 0 < rewardPoints ≤ MAX_REWARD_POINTS, startTime < endTime, endTime in the
    /// future, maxCompletions == 0 means unlimited, and a non-zero badgeId must
    /// already be defined on the Achievement contract.
    /// @dev Validation rules (TEMUAN 1): OnChain quests REQUIRE a validator
    /// contract (code must exist); CheckIn and Attested quests REQUIRE
    /// validator == address(0).
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
    ) external returns (uint256 questId);

    /// @notice Complete a CheckIn or OnChain quest. Caller must hold an Agent ID.
    /// Enforces one-time rules and cooldowns (daily/weekly). Awards points + badge.
    /// @dev Community quests behave like OneTime: one completion per account.
    /// @dev Reverts with AttestationRequired on Attested quests.
    function completeQuest(uint256 questId) external;

    /// @notice Complete an Attested quest with an EIP-712 attestation from an
    /// authorized verifier. The attestation binds account + questId + the
    /// caller's current nonce + deadline; the nonce is consumed on success.
    /// @dev The signature is over the EIP-712 typed data
    /// Attestation(address account, uint256 questId, uint256 nonce, uint256 deadline)
    /// in the domain ("AGENTHUB QuestManager", "1", chainId, this contract).
    function completeQuestWithAttestation(uint256 questId, uint256 deadline, bytes calldata signature) external;

    /// @notice The next attestation nonce for `account`. Verifiers sign the
    /// current nonce; it increments on every attested completion.
    function nonces(address account) external view returns (uint256 nonce);

    /// @notice Deactivate a quest (creator or admin). No new completions after this.
    function deactivateQuest(uint256 questId) external;

    function getQuest(uint256 questId) external view returns (Quest memory quest);
    function hasCompleted(address account, uint256 questId) external view returns (bool);
    /// @return readyAt Unix timestamp when `account` may next complete `questId` (0 = now).
    function nextCompletionAt(address account, uint256 questId) external view returns (uint256 readyAt);
    function questCount() external view returns (uint256);
}
