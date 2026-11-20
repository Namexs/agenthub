// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {IAchievement} from "../src/interfaces/IAchievement.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {AlwaysTrueValidator} from "./mocks/MaliciousValidators.t.sol";

/// @notice PHASE 8 (PH7-H01 / PH7-M02 / PH7-L07 / PH7-L10): threshold
/// policy enforcement tests. Phase 7 found the threshold policy lived
/// ONLY in the SOP — no test asserted it, and no code enforced it.
/// These tests pin the on-chain policy:
/// - Attested quest with rewardPoints > 1,000 REQUIRES threshold ≥ 2.
/// - Attested quest with a high-value badge REQUIRES threshold ≥ 2.
/// - The policy applies to Attested quests ONLY: CheckIn/OnChain quests
///   store a threshold but never enforce it at completion (PH7-L08), so
///   a 10,000-point CheckIn quest with threshold 1 is legitimate.
/// - Deactivate + recreate cannot pay the same account twice once the
///   admin links the new quest to the old one (setSupersedes).
contract PolicyEnforcementTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;
    AlwaysTrueValidator internal validator;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant VERIFIER_KEY = 0xA11CE5;
    uint256 internal constant VERIFIER2_KEY = 0xBEEF2;
    uint256 internal constant VERIFIER3_KEY = 0xCAFE3;
    address internal verifier;
    address internal verifier2;
    address internal verifier3;

    uint256 internal constant BADGE_ID = 1;
    uint256 internal constant HIGH_VALUE_BADGE_ID = 2;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        verifier = vm.addr(VERIFIER_KEY);
        verifier2 = vm.addr(VERIFIER2_KEY);
        verifier3 = vm.addr(VERIFIER3_KEY);

        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new Reputation(admin);
        achievement = new Achievement(admin);
        qm = new QuestManager(address(gate), address(reputation), address(achievement), admin);
        validator = new AlwaysTrueValidator();

        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        achievement.grantRole(achievement.BADGE_MANAGER_ROLE(), admin);
        achievement.defineBadge(BADGE_ID, "Ordinary Badge", "ipfs://badge1");
        achievement.defineBadge(HIGH_VALUE_BADGE_ID, "VIP Badge", "ipfs://badge2");
        achievement.setBadgeHighValue(HIGH_VALUE_BADGE_ID, true);
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier2);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier3);
        qm.approveValidator(address(validator), "AlwaysTrueValidator", "1.0.0", "test only");

        mockId.mint(alice);
        mockId.mint(bob);
        vm.warp(1_000_000);
    }

    function _createAttested(string memory title, uint256 reward, uint256 badgeId, uint8 threshold)
        internal
        returns (uint256)
    {
        vm.prank(creator);
        return qm.createQuest(
            title,
            "policy test quest",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            reward,
            badgeId,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            threshold
        );
    }

    function _createKind(
        IQuestManager.ValidationKind kind,
        uint256 reward,
        uint256 badgeId,
        uint8 threshold,
        address validator_
    ) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Kind Quest",
            "policy test quest",
            IQuestManager.QuestType.OneTime,
            kind,
            validator_,
            reward,
            badgeId,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            threshold
        );
    }

    // --- EIP-712 signing helpers (computed independently from the contract) ---

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("AGENTHUB QuestManager")),
                keccak256(bytes("1")),
                block.chainid,
                address(qm)
            )
        );
    }

    function _digest(address account, uint256 questId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(qm.ATTESTATION_TYPEHASH(), account, questId, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _sign(uint256 key, address account, uint256 questId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _digest(account, questId, nonce, deadline));
        return abi.encodePacked(r, s, v);
    }

    function _sigs(bytes memory sig) internal pure returns (bytes[] memory sigs) {
        sigs = new bytes[](1);
        sigs[0] = sig;
    }

    function _sigs2(bytes memory sig1, bytes memory sig2) internal pure returns (bytes[] memory sigs) {
        sigs = new bytes[](2);
        sigs[0] = sig1;
        sigs[1] = sig2;
    }

    // --- PH7-H01: reward-based policy ---

    function test_HighReward1001Threshold1Reverts() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientAttestations.selector, 1, 2));
        qm.createQuest(
            "High",
            "1,001 points at threshold 1",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            1_001,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            1
        );
    }

    function test_HighReward1001Threshold2Succeeds() public {
        uint256 id = _createAttested("High T2", 1_001, 0, 2);
        assertEq(qm.getQuest(id).attestationThreshold, 2);
        assertEq(qm.getQuest(id).rewardPoints, 1_001);
    }

    function test_Reward1000BoundaryThreshold1Succeeds() public {
        // The policy is rewardPoints > 1,000 — exactly 1,000 is NOT
        // high-value, so threshold 1 is legitimate.
        uint256 id = _createAttested("Boundary", 1_000, 0, 1);
        assertEq(qm.getQuest(id).attestationThreshold, 1);
    }

    function test_Reward10000Threshold1Reverts() public {
        // The Phase 7 reproduction case: a 10,000-point Attested quest
        // at threshold 1 (one compromised verifier could farm it).
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientAttestations.selector, 1, 2));
        qm.createQuest(
            "Max",
            "10,000 points at threshold 1",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            10_000,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            1
        );
    }

    function test_Reward10000Threshold3Succeeds() public {
        uint256 id = _createAttested("Max T3", 10_000, 0, 3);
        assertEq(qm.getQuest(id).attestationThreshold, 3);
    }

    // --- PH7-M02: high-value badge policy ---

    function test_HighValueBadgeThreshold1Reverts() public {
        // 100 points only — but the badge unlocks real-world value, so
        // threshold 1 is not enough.
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientAttestations.selector, 1, 2));
        qm.createQuest(
            "VIP",
            "high-value badge at threshold 1",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            HIGH_VALUE_BADGE_ID,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            1
        );
    }

    function test_HighValueBadgeThreshold2Succeeds() public {
        uint256 id = _createAttested("VIP T2", 100, HIGH_VALUE_BADGE_ID, 2);
        assertEq(qm.getQuest(id).attestationThreshold, 2);
        assertEq(qm.getQuest(id).badgeId, HIGH_VALUE_BADGE_ID);
    }

    function test_OrdinaryBadgeThreshold1Succeeds() public {
        uint256 id = _createAttested("Ordinary", 100, BADGE_ID, 1);
        assertEq(qm.getQuest(id).attestationThreshold, 1);
    }

    function test_HighValueFlagIsMutableAndReadAtCreation() public {
        // The flag is a mutable policy classification (see IAchievement):
        // clearing it lets a threshold-1 quest be created afterwards.
        achievement.setBadgeHighValue(HIGH_VALUE_BADGE_ID, false);
        assertFalse(achievement.isBadgeHighValue(HIGH_VALUE_BADGE_ID));
        uint256 id = _createAttested("VIP cleared", 100, HIGH_VALUE_BADGE_ID, 1);
        // Re-flagging the badge does NOT retroactively change the live
        // quest's threshold (thresholds are immutable): the threshold-1
        // quest still completes with one signature.
        achievement.setBadgeHighValue(HIGH_VALUE_BADGE_ID, true);
        assertEq(qm.getQuest(id).attestationThreshold, 1);
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, id, qm.nonces(alice), deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(id, deadline, _sigs(sig));
        assertEq(reputation.points(alice), 100);
    }

    function test_SetBadgeHighValueValidation() public {
        // Undefined badge: revert (the flag may only classify badges
        // that exist).
        vm.expectRevert(abi.encodeWithSelector(IAchievement.BadgeNotDefined.selector, 999));
        achievement.setBadgeHighValue(999, true);
        // Non-manager: revert (only BADGE_MANAGER_ROLE). Hoist the role
        // lookup before prank/expectRevert: a contract call between
        // them would consume the prank / the expected revert.
        bytes32 badgeManagerRole = achievement.BADGE_MANAGER_ROLE();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, badgeManagerRole)
        );
        achievement.setBadgeHighValue(BADGE_ID, true);
        // Getter never reverts: badgeId 0 and undefined badges are
        // simply not high-value.
        assertFalse(achievement.isBadgeHighValue(0));
        assertFalse(achievement.isBadgeHighValue(999));
        assertFalse(achievement.isBadgeHighValue(BADGE_ID));
        assertTrue(achievement.isBadgeHighValue(HIGH_VALUE_BADGE_ID));
    }

    // --- Policy scope: Attested only (PH7-I07) ---

    function test_CheckInHighRewardExemptFromPolicy() public {
        // DOCUMENTED SCOPE DECISION: the policy binds Attested quests
        // only. A CheckIn quest's threshold is stored but never enforced
        // at completion (anyone can self-complete it), so requiring
        // threshold 2 would be theater — the "protection" would not
        // exist. A 10,000-point CheckIn quest is therefore legitimate
        // at threshold 1; if the team ever wants a reward cap per kind,
        // that is a separate policy decision (PH7-I07).
        uint256 id = _createKind(IQuestManager.ValidationKind.CheckIn, 10_000, 0, 1, address(0));
        assertEq(qm.getQuest(id).rewardPoints, 10_000);
        assertEq(qm.getQuest(id).attestationThreshold, 1);
    }

    function test_OnChainHighRewardExemptFromPolicy() public {
        // Same scope decision for OnChain quests: their proof is the
        // validator contract, not attestations.
        uint256 id = _createKind(IQuestManager.ValidationKind.OnChain, 10_000, 0, 1, address(validator));
        assertEq(qm.getQuest(id).rewardPoints, 10_000);
    }

    function test_CheckInHighValueBadgeExemptFromPolicy() public {
        // A high-value badge on a non-Attested quest does not trigger
        // the threshold rule either — same reasoning as above.
        uint256 id = _createKind(IQuestManager.ValidationKind.CheckIn, 100, HIGH_VALUE_BADGE_ID, 1, address(0));
        assertEq(qm.getQuest(id).badgeId, HIGH_VALUE_BADGE_ID);
    }

    // --- Range checks still fire first (PH7-L10) ---

    function test_ThresholdZeroAndFourStillRevert() public {
        // Even at 10,000 points, an out-of-range threshold reports the
        // range error (checked before the policy).
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationThresholdOutOfRange.selector, 0));
        qm.createQuest(
            "T0",
            "threshold 0",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            10_000,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            0
        );
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationThresholdOutOfRange.selector, 4));
        qm.createQuest(
            "T4",
            "threshold 4",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            10_000,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            4
        );
    }

    // --- PH7-L07: deactivate + recreate cannot double-pay ---

    function test_SupersedesBlocksDoubleClaim() public {
        // The Phase 7 PoC scenario (testA2): Alice completes a
        // threshold-2 quest (100 points), the creator deactivates it
        // and recreates the same quest at threshold 1. WITHOUT the
        // supersedes link, Alice could complete the recreate for a
        // second 100 points (200 total). WITH the link, her second
        // completion reverts — while Bob, who never completed the old
        // quest, can still complete the new one.
        uint256 oldQuest = _createAttested("Post T2", 100, 0, 2);
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _sigs2(
            _sign(VERIFIER_KEY, alice, oldQuest, qm.nonces(alice), deadline),
            _sign(VERIFIER2_KEY, alice, oldQuest, qm.nonces(alice), deadline)
        );
        vm.prank(alice);
        qm.completeQuestWithAttestation(oldQuest, deadline, sigs);
        assertEq(reputation.points(alice), 100);

        vm.prank(creator);
        qm.deactivateQuest(oldQuest);
        uint256 newQuest = _createAttested("Post T1 (recreate)", 100, 0, 1);
        qm.setSupersedes(newQuest, oldQuest);
        assertEq(qm.supersedes(newQuest), oldQuest);

        // Alice's second completion reverts.
        uint256 deadline2 = block.timestamp + 1 days;
        bytes memory aliceSig = _sign(VERIFIER_KEY, alice, newQuest, qm.nonces(alice), deadline2);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IQuestManager.AlreadyCompletedSupersededQuest.selector, alice, newQuest, oldQuest)
        );
        qm.completeQuestWithAttestation(newQuest, deadline2, _sigs(aliceSig));
        assertEq(reputation.points(alice), 100, "double claim paid out");
        assertEq(qm.nonces(alice), 1, "failed completion burned a nonce");

        // Bob never completed the old quest: the recreate is open to him.
        bytes memory bobSig = _sign(VERIFIER_KEY, bob, newQuest, qm.nonces(bob), deadline2);
        vm.prank(bob);
        qm.completeQuestWithAttestation(newQuest, deadline2, _sigs(bobSig));
        assertEq(reputation.points(bob), 100);
    }

    function test_SetSupersedesValidation() public {
        uint256 oldQuest = _createAttested("Old", 100, 0, 1);
        uint256 newQuest = _createAttested("New", 100, 0, 1);
        // Both quests must exist.
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotFound.selector, 999));
        qm.setSupersedes(999, oldQuest);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotFound.selector, 999));
        qm.setSupersedes(newQuest, 999);
        // A quest cannot supersede itself.
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.setSupersedes(newQuest, newQuest);
        // Admin only (timelock in production). Hoist the role lookup
        // before prank/expectRevert (see above).
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, creator, adminRole)
        );
        qm.setSupersedes(newQuest, oldQuest);
        // Happy path: the link is stored and readable.
        qm.setSupersedes(newQuest, oldQuest);
        assertEq(qm.supersedes(newQuest), oldQuest);
        assertEq(qm.supersedes(oldQuest), 0, "old quest supersedes nothing");
    }
}
