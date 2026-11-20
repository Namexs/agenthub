// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice PHASE 8 (PH7-M01): verifier guardrail tests. Phase 7 proved
/// (two independent PoCs) that revoking VERIFIER_ROLE below a live
/// quest's threshold bricked the quest with no on-chain guard. These
/// tests pin the guardrail:
/// - revoke/renounce is rejected while it would leave fewer verifiers
///   than the highest live Attested threshold;
/// - deactivating the affected quests first unblocks the revoke, and
///   the revoked signer's outstanding attestation pair is then dead
///   (the old ThresholdAttestation assertion, via the new path);
/// - an Attested quest cannot be created above the live verifier count;
/// - non-Attested quests never affect the counters, and expired
///   quests still count until deactivated (fail-safe).
contract VerifierGuardrailTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");

    uint256 internal constant VERIFIER_KEY = 0xA11CE5;
    uint256 internal constant VERIFIER2_KEY = 0xBEEF2;
    uint256 internal constant VERIFIER3_KEY = 0xCAFE3;
    address internal verifier;
    address internal verifier2;
    address internal verifier3;

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

        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier2);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier3);

        mockId.mint(alice);
        vm.warp(1_000_000);
    }

    function _createAttested(string memory title, uint8 threshold) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            title,
            "guardrail test quest",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            threshold
        );
    }

    function _createAttestedWithWindow(string memory title, uint8 threshold, uint256 window)
        internal
        returns (uint256)
    {
        vm.prank(creator);
        return qm.createQuest(
            title,
            "guardrail test quest",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + window,
            0,
            threshold
        );
    }

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

    // --- Counter bookkeeping ---

    function test_VerifierCountTracksGrantsAndRevokes() public {
        assertEq(qm.verifierCount(), 3, "setup should have 3 verifiers");
        // A duplicate grant does not double-count (no status change).
        qm.grantRole(qm.VERIFIER_ROLE(), verifier);
        assertEq(qm.verifierCount(), 3, "duplicate grant moved the count");
        // A no-op revoke does not underflow the count.
        address stranger = makeAddr("stranger");
        qm.revokeRole(qm.VERIFIER_ROLE(), stranger);
        assertEq(qm.verifierCount(), 3, "no-op revoke moved the count");
        // A real grant/revoke moves it by exactly one.
        qm.grantRole(qm.VERIFIER_ROLE(), stranger);
        assertEq(qm.verifierCount(), 4);
        qm.revokeRole(qm.VERIFIER_ROLE(), stranger);
        assertEq(qm.verifierCount(), 3);
        // Grants of OTHER roles never touch the counter.
        qm.grantRole(qm.PAUSER_ROLE(), stranger);
        assertEq(qm.verifierCount(), 3, "non-verifier grant moved the count");
    }

    // --- Revoke guardrail ---

    function test_RevokeBlockedWhileThreshold2QuestLive() public {
        _createAttested("Post T2", 2);
        assertEq(qm.highestLiveThreshold(), 2);
        // Hoist the role lookup: a qm.VERIFIER_ROLE() call between
        // expectRevert and revokeRole would consume the expectation.
        bytes32 role = qm.VERIFIER_ROLE();
        // 3 -> 2 verifiers is fine (2 >= highest live threshold 2).
        qm.revokeRole(role, verifier3);
        assertEq(qm.verifierCount(), 2);
        // 2 -> 1 would brick the threshold-2 quest: blocked.
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.RevocationWouldBrickQuest.selector, 1, 2));
        qm.revokeRole(role, verifier2);
        assertTrue(qm.hasRole(qm.VERIFIER_ROLE(), verifier2), "blocked revoke still removed the role");
        assertEq(qm.verifierCount(), 2, "blocked revoke moved the count");
    }

    function test_RevokeSucceedsAfterDeactivate() public {
        uint256 questId = _createAttested("Post T2", 2);
        // The recovery path: deactivate the threshold-2 quest first,
        // then the revoke succeeds (no live Attested quest remains).
        // (The revoked signer's outstanding pair being dead is proven
        // separately in test_RevokedSignerPairInvalidAfterDeactivateFirst.)
        vm.prank(creator);
        qm.deactivateQuest(questId);
        assertEq(qm.highestLiveThreshold(), 0);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier2);
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), verifier2));
        assertEq(qm.verifierCount(), 2);
        // Re-granting restores the verifier (rotation completes).
        qm.grantRole(qm.VERIFIER_ROLE(), verifier2);
        assertEq(qm.verifierCount(), 3);
    }

    function test_RevokedSignerPairInvalidAfterDeactivateFirst() public {
        // The old ThresholdAttestation assertion, via the new
        // deactivate-first path: a pair signed before the revoke is
        // dead once the signer's role is gone — proven on a quest that
        // stays live (only the threshold-3 quest is deactivated to
        // unblock the revoke).
        uint256 questT2 = _createAttested("Post T2", 2);
        uint256 questT3 = _createAttested("Post T3", 3);
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        sigs[1] = _sign(VERIFIER2_KEY, alice, questT2, qm.nonces(alice), deadline);
        vm.prank(creator);
        qm.deactivateQuest(questT3);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier2);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, verifier2));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
        // Re-granting restores the same pair (no nonce was burned).
        qm.grantRole(qm.VERIFIER_ROLE(), verifier2);
        vm.prank(alice);
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 100);
    }

    function test_RenounceRoleAlsoGuarded() public {
        uint256 questId = _createAttested("Post T2", 2);
        // Hoist the role lookup (see test_RevokeBlocked...).
        bytes32 role = qm.VERIFIER_ROLE();
        // Drop to exactly 2 verifiers first (3 -> 2 is allowed).
        qm.revokeRole(role, verifier3);
        // A verifier renouncing its own role is the same removal — the
        // guard applies (renounceRole routes through _revokeRole).
        vm.prank(verifier2);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.RevocationWouldBrickQuest.selector, 1, 2));
        qm.renounceRole(role, verifier2);
        assertTrue(qm.hasRole(role, verifier2), "blocked renounce still removed the role");
        // After deactivation, the renounce succeeds.
        vm.prank(creator);
        qm.deactivateQuest(questId);
        vm.prank(verifier2);
        qm.renounceRole(role, verifier2);
        assertFalse(qm.hasRole(role, verifier2));
        assertEq(qm.verifierCount(), 1);
    }

    function test_NoOpRevokeIsNotBlocked() public {
        // Revoking an address that does NOT hold the role removes
        // nobody, so the guard must not fire — emergency revocation
        // stays idempotent even with live threshold quests.
        _createAttested("Post T2", 2);
        address stranger = makeAddr("stranger");
        qm.revokeRole(qm.VERIFIER_ROLE(), stranger);
        assertEq(qm.verifierCount(), 3);
    }

    // --- Creation guardrail ---

    function test_CreateThreshold3RejectedWithOneVerifier() public {
        // Drop to a single verifier (no live quests, so revokes pass).
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier2);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier3);
        assertEq(qm.verifierCount(), 1);
        // A threshold-3 quest would be bricked from birth: rejected.
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientVerifiers.selector, 1, 3));
        qm.createQuest(
            "T3",
            "three verifiers needed, one exists",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            3
        );
        // Granting the 2nd verifier unblocks threshold-2 creation.
        qm.grantRole(qm.VERIFIER_ROLE(), verifier2);
        uint256 id2 = _createAttested("Post T2", 2);
        assertEq(qm.getQuest(id2).attestationThreshold, 2);
        // Granting the 3rd unblocks threshold-3 creation.
        qm.grantRole(qm.VERIFIER_ROLE(), verifier3);
        uint256 id3 = _createAttested("Post T3", 3);
        assertEq(qm.getQuest(id3).attestationThreshold, 3);
    }

    function test_RegrantRestoresCreation() public {
        uint256 questId = _createAttested("Post T2", 2);
        vm.prank(creator);
        qm.deactivateQuest(questId);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier2);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier3);
        assertEq(qm.verifierCount(), 1);
        // Threshold-2 creation is blocked with one verifier...
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientVerifiers.selector, 1, 2));
        qm.createQuest(
            "T2",
            "two verifiers needed, one exists",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            2
        );
        // ...and re-granting restores it.
        qm.grantRole(qm.VERIFIER_ROLE(), verifier2);
        uint256 id = _createAttested("Post T2 again", 2);
        assertEq(qm.getQuest(id).attestationThreshold, 2);
    }

    // --- Counter derivation ---

    function test_DeactivateLowersHighestLiveThreshold() public {
        uint256 questT3 = _createAttested("Post T3", 3);
        uint256 questT2 = _createAttested("Post T2", 2);
        _createAttested("Post T1", 1);
        assertEq(qm.highestLiveThreshold(), 3);
        assertEq(qm.liveAttestedQuestCount(3), 1);
        assertEq(qm.liveAttestedQuestCount(2), 1);
        assertEq(qm.liveAttestedQuestCount(1), 1);
        assertEq(qm.liveAttestedQuestCount(0), 0, "threshold 0 has no counter");
        vm.prank(creator);
        qm.deactivateQuest(questT3);
        assertEq(qm.highestLiveThreshold(), 2);
        assertEq(qm.liveAttestedQuestCount(3), 0);
        vm.prank(creator);
        qm.deactivateQuest(questT2);
        assertEq(qm.highestLiveThreshold(), 1);
        // Deactivating twice is idempotent: the counter must not
        // underflow (a second deactivate still succeeds and re-emits).
        vm.prank(creator);
        qm.deactivateQuest(questT2);
        assertEq(qm.liveAttestedQuestCount(2), 0, "double deactivate underflowed the counter");
        assertEq(qm.highestLiveThreshold(), 1);
    }

    function test_NonAttestedQuestsDoNotAffectCounters() public {
        // A CheckIn quest with threshold 3 stored: the threshold is
        // never enforced for it (PH7-L08), so it must not raise the
        // guardrail's bar — and creating it needs no verifiers at all.
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "CheckIn T3",
            "threshold stored, never enforced",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            3
        );
        assertEq(qm.getQuest(id).attestationThreshold, 3);
        assertEq(qm.highestLiveThreshold(), 0);
        assertEq(qm.liveAttestedQuestCount(3), 0);
        // All three verifiers can be revoked with no live Attested quest.
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier2);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier3);
        assertEq(qm.verifierCount(), 0);
    }

    function test_ExpiredQuestStillCountsUntilDeactivated() public {
        // DOCUMENTED FAIL-SAFE: an Attested quest past its endTime can
        // never complete, but it still counts toward the guardrail
        // until explicitly deactivated — the contract does not scan for
        // expiry, and an operator who forgets a quest must not silently
        // lower the bar. Deactivation is the explicit step.
        uint256 questId = _createAttestedWithWindow("Short T2", 2, 1 days);
        vm.warp(block.timestamp + 2 days);
        assertEq(qm.highestLiveThreshold(), 2, "expired quest stopped counting");
        // Hoist the role lookup (see test_RevokeBlocked...).
        bytes32 role = qm.VERIFIER_ROLE();
        qm.revokeRole(role, verifier3);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.RevocationWouldBrickQuest.selector, 1, 2));
        qm.revokeRole(role, verifier2);
        // Deactivation (allowed after expiry) unblocks the revoke.
        vm.prank(creator);
        qm.deactivateQuest(questId);
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier2);
        assertEq(qm.verifierCount(), 1);
    }
}
