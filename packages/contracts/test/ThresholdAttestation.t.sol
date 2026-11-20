// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice PHASE 6 (R-010) threshold (M-of-N) attestation tests.
/// Every test names the property it proves: happy paths at thresholds
/// 1/2/3, the reject cases (too few, duplicate, unauthorized, malformed,
/// wrong binding, too many, empty), the creation bounds (1–3), the
/// nonce invariants (consumed exactly once, never burned by a failed
/// completion), per-signer events, revocation, deadlines, and threshold
/// immutability. The EIP-712 digest is computed independently from the
/// contract (domain separator + struct hash), exactly as in
/// Attestation.t.sol, so a domain mismatch fails the happy-path tests
/// instead of passing vacuously.
contract ThresholdAttestationTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant VERIFIER_KEY = 0xA11CE5;
    uint256 internal constant VERIFIER2_KEY = 0xBEEF2;
    uint256 internal constant VERIFIER3_KEY = 0xCAFE3;
    uint256 internal constant ATTACKER_KEY = 0xBADC0DE;
    address internal verifier;
    address internal verifier2;
    address internal verifier3;
    address internal attacker;

    uint256 internal questT1;
    uint256 internal questT2;
    uint256 internal questT3;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        verifier = vm.addr(VERIFIER_KEY);
        verifier2 = vm.addr(VERIFIER2_KEY);
        verifier3 = vm.addr(VERIFIER3_KEY);
        attacker = vm.addr(ATTACKER_KEY);

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
        mockId.mint(bob);
        mockId.mint(carol);
        vm.warp(1_000_000);

        vm.startPrank(creator);
        questT1 = _createAttested("Post T1", 100, 1);
        questT2 = _createAttested("Post T2", 100, 2);
        questT3 = _createAttested("Post T3", 100, 3);
        vm.stopPrank();
    }

    function _createAttested(string memory title, uint256 reward, uint8 threshold) internal returns (uint256) {
        return qm.createQuest(
            title,
            "Share AGENTHUB on X",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            reward,
            0,
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

    /// @dev Sign the SAME digest with every key in `keys` (the threshold
    /// scheme: all M signers sign one digest).
    function _signMany(uint256[] memory keys, address account, uint256 questId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes[] memory sigs)
    {
        sigs = new bytes[](keys.length);
        for (uint256 i = 0; i < keys.length; ++i) {
            sigs[i] = _sign(keys[i], account, questId, nonce, deadline);
        }
    }

    function _keys1() internal pure returns (uint256[] memory keys) {
        keys = new uint256[](1);
        keys[0] = VERIFIER_KEY;
    }

    function _keys2() internal pure returns (uint256[] memory keys) {
        keys = new uint256[](2);
        keys[0] = VERIFIER_KEY;
        keys[1] = VERIFIER2_KEY;
    }

    function _keys3() internal pure returns (uint256[] memory keys) {
        keys = new uint256[](3);
        keys[0] = VERIFIER_KEY;
        keys[1] = VERIFIER2_KEY;
        keys[2] = VERIFIER3_KEY;
    }

    function _complete(address account, uint256 questId, uint256 deadline, bytes[] memory sigs) internal {
        vm.prank(account);
        qm.completeQuestWithAttestation(questId, deadline, sigs);
    }

    // --- Happy paths ---

    function test_Threshold1WithOneSignatureCompletes() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys1(), alice, questT1, qm.nonces(alice), deadline);
        _complete(alice, questT1, deadline, sigs);
        assertEq(reputation.points(alice), 100);
        assertTrue(qm.hasCompleted(alice, questT1));
        assertEq(qm.nonces(alice), 1);
    }

    function test_Threshold2WithTwoDistinctVerifiersCompletes() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys2(), alice, questT2, qm.nonces(alice), deadline);
        _complete(alice, questT2, deadline, sigs);
        assertEq(reputation.points(alice), 100);
        assertTrue(qm.hasCompleted(alice, questT2));
        assertEq(qm.nonces(alice), 1);
    }

    function test_Threshold3WithThreeDistinctVerifiersCompletes() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys3(), alice, questT3, qm.nonces(alice), deadline);
        _complete(alice, questT3, deadline, sigs);
        assertEq(reputation.points(alice), 100);
        assertTrue(qm.hasCompleted(alice, questT3));
        assertEq(qm.nonces(alice), 1);
    }

    function test_ExtraSignaturesBeyondThresholdAllowed() public {
        // Plan §2.1: extra signatures beyond M are allowed (each must
        // still be a valid distinct verifier).
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys3(), alice, questT2, qm.nonces(alice), deadline);
        _complete(alice, questT2, deadline, sigs);
        assertEq(reputation.points(alice), 100);
        assertEq(qm.nonces(alice), 1, "nonce consumed more than once with extra signatures");
    }

    function test_ThresholdStoredAtCreation() public {
        assertEq(qm.getQuest(questT1).attestationThreshold, 1);
        assertEq(qm.getQuest(questT2).attestationThreshold, 2);
        assertEq(qm.getQuest(questT3).attestationThreshold, 3);
    }

    // --- Too few signatures ---

    function test_Threshold2WithOneSignatureReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys1(), alice, questT2, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientAttestations.selector, 1, 2));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_Threshold3WithTwoSignaturesReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys2(), alice, questT3, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientAttestations.selector, 2, 3));
        qm.completeQuestWithAttestation(questT3, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_EmptySignatureArrayReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InsufficientAttestations.selector, 0, 2));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(qm.nonces(alice), 0);
    }

    function test_MoreThanFiveSignaturesReverts() public {
        // The length cap is checked before any recovery, so six copies
        // of one valid signature still hit the cap (not the duplicate
        // check).
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        bytes[] memory sigs = new bytes[](6);
        for (uint256 i = 0; i < 6; ++i) {
            sigs[i] = sig;
        }
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.TooManyAttestationSignatures.selector, 6));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(qm.nonces(alice), 0);
    }

    function test_FiveSignaturesAccepted() public {
        // Boundary: exactly MAX_ATTESTATION_SIGNATURES (5) is accepted.
        // Threshold 2 + 5 entries needs 5 distinct verifiers, so grant
        // two extra ones for this test.
        address verifier4 = vm.addr(0xAAAA4);
        address verifier5 = vm.addr(0xAAAA5);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier4);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier5);
        uint256[] memory keys = new uint256[](5);
        keys[0] = VERIFIER_KEY;
        keys[1] = VERIFIER2_KEY;
        keys[2] = VERIFIER3_KEY;
        keys[3] = 0xAAAA4;
        keys[4] = 0xAAAA5;
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(keys, alice, questT2, qm.nonces(alice), deadline);
        _complete(alice, questT2, deadline, sigs);
        assertEq(reputation.points(alice), 100);
        assertEq(qm.nonces(alice), 1);
    }

    // --- Duplicate / unauthorized / malformed ---

    function test_DuplicateSignerReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = sig;
        sigs[1] = sig; // same signer twice — never counted once
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.DuplicateAttestationSigner.selector, verifier));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_TwoValidPlusUnauthorizedReverts() public {
        // Junk anywhere in the array fails the whole call, even when
        // the threshold is already met by the valid signatures.
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        sigs[1] = _sign(VERIFIER2_KEY, alice, questT2, qm.nonces(alice), deadline);
        sigs[2] = _sign(ATTACKER_KEY, alice, questT2, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, attacker));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_MalformedSignatureInArrayReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        sigs[1] = new bytes(10); // malformed: bad length
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IQuestManager.InvalidAttestationSignature.selector, bytes32(uint256(10)))
        );
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    // --- Wrong binding: nonce / quest / deadline ---

    function test_SignatureForDifferentNonceReverts() public {
        // Verifier 2 signed over nonce 5 while the current nonce is 0:
        // the digest differs, so recovery yields a non-verifier.
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        sigs[1] = _sign(VERIFIER2_KEY, alice, questT2, 5, deadline);
        address recovered = ECDSA.recover(_digest(alice, questT2, 0, deadline), sigs[1]);
        assertTrue(recovered != verifier && recovered != verifier2, "test setup: wrong-nonce sig recovered a verifier");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, recovered));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_SignatureForDifferentQuestReverts() public {
        // Verifier 2 signed for questT3, submitted for questT2.
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        sigs[1] = _sign(VERIFIER2_KEY, alice, questT3, qm.nonces(alice), deadline);
        address recovered = ECDSA.recover(_digest(alice, questT2, 0, deadline), sigs[1]);
        assertTrue(recovered != verifier && recovered != verifier2, "test setup: wrong-quest sig recovered a verifier");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, recovered));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_SignatureForDifferentDeadlineReverts() public {
        // Verifier 2 signed over a different deadline than the one
        // submitted: the digest differs, so recovery yields a
        // non-verifier.
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(VERIFIER_KEY, alice, questT2, qm.nonces(alice), deadline);
        sigs[1] = _sign(VERIFIER2_KEY, alice, questT2, qm.nonces(alice), deadline + 1 days);
        address recovered = ECDSA.recover(_digest(alice, questT2, 0, deadline), sigs[1]);
        assertTrue(
            recovered != verifier && recovered != verifier2, "test setup: wrong-deadline sig recovered a verifier"
        );
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, recovered));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    // --- Creation bounds (uniform for ALL quest kinds) ---

    function test_ThresholdZeroAtCreationReverts() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationThresholdOutOfRange.selector, 0));
        qm.createQuest(
            "T0",
            "threshold 0",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            0
        );
    }

    function test_ThresholdFourAtCreationReverts() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationThresholdOutOfRange.selector, 4));
        qm.createQuest(
            "T4",
            "threshold 4",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            4
        );
    }

    function test_ThresholdBoundsApplyToNonAttestedQuests() public {
        // The 1–3 bound is uniform: a CheckIn quest with threshold 0
        // reverts the same way, and threshold 3 stores fine (unused).
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationThresholdOutOfRange.selector, 0));
        qm.createQuest(
            "C0",
            "check-in threshold 0",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            0
        );
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "C3",
            "check-in threshold 3",
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
    }

    // --- Nonce invariants ---

    function test_NonceConsumedExactlyOnceThenReplayReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys2(), alice, questT2, qm.nonces(alice), deadline);
        _complete(alice, questT2, deadline, sigs);
        assertEq(qm.nonces(alice), 1, "threshold-2 completion moved the nonce by != 1");
        // Replay the same attestation (stale nonce): the digest changes
        // and the recovered signers are no longer the verifiers.
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(qm.nonces(alice), 1, "replay consumed a nonce");
        assertEq(reputation.points(alice), 100, "replay awarded points twice");
    }

    function test_FailedCompletionDoesNotBurnNonceWithMSignatures() public {
        // Capped threshold-2 quest (1 completion): alice takes the only
        // slot, then bob's valid 2-signature attestation fails with
        // QuestFull — and bob's nonce must NOT be consumed.
        vm.prank(creator);
        uint256 capped = qm.createQuest(
            "Capped T2",
            "one slot only",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            1,
            2
        );
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory aliceSigs = _signMany(_keys2(), alice, capped, qm.nonces(alice), deadline);
        _complete(alice, capped, deadline, aliceSigs);
        assertEq(qm.nonces(alice), 1);

        bytes[] memory bobSigs = _signMany(_keys2(), bob, capped, qm.nonces(bob), deadline);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestFull.selector, capped));
        qm.completeQuestWithAttestation(capped, deadline, bobSigs);
        assertEq(qm.nonces(bob), 0, "failed threshold completion consumed a nonce");
        assertEq(reputation.points(bob), 0);
    }

    // --- Events: one AttestationUsed per distinct signer ---

    function test_EachSignerGetsAttestationUsedEvent() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys3(), alice, questT3, qm.nonces(alice), deadline);
        vm.recordLogs();
        _complete(alice, questT3, deadline, sigs);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sigHash = keccak256("AttestationUsed(address,uint256,uint256,address)");
        uint256 found;
        address[3] memory seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(qm) && logs[i].topics.length == 4 && logs[i].topics[0] == sigHash) {
                address account = address(uint160(uint256(logs[i].topics[1])));
                uint256 questId = uint256(logs[i].topics[2]);
                address signer = address(uint160(uint256(logs[i].topics[3])));
                uint256 nonce = abi.decode(logs[i].data, (uint256));
                assertEq(account, alice);
                assertEq(questId, questT3);
                assertEq(nonce, 0);
                seen[found] = signer;
                found++;
            }
        }
        assertEq(found, 3, "expected one AttestationUsed per signer");
        assertEq(seen[0], verifier);
        assertEq(seen[1], verifier2);
        assertEq(seen[2], verifier3);
    }

    // --- Revocation ---

    function test_RevokedSecondVerifierInvalidatesPair() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys2(), alice, questT2, qm.nonces(alice), deadline);
        // PHASE 8 (PH7-M01): revoking verifier 2 while the threshold-3
        // quest is live is BLOCKED by the guardrail (2 verifiers left
        // < highest live threshold 3) — so deactivate the threshold-3
        // quest first (the supported recovery path). The threshold-2
        // quest stays live, and the revoke then succeeds (2 ≥ 2).
        vm.prank(creator);
        qm.deactivateQuest(questT3);
        assertEq(qm.highestLiveThreshold(), 2, "deactivating T3 did not lower the highest live threshold");
        // Revoke verifier 2 AFTER signing: the role is checked at
        // verification time, so the outstanding pair is dead.
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier2);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, verifier2));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
        // Re-granting restores the same pair (no nonce was burned).
        qm.grantRole(qm.VERIFIER_ROLE(), verifier2);
        _complete(alice, questT2, deadline, sigs);
        assertEq(reputation.points(alice), 100);
    }

    // --- Deadlines with M signatures ---

    function test_ExpiredDeadlineWithMSignaturesReverts() public {
        uint256 deadline = block.timestamp - 1;
        bytes[] memory sigs = _signMany(_keys2(), alice, questT2, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationExpired.selector, deadline, block.timestamp));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(qm.nonces(alice), 0);
    }

    function test_DeadlineTooFarWithMSignaturesReverts() public {
        uint256 deadline = block.timestamp + qm.MAX_ATTESTATION_LIFETIME() + 1;
        bytes[] memory sigs = _signMany(_keys2(), alice, questT2, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IQuestManager.AttestationDeadlineTooFar.selector,
                deadline,
                block.timestamp + qm.MAX_ATTESTATION_LIFETIME()
            )
        );
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
        assertEq(qm.nonces(alice), 0);
    }

    // --- Immutability ---

    function test_ThresholdImmutable() public {
        // There is no setter: the only quest-mutating function besides
        // completion is deactivateQuest, and it must not touch the
        // threshold. The threshold is pinned at creation forever.
        assertEq(qm.getQuest(questT2).attestationThreshold, 2);
        vm.prank(creator);
        qm.deactivateQuest(questT2);
        assertEq(qm.getQuest(questT2).attestationThreshold, 2, "deactivateQuest changed the threshold");
        assertFalse(qm.getQuest(questT2).active);
        // And a threshold-2 quest still demands 2 signatures even after
        // deactivation attempts (here it fails on QuestNotActive first,
        // which proves the quest state — not the threshold — changed).
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(_keys2(), alice, questT2, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotActive.selector, questT2));
        qm.completeQuestWithAttestation(questT2, deadline, sigs);
    }

    // --- Fuzz: no shortcut to M distinct valid signers ---

    function testFuzz_Threshold3NeverCompletesWithoutThreeDistinctVerifiers(uint8[] memory picks) public {
        // Signatures drawn ONLY from {verifier1, verifier2, attacker}
        // (with replacement): at most 2 distinct valid signers exist,
        // so a threshold-3 quest can never complete, whatever the array.
        // Cap the array at 5 entries WITHOUT vm.assume: the fuzzer
        // generates arbitrary lengths, and assume-based filtering
        // exhausts the 65,536-rejection budget at 10k runs (found by
        // the Phase 6 regression battery). The property holds for any
        // length (a >5 array reverts on the cap; an empty array
        // reverts on insufficient signatures), so truncation
        // preserves the test's meaning.
        uint256 len = picks.length > 5 ? 5 : picks.length;
        if (len == 0) len = 1;
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = new bytes[](len);
        for (uint256 i = 0; i < len; ++i) {
            uint256 pick = i < picks.length ? picks[i] : 0;
            uint256 key = pick % 3 == 0 ? VERIFIER_KEY : pick % 3 == 1 ? VERIFIER2_KEY : ATTACKER_KEY;
            sigs[i] = _sign(key, alice, questT3, qm.nonces(alice), deadline);
        }
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(questT3, deadline, sigs);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function testFuzz_RandomSignatureBytesNeverCompleteThreshold2(bytes[] memory sigs) public {
        // Random signature bytes (1–5 entries): recovery either fails
        // or yields a non-verifier, so a threshold-2 quest never
        // completes. (A random 65-byte string recovering to one of our
        // three verifiers is a 2^-160 event per entry; the test would
        // fail loudly if it ever happened.)
        // Cap the array at 5 entries WITHOUT vm.assume (see the
        // threshold-3 fuzz test above for why assume is unusable at
        // 10k runs). The property holds for any length.
        uint256 len = sigs.length > 5 ? 5 : sigs.length;
        if (len == 0) len = 1;
        bytes[] memory arr = new bytes[](len);
        for (uint256 i = 0; i < len; ++i) {
            arr[i] = i < sigs.length ? sigs[i] : bytes("");
        }
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(questT2, deadline, arr);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    // --- Gas benchmark: identical quests, fresh account each, gasleft() ---

    function _measureGas(address account, uint256 questId, uint256[] memory keys) internal returns (uint256 gasUsed) {
        uint256 deadline = block.timestamp + 1 days;
        bytes[] memory sigs = _signMany(keys, account, questId, qm.nonces(account), deadline);
        uint256 before = gasleft();
        vm.prank(account);
        qm.completeQuestWithAttestation(questId, deadline, sigs);
        gasUsed = before - gasleft();
    }

    function testGas_Threshold1Completion() public {
        uint256 gasUsed = _measureGas(alice, questT1, _keys1());
        emit log_named_uint("gas threshold-1 completion", gasUsed);
        assertGt(gasUsed, 0);
        assertLt(gasUsed, 300_000, "threshold-1 completion unexpectedly expensive");
    }

    function testGas_Threshold2Completion() public {
        uint256 gasUsed = _measureGas(alice, questT2, _keys2());
        emit log_named_uint("gas threshold-2 completion", gasUsed);
        assertGt(gasUsed, 0);
        assertLt(gasUsed, 300_000, "threshold-2 completion unexpectedly expensive");
    }

    function testGas_Threshold3Completion() public {
        uint256 gasUsed = _measureGas(alice, questT3, _keys3());
        emit log_named_uint("gas threshold-3 completion", gasUsed);
        assertGt(gasUsed, 0);
        assertLt(gasUsed, 300_000, "threshold-3 completion unexpectedly expensive");
    }

    function testGas_MarginalCostPerExtraSignature() public {
        // Fresh account per threshold (alice/bob/carol): every
        // completion touches only cold per-account + per-quest storage
        // (Reputation.addPoints writes only _points[account] /
        // _events[account] — no shared counters), so the gas
        // differences between the three measurements isolate the
        // per-signature attestation cost.
        uint256 g1 = _measureGas(alice, questT1, _keys1());
        uint256 g2 = _measureGas(bob, questT2, _keys2());
        uint256 g3 = _measureGas(carol, questT3, _keys3());
        emit log_named_uint("gas t1 (fresh account)", g1);
        emit log_named_uint("gas t2 (fresh account)", g2);
        emit log_named_uint("gas t3 (fresh account)", g3);
        emit log_named_uint("marginal t1->t2", g2 - g1);
        emit log_named_uint("marginal t2->t3", g3 - g2);
        assertGt(g2, g1, "2nd signature did not cost gas");
        assertGt(g3, g2, "3rd signature did not cost gas");
    }
}
