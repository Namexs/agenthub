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
/// - Attested: completion requires EIP-712 attestations signed by
///   authorized verifiers (VERIFIER_ROLE), bound to account + questId +
///   nonce + deadline. PHASE 6 (R-010): each quest declares an
///   attestationThreshold (1–3) — the minimum number of DISTINCT
///   verifier signatures required. This is the ONLY kind that may
///   represent off-chain activity (e.g. "post on X").
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
        /// @dev PHASE 6 (R-010): minimum number of DISTINCT VERIFIER_ROLE
        /// signatures an attestation must carry for this quest (1–3).
        /// Set at creation, immutable afterwards. Only Attested quests
        /// use it; other kinds store it but never enforce it.
        uint8 attestationThreshold;
    }

    /// @notice A validator registry entry. Approval is per INSTANCE, not
    /// per implementation: the admin reviews each instance's parameters
    /// (e.g. token + threshold for TokenBalanceValidator) before
    /// approving it. Metadata is required — a validator without
    /// identity, version, and documentation cannot be approved.
    /// @dev Revocation sets `approved` to false and KEEPS the metadata
    /// (audit trail); re-approval overwrites metadata + `approvedAt`
    /// (fresh review).
    struct ValidatorInfo {
        string name;
        string version;
        string documentation;
        uint256 approvedAt;
        bool approved;
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
    /// @dev PHASE 6 (R-010): the same verifier signed twice in one
    /// attestation array — duplicates are rejected, never counted once.
    error DuplicateAttestationSigner(address signer);
    /// @dev PHASE 6 (R-010): fewer distinct valid verifier signatures
    /// than the quest's attestation threshold.
    error InsufficientAttestations(uint256 provided, uint256 required);
    /// @dev PHASE 6 (R-010): more signatures than MAX_ATTESTATION_SIGNATURES.
    error TooManyAttestationSignatures(uint256 provided);
    /// @dev PHASE 6 (R-010): attestationThreshold outside 1–3 at creation.
    error AttestationThresholdOutOfRange(uint256 threshold);
    // PHASE 8 (PH7-H01 / PH7-M02): a high-value Attested quest
    // (rewardPoints > HIGH_VALUE_REWARD_POINTS, or a high-value badge)
    // created with attestationThreshold < 2 reverts with
    // InsufficientAttestations(threshold, 2) — the policy floor is 2
    // distinct verifiers, so `provided` is the requested threshold and
    // `required` is 2. No separate error: one error surface for "not
    // enough verifiers", whether at creation or at completion.
    /// @dev PHASE 8 (PH7-M01): revoking a verifier would leave fewer
    /// verifiers than the highest threshold among live Attested quests,
    /// bricking those quests. `remainingVerifiers` is the count after
    /// the revoke; `highestLiveThreshold` is the bar it must clear.
    /// Recovery: deactivate the affected quests first, then revoke.
    error RevocationWouldBrickQuest(uint256 remainingVerifiers, uint256 highestLiveThreshold);
    /// @dev PHASE 8 (PH7-M01): an Attested quest was created with a
    /// threshold above the number of live VERIFIER_ROLE holders — it
    /// would be bricked from birth. Grant verifiers first.
    error InsufficientVerifiers(uint256 available, uint256 required);
    /// @dev PHASE 8 (PH7-L07): `account` already completed the quest
    /// this quest supersedes (`supersededQuestId`) — the recreate
    /// cannot pay the same account twice for the same quest.
    error AlreadyCompletedSupersededQuest(address account, uint256 questId, uint256 supersededQuestId);
    /// @dev The on-chain validator rejected the completion.
    error OnChainValidationFailed(uint256 questId, address account);
    /// @dev Validator address mismatches the quest's validation kind:
    /// non-zero for CheckIn/Attested, or zero / code-less for OnChain.
    error InvalidValidator(address validator);
    /// @dev PRE-TESTNET CLEANUP (item 6): an OnChain quest may only use a
    /// validator the admin has approved. A validator that was never
    /// approved — or was approved and later revoked — is rejected both at
    /// quest creation and at completion time, so revocation takes effect
    /// immediately, including for quests already created.
    error ValidatorNotApproved(address validator);
    /// @dev FINAL REMEDIATION (Phase 5): approveValidator metadata is
    /// incomplete — name, version, and documentation are all required.
    error InvalidValidatorMetadata();
    /// @dev FINAL REMEDIATION (Phase 5): the validator's validate() call
    /// reverted (staticcall returned success = false). The completion
    /// fails closed with this error instead of propagating the
    /// validator's arbitrary revert data.
    error ValidatorCallFailed(address validator);
    /// @dev FINAL REMEDIATION (Phase 5): the validator returned malformed
    /// data (not exactly 32 bytes, or a bool word other than 0/1).
    error InvalidValidatorReturndata(address validator);

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
    /// @dev FINAL REMEDIATION (Phase 6): `signer` is indexed for
    /// monitoring attribution — every attested completion is traceable
    /// to the verifier who signed it (see VERIFIER_SECURITY_SOP.md §5).
    event AttestationUsed(address indexed account, uint256 indexed questId, uint256 nonce, address indexed signer);
    /// @notice Emitted when the admin approves a validator for OnChain quests.
    event ValidatorApproved(address indexed validator);
    /// @notice Emitted when the admin revokes a validator's approval.
    /// Revocation blocks new quests AND completions using that validator.
    event ValidatorRevoked(address indexed validator);
    /// @notice PHASE 8 (PH7-L07): `newQuestId` supersedes `oldQuestId`
    /// (a deactivate + recreate). Accounts that completed the old quest
    /// cannot complete the new one — the link is the anti-double-claim
    /// record for indexers and the frontend.
    event QuestSuperseded(uint256 indexed newQuestId, uint256 indexed oldQuestId);

    /// @notice Create a quest. Only QUEST_CREATOR_ROLE. Returns the new quest id.
    /// @dev Rules (review R3/R4/R5): title 1–128 bytes, description ≤ 1024 bytes,
    /// 0 < rewardPoints ≤ MAX_REWARD_POINTS, startTime < endTime, endTime in the
    /// future, maxCompletions == 0 means unlimited, and a non-zero badgeId must
    /// already be defined on the Achievement contract.
    /// @dev Validation rules (TEMUAN 1): OnChain quests REQUIRE a validator
    /// contract (code must exist); CheckIn and Attested quests REQUIRE
    /// validator == address(0).
    /// @dev PHASE 6 (R-010): attestationThreshold (1–3, uniform for all quest
    /// kinds) is the minimum number of DISTINCT VERIFIER_ROLE signatures an
    /// attestation must carry. Immutable after creation — there is no setter.
    /// @dev PHASE 8 (PH7-H01 / PH7-M02): the threshold policy is enforced
    /// ON-CHAIN for Attested quests only — a quest with
    /// rewardPoints > HIGH_VALUE_REWARD_POINTS (1,000) or a high-value
    /// badge REQUIRES attestationThreshold ≥ 2, else
    /// InsufficientAttestations(threshold, 2). Non-Attested quests are
    /// exempt: their threshold is stored but never enforced at
    /// completion (PH7-L08 / PH7-I07), so the policy has no meaning for
    /// them — a CheckIn quest may legitimately carry 10,000 points.
    /// @dev PHASE 8 (PH7-M01): an Attested quest also requires at least
    /// `attestationThreshold` live VERIFIER_ROLE holders at creation
    /// (InsufficientVerifiers), so a quest can never be born bricked.
    /// Non-Attested quests are not checked.
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
        uint256 maxCompletions,
        uint8 attestationThreshold
    ) external returns (uint256 questId);

    /// @notice Complete a CheckIn or OnChain quest. Caller must hold an Agent ID.
    /// Enforces one-time rules and cooldowns (daily/weekly). Awards points + badge.
    /// @dev Community quests behave like OneTime: one completion per account.
    /// @dev Reverts with AttestationRequired on Attested quests.
    function completeQuest(uint256 questId) external;

    /// @notice Complete an Attested quest with EIP-712 attestations from
    /// authorized verifiers. Every attestation binds account + questId +
    /// the caller's current nonce + deadline; the nonce is consumed once
    /// on success, regardless of how many signatures are provided.
    /// @dev PHASE 6 (R-010): threshold attestation (M-of-N). All signers
    /// sign the SAME digest. The array must carry at least the quest's
    /// attestationThreshold DISTINCT VERIFIER_ROLE signers; every
    /// signature in the array must recover to a distinct VERIFIER_ROLE
    /// holder (a junk signature anywhere reverts the call), and the
    /// array is capped at MAX_ATTESTATION_SIGNATURES.
    /// @dev The signature is over the EIP-712 typed data
    /// Attestation(address account, uint256 questId, uint256 nonce, uint256 deadline)
    /// in the domain ("AGENTHUB QuestManager", "1", chainId, this contract).
    function completeQuestWithAttestation(uint256 questId, uint256 deadline, bytes[] calldata signatures) external;

    /// @notice The next attestation nonce for `account`. Verifiers sign the
    /// current nonce; it increments on every attested completion.
    function nonces(address account) external view returns (uint256 nonce);

    /// @notice Whether `validator` is approved for OnChain quests.
    /// @dev TokenBalanceValidator is deployed once per (token, threshold)
    /// pair, so approval is per INSTANCE, not per implementation: the admin
    /// reviews each instance's token + threshold before approving it.
    /// Backed by the validator registry (`validatorInfo`).
    function approvedValidators(address validator) external view returns (bool approved);

    /// @notice The registry entry for `validator` (name, version,
    /// documentation, approval time, approval status). Readable by anyone.
    function validatorInfo(address validator) external view returns (ValidatorInfo memory info);

    /// @notice Approve a validator for OnChain quests. Admin only.
    /// @dev The admin must review the validator contract (and, for
    /// TokenBalanceValidator, its token + threshold) before approving:
    /// approval is the trust decision that replaces the old "creator picks
    /// any contract" model. Reverts on zero / code-less addresses and on
    /// empty metadata. Re-approval overwrites metadata + approvedAt.
    function approveValidator(
        address validator,
        string calldata name,
        string calldata version,
        string calldata documentation
    ) external;

    /// @notice Revoke a validator's approval. Admin only (timelock).
    /// Takes effect immediately: new quests cannot use it, and completions
    /// of existing quests using it revert until (and unless) it is
    /// re-approved. Metadata is kept as an audit trail.
    function revokeValidator(address validator) external;

    /// @notice Emergency-revoke a validator's approval. PAUSER_ROLE only
    /// (no timelock delay) — the fast path for a compromised or malicious
    /// validator. Same effect as revokeValidator; re-approval still
    /// requires the admin (timelock).
    function emergencyRevokeValidator(address validator) external;

    /// @notice Deactivate a quest (creator or admin). No new completions after this.
    /// @dev PHASE 8 (PH7-M01): deactivating an Attested quest lowers the
    /// live-threshold counters, which is the recovery path when a
    /// verifier revocation would otherwise be blocked by the guardrail.
    function deactivateQuest(uint256 questId) external;

    /// @notice PHASE 8 (PH7-L07): record that `newQuestId` supersedes
    /// `oldQuestId` (a deactivate + recreate of the same quest). Admin
    /// only. Both quests must exist and differ; the old quest SHOULD
    /// already be deactivated (the recreate flow), but the contract
    /// does not enforce it — linking a live quest is harmless, since
    /// the guard only blocks accounts that completed the old quest.
    /// The link is single-hop and permanent (no clear function):
    /// completions of the new quest check ONLY the linked old quest,
    /// so for a chain of recreates, link the new quest to the quest
    /// that actually has completions. Re-linking overwrites the
    /// previous link (admin correction path). Accounts that completed
    /// the new quest BEFORE the link was set keep their completion —
    /// set the link promptly after recreating.
    function setSupersedes(uint256 newQuestId, uint256 oldQuestId) external;

    /// @notice PHASE 8 (PH7-L07): the quest `questId` supersedes, or 0
    /// if it supersedes none.
    function supersedes(uint256 questId) external view returns (uint256 oldQuestId);

    /// @notice PHASE 8 (PH7-M01): number of live VERIFIER_ROLE holders.
    /// Maintained by the _grantRole/_revokeRole overrides (AccessControl
    /// cannot enumerate role holders, so the contract counts them).
    function verifierCount() external view returns (uint256 count);

    /// @notice PHASE 8 (PH7-M01): highest attestationThreshold among
    /// live (active) Attested quests, or 0 when none are live. A
    /// revocation is blocked while it would leave fewer verifiers
    /// than this number. Expired-but-still-active quests still count
    /// (conservative: an expired quest can never complete, but its
    /// threshold still guards the verifier set until deactivated).
    function highestLiveThreshold() external view returns (uint8 threshold);

    /// @notice PHASE 8 (PH7-M01): number of live (active) Attested
    /// quests at exactly `threshold` (1–3; any other value returns 0).
    /// Observability for the SOP pre-revoke check.
    function liveAttestedQuestCount(uint8 threshold) external view returns (uint256 count);

    function getQuest(uint256 questId) external view returns (Quest memory quest);
    function hasCompleted(address account, uint256 questId) external view returns (bool);
    /// @return readyAt Unix timestamp when `account` may next complete `questId` (0 = now).
    function nextCompletionAt(address account, uint256 questId) external view returns (uint256 readyAt);
    function questCount() external view returns (uint256);
}
