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
/// - Attested: completion requires EIP-712 attestations from VERIFIER_ROLE
///   signers, bound to account + questId + nonce + deadline. PHASE 6
///   (R-010): each quest declares an attestationThreshold (1–3) — the
///   minimum number of DISTINCT verifier signatures required. The ONLY kind
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
    /// @notice PHASE 6 (R-010): maximum signatures in one attestation
    /// array. Bounds gas + calldata of a threshold completion.
    uint256 public constant MAX_ATTESTATION_SIGNATURES = 5;
    /// @notice PHASE 6 (R-010): attestationThreshold bounds (uniform for
    /// all quest kinds). 1 preserves single-verifier behavior; 3 is the
    /// highest threshold the SOP's verifier set is sized for.
    uint8 public constant MIN_ATTESTATION_THRESHOLD = 1;
    uint8 public constant MAX_ATTESTATION_THRESHOLD = 3;

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
    /// @notice The validator registry: per-instance approval + metadata
    /// (name, version, documentation, approval time).
    /// @dev FINAL REMEDIATION (Phase 5): upgrades the pre-testnet
    /// allowlist into a registry. Approval is per instance
    /// (TokenBalanceValidator is deployed once per (token, threshold)).
    /// Revocation is checked at creation AND at completion, so it takes
    /// effect immediately for existing quests too. Revocation keeps the
    /// metadata (audit trail); re-approval overwrites it (fresh review).
    /// Internal (not public): a public mapping getter returns a tuple,
    /// which cannot satisfy the interface's struct return type — the
    /// explicit validatorInfo() below returns the struct.
    mapping(address => IQuestManager.ValidatorInfo) internal _validatorInfo;

    /// @inheritdoc IQuestManager
    function validatorInfo(address validator) external view returns (IQuestManager.ValidatorInfo memory) {
        return _validatorInfo[validator];
    }

    /// @notice Whether `validator` is approved for OnChain quests.
    /// Backwards-compatible view over the registry.
    function approvedValidators(address validator) external view returns (bool) {
        return _validatorInfo[validator].approved;
    }

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
        uint256 maxCompletions,
        uint8 attestationThreshold
    ) external onlyRole(QUEST_CREATOR_ROLE) returns (uint256 questId) {
        if (bytes(title).length == 0 || bytes(title).length > MAX_TITLE_BYTES) {
            revert InvalidQuestParams();
        }
        if (bytes(description).length > MAX_DESCRIPTION_BYTES) revert InvalidQuestParams();
        if (rewardPoints == 0 || rewardPoints > MAX_REWARD_POINTS) revert InvalidQuestParams();
        if (startTime >= endTime || endTime <= block.timestamp) revert InvalidQuestParams();
        // PHASE 6 (R-010): threshold is uniform for ALL quest kinds (1–3)
        // and IMMUTABLE after creation — there is deliberately no setter,
        // so a live quest's bar can never be lowered (or raised to brick
        // in-flight completions) mid-flight.
        if (attestationThreshold < MIN_ATTESTATION_THRESHOLD || attestationThreshold > MAX_ATTESTATION_THRESHOLD) {
            revert AttestationThresholdOutOfRange(attestationThreshold);
        }
        if (badgeId != 0 && !achievement.isBadgeDefined(badgeId)) {
            revert IAchievement.BadgeNotDefined(badgeId);
        }
        // Validation-kind rules (TEMUAN 1): OnChain quests REQUIRE a
        // validator contract (code must exist); CheckIn and Attested
        // quests REQUIRE validator == address(0).
        // PRE-TESTNET CLEANUP (item 6): the validator must ALSO be on the
        // admin-approved allowlist — a creator cannot attach an arbitrary
        // contract, even one with code.
        if (validationKind == ValidationKind.OnChain) {
            if (validator == address(0) || validator.code.length == 0) revert InvalidValidator(validator);
            if (!_validatorInfo[validator].approved) revert ValidatorNotApproved(validator);
        } else if (validator != address(0)) {
            revert InvalidValidator(validator);
        }
        questId = ++_questCount;
        // Field-by-field storage assignment (not a struct literal): the
        // 11-parameter signature + struct literal exceeds the EVM stack
        // ("stack too deep") — this form keeps every value in storage
        // without holding them all on the stack at once.
        Quest storage quest = _quests[questId];
        quest.id = questId;
        quest.creator = msg.sender;
        quest.title = title;
        quest.description = description;
        quest.questType = questType;
        quest.validationKind = validationKind;
        quest.validator = validator;
        quest.rewardPoints = rewardPoints;
        quest.badgeId = badgeId;
        quest.startTime = startTime;
        quest.endTime = endTime;
        quest.maxCompletions = maxCompletions; // 0 = unlimited
        quest.completions = 0;
        quest.active = true;
        quest.attestationThreshold = attestationThreshold;
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
    /// @dev Order: kind gate → attestation verification (array bounds,
    /// deadline, EIP-712 signatures, verifier roles, distinctness,
    /// threshold, nonce consumption) → shared completion.
    /// The nonce is consumed inside _verifyAttestations; if the
    /// completion then reverts, the whole transaction reverts and the
    /// nonce is NOT consumed, so the same attestation can be retried.
    function completeQuestWithAttestation(uint256 questId, uint256 deadline, bytes[] calldata signatures)
        external
        nonReentrant
        whenNotPaused
    {
        Quest storage quest = _quests[questId];
        if (quest.id == 0) revert QuestNotFound(questId);
        if (quest.validationKind != ValidationKind.Attested) revert QuestNotAttested(questId);
        _verifyAttestations(msg.sender, questId, deadline, signatures, quest.attestationThreshold);
        _completeQuest(quest, questId);
    }

    /// @notice Verify an array of EIP-712 attestations and consume the
    /// account nonce exactly once.
    /// @dev PHASE 6 (R-010): threshold attestation (M-of-N). All signers
    /// sign the SAME digest (account + questId + nonce + deadline); the
    /// EIP-712 struct and domain are unchanged from the single-verifier
    /// scheme. Every signature in the array must recover (ECDSA.tryRecover
    /// rejects malleable/malformed signatures — see OpenZeppelin ECDSA)
    /// to a DISTINCT VERIFIER_ROLE holder; a duplicate reverts, a junk
    /// signature anywhere reverts, and fewer than `threshold` distinct
    /// valid signers revert. Extra signatures beyond the threshold are
    /// allowed but must still be valid. The domain separator binds
    /// chainId + this contract (cross-chain and cross-contract replay
    /// are impossible); the struct binds account + questId + nonce +
    /// deadline. Distinctness is enforced pairwise (O(M²), fine for
    /// M ≤ MAX_ATTESTATION_SIGNATURES = 5).
    function _verifyAttestations(
        address account,
        uint256 questId,
        uint256 deadline,
        bytes[] calldata signatures,
        uint8 threshold
    ) internal {
        uint256 provided = signatures.length;
        if (provided == 0) revert InsufficientAttestations(0, threshold);
        if (provided > MAX_ATTESTATION_SIGNATURES) revert TooManyAttestationSignatures(provided);
        if (deadline < block.timestamp) revert AttestationExpired(deadline, block.timestamp);
        if (deadline > block.timestamp + MAX_ATTESTATION_LIFETIME) {
            revert AttestationDeadlineTooFar(deadline, block.timestamp + MAX_ATTESTATION_LIFETIME);
        }
        uint256 nonce = nonces[account];
        bytes32 digest = _attestationDigest(account, questId, nonce, deadline);
        address[] memory signers = new address[](provided);
        for (uint256 i = 0; i < provided; ++i) {
            address signer = _recoverAttestationSigner(digest, signatures[i]);
            for (uint256 j = 0; j < i; ++j) {
                if (signers[j] == signer) revert DuplicateAttestationSigner(signer);
            }
            signers[i] = signer;
        }
        if (provided < threshold) revert InsufficientAttestations(provided, threshold);
        // Consume the nonce EXACTLY ONCE per completion, regardless of
        // how many signatures were provided: a replayed attestation
        // signs a stale nonce and recovers a different signer.
        unchecked {
            nonces[account] = nonce + 1;
        }
        // One AttestationUsed event per distinct signer (keeps the
        // per-signer accounting and SOP weekly review working unchanged).
        for (uint256 i = 0; i < provided; ++i) {
            emit AttestationUsed(account, questId, nonce, signers[i]);
        }
    }

    /// @notice EIP-712 digest for one attestation (struct hash + domain).
    /// @dev Split out of _verifyAttestations to keep the verifier loop's
    /// stack shallow (the 5-parameter function + loop + recovery would
    /// otherwise hit "stack too deep" in the legacy code generator).
    function _attestationDigest(address account, uint256 questId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(ATTESTATION_TYPEHASH, account, questId, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

    /// @notice Recover one attestation signer and check VERIFIER_ROLE.
    /// @dev Split out of _verifyAttestations for the same stack-depth
    /// reason: ECDSA.tryRecover takes `bytes memory`, so the calldata
    /// element is copied to memory inside this small frame.
    /// tryRecover's third return is the error argument (the offending `s`
    /// for InvalidSignatureS, the length for InvalidSignatureLength); it
    /// is bytes32(0) on success. It is carried into the revert so a bad
    /// attestation is diagnosable off-chain.
    function _recoverAttestationSigner(bytes32 digest, bytes calldata signature)
        internal
        view
        returns (address signer)
    {
        ECDSA.RecoverError err;
        bytes32 errorArg;
        (signer, err, errorArg) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer == address(0)) {
            revert InvalidAttestationSignature(errorArg);
        }
        if (!hasRole(VERIFIER_ROLE, signer)) revert UnauthorizedVerifier(signer);
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
        // change. A false result reverts; a reverting validator reverts
        // too (fail-closed, with a uniform error). The call is a
        // STATICCALL with a returndata length check: a validator that
        // attempts a state change (reentry, storage write) has its call
        // reverted at the EVM level, so `view` is enforced on-chain, not
        // just promised by the interface (FINAL REMEDIATION, Phase 5).
        // PRE-TESTNET CLEANUP (item 6): approval is re-checked here so a
        // revocation immediately stops completions of existing quests.
        if (quest.validationKind == ValidationKind.OnChain) {
            if (!_validatorInfo[quest.validator].approved) revert ValidatorNotApproved(quest.validator);
            if (!_validateOnChain(quest.validator, msg.sender, questId)) {
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
    /// @dev FINAL REMEDIATION (Phase 5): approval is a registry entry
    /// with mandatory metadata. Re-approval overwrites metadata +
    /// approvedAt (the admin re-reviews the instance).
    function approveValidator(
        address validator,
        string calldata name,
        string calldata version,
        string calldata documentation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (validator == address(0) || validator.code.length == 0) {
            revert InvalidValidator(validator);
        }
        if (bytes(name).length == 0 || bytes(version).length == 0 || bytes(documentation).length == 0) {
            revert InvalidValidatorMetadata();
        }
        _validatorInfo[validator] = IQuestManager.ValidatorInfo({
            name: name, version: version, documentation: documentation, approvedAt: block.timestamp, approved: true
        });
        emit ValidatorApproved(validator);
    }

    /// @inheritdoc IQuestManager
    /// @dev Metadata is KEPT (audit trail); only `approved` flips.
    /// Idempotent on purpose: revoking a validator that was never
    /// approved (or already revoked) still succeeds, so an emergency
    /// revocation can never be blocked by stale state.
    function revokeValidator(address validator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _validatorInfo[validator].approved = false;
        emit ValidatorRevoked(validator);
    }

    /// @inheritdoc IQuestManager
    /// @dev Fast path (no timelock) for a compromised or malicious
    /// validator. Same effect as revokeValidator; re-approval still
    /// requires the admin (timelock). Idempotent.
    function emergencyRevokeValidator(address validator) external onlyRole(PAUSER_ROLE) {
        _validatorInfo[validator].approved = false;
        emit ValidatorRevoked(validator);
    }

    /// @notice Call a validator's validate() via STATICCALL and check its
    /// returndata strictly.
    /// @dev FINAL REMEDIATION (Phase 5): the staticcall enforces
    /// view-ness at the EVM level — a validator that attempts any state
    /// change (storage write, reentry into a state-changing function)
    /// has the whole call reverted. Malformed returndata (wrong length
    /// or a bool word other than 0/1) reverts with a dedicated error
    /// instead of an ABI-decoding panic. A reverting validator fails
    /// closed with ValidatorCallFailed rather than propagating the
    /// validator's arbitrary revert data.
    function _validateOnChain(address validator, address account, uint256 questId) internal view returns (bool) {
        (bool success, bytes memory data) =
            validator.staticcall(abi.encodeWithSelector(IQuestValidator.validate.selector, account, questId));
        if (!success) revert ValidatorCallFailed(validator);
        if (data.length != 32) revert InvalidValidatorReturndata(validator);
        uint256 word;
        assembly {
            word := mload(add(data, 32))
        }
        if (word > 1) revert InvalidValidatorReturndata(validator);
        return word == 1;
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
