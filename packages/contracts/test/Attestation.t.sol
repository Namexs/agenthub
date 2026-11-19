// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {IAgentGate} from "../src/interfaces/IAgentGate.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice TEMUAN 1 attestation tests: EIP-712 attestations for off-chain
/// quests. Every test names the attack or failure it proves impossible:
/// replay, wrong account/quest/chain/contract, unauthorized signer,
/// expired or over-long attestations, malleable signatures, and verifier
/// rotation. The test computes the EIP-712 digest independently from the
/// contract (domain separator + struct hash), so a domain mismatch fails
/// the happy-path test instead of passing vacuously.
contract AttestationTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal dave = makeAddr("dave"); // NO Agent ID

    uint256 internal constant VERIFIER_KEY = 0xA11CE5;
    uint256 internal constant ATTACKER_KEY = 0xBADC0DE;
    uint256 internal constant NEW_VERIFIER_KEY = 0x5EED;
    address internal verifier;
    address internal attacker;

    uint256 internal constant BADGE_ID = 1;
    uint256 internal attestedQuest;
    uint256 internal dailyAttestedQuest;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    // secp256k1 curve order (for the malleability test).
    uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function setUp() public {
        verifier = vm.addr(VERIFIER_KEY);
        attacker = vm.addr(ATTACKER_KEY);

        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new Reputation(admin);
        achievement = new Achievement(admin);
        qm = new QuestManager(address(gate), address(reputation), address(achievement), admin);

        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        achievement.grantRole(achievement.BADGE_MANAGER_ROLE(), admin);
        achievement.defineBadge(BADGE_ID, "First Quest", "ipfs://badge1");
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier);

        mockId.mint(alice);
        mockId.mint(bob);
        // dave deliberately gets NO Agent ID.
        vm.warp(1_000_000);

        vm.startPrank(creator);
        attestedQuest = qm.createQuest(
            "Post on X",
            "Share AGENTHUB on X",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            BADGE_ID,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
        dailyAttestedQuest = qm.createQuest(
            "Daily Post",
            "Post daily",
            IQuestManager.QuestType.DailyCheckIn,
            IQuestManager.ValidationKind.Attested,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
        vm.stopPrank();
    }

    // --- EIP-712 signing helpers (computed independently from the contract) ---

    function _domainSeparator(uint256 chainId_, address verifyingContract_) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("AGENTHUB QuestManager")),
                keccak256(bytes("1")),
                chainId_,
                verifyingContract_
            )
        );
    }

    function _digest(address account, uint256 questId, uint256 nonce, uint256 deadline, uint256 chainId_, address v)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(qm.ATTESTATION_TYPEHASH(), account, questId, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(chainId_, v), structHash));
    }

    function _sign(uint256 key, address account, uint256 questId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        return _signFor(key, account, questId, nonce, deadline, block.chainid, address(qm));
    }

    function _signFor(
        uint256 key,
        address account,
        uint256 questId,
        uint256 nonce,
        uint256 deadline,
        uint256 chainId_,
        address verifyingContract_
    ) internal view returns (bytes memory) {
        bytes32 digest = _digest(account, questId, nonce, deadline, chainId_, verifyingContract_);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    // --- Happy path ---

    function test_AttestedCompletionWithValidSignature() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.expectEmit(true, true, false, true, address(qm));
        emit IQuestManager.AttestationUsed(alice, attestedQuest, 0);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 100);
        assertTrue(achievement.hasBadge(alice, BADGE_ID));
        assertTrue(qm.hasCompleted(alice, attestedQuest));
        assertEq(qm.nonces(alice), 1);
    }

    function test_AttestedCompletionEmitsQuestCompleted() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.expectEmit(true, true, false, true, address(qm));
        emit IQuestManager.QuestCompleted(attestedQuest, alice, 100, 1);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
    }

    // --- Replay protection ---

    function test_ReplaySameAttestationReverts() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 100);
        // Same signature, same deadline: the nonce moved, so the digest
        // changes and the recovered signer is no longer the verifier.
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 100, "replay awarded points twice");
        assertEq(qm.nonces(alice), 1, "replay consumed a nonce");
    }

    function test_WrongNonceRejected() public {
        // Signed over nonce 5 while the current nonce is 0.
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, 5, deadline);
        // The contract hashes nonce 0; recovery yields a different address.
        bytes32 digest = _digest(alice, attestedQuest, 0, deadline, block.chainid, address(qm));
        address recovered = ECDSA.recover(digest, sig);
        assertTrue(recovered != verifier, "test setup: wrong-nonce sig recovered the verifier");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, recovered));
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    // --- Binding: account / quest / chain / contract ---

    function test_WrongAccountRejected() public {
        // Attestation signed FOR bob, submitted BY alice.
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, bob, attestedQuest, qm.nonces(bob), deadline);
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
        assertEq(reputation.points(bob), 0);
    }

    function test_WrongQuestRejected() public {
        // Attestation signed for the daily quest, submitted for the one-time quest.
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, dailyAttestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
    }

    function test_CrossChainReplayRejected() public {
        // Signed with a mainnet (56) domain; submitted on this chain (31337).
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _signFor(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline, 56, address(qm));
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
    }

    function test_CrossContractReplayRejected() public {
        // Signed for a DIFFERENT QuestManager deployment.
        QuestManager qm2 = new QuestManager(address(gate), address(reputation), address(achievement), admin);
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig =
            _signFor(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline, block.chainid, address(qm2));
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
    }

    // --- Signer authorization + rotation ---

    function test_UnauthorizedSignerRejected() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(ATTACKER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, attacker));
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_VerifierRotationInvalidatesOldAttestations() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory oldSig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        // Rotate: revoke the old verifier, grant a new one.
        qm.revokeRole(qm.VERIFIER_ROLE(), verifier);
        address newVerifier = vm.addr(NEW_VERIFIER_KEY);
        qm.grantRole(qm.VERIFIER_ROLE(), newVerifier);
        // The old attestation is dead the moment the role is revoked.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, verifier));
        qm.completeQuestWithAttestation(attestedQuest, deadline, oldSig);
        // A fresh attestation from the new verifier works.
        bytes memory newSig = _sign(NEW_VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, newSig);
        assertEq(reputation.points(alice), 100);
    }

    function test_OnlyAdminCanGrantVerifierRole() public {
        // Hoist BOTH role lookups before prank/expectRevert: a contract
        // call between them would consume the prank / the expected revert.
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        bytes32 verifierRole = qm.VERIFIER_ROLE();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, adminRole)
        );
        qm.grantRole(verifierRole, attacker);
    }

    // --- Deadlines ---

    function test_ExpiredAttestationReverts() public {
        uint256 deadline = block.timestamp - 1;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationExpired.selector, deadline, block.timestamp));
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(qm.nonces(alice), 0);
    }

    function test_DeadlineTooFarReverts() public {
        uint256 deadline = block.timestamp + qm.MAX_ATTESTATION_LIFETIME() + 1;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IQuestManager.AttestationDeadlineTooFar.selector,
                deadline,
                block.timestamp + qm.MAX_ATTESTATION_LIFETIME()
            )
        );
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(qm.nonces(alice), 0);
    }

    function test_DeadlineAtMaxLifetimeAccepted() public {
        uint256 deadline = block.timestamp + qm.MAX_ATTESTATION_LIFETIME();
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 100);
    }

    // --- Signature validity ---

    function test_MalleableSignatureRejected() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        // Flip s -> n - s and v -> 27/28 counterpart: the malleable twin of
        // a valid signature. ECDSA.tryRecover must reject it.
        (uint8 v, bytes32 r, bytes32 s) = _split(sig);
        bytes memory malleable = abi.encodePacked(r, bytes32(SECP256K1_N - uint256(s)), v == 27 ? uint8(28) : uint8(27));
        vm.prank(alice);
        // The error carries the offending (flipped) s value.
        vm.expectRevert(
            abi.encodeWithSelector(
                IQuestManager.InvalidAttestationSignature.selector, bytes32(SECP256K1_N - uint256(s))
            )
        );
        qm.completeQuestWithAttestation(attestedQuest, deadline, malleable);
        assertEq(reputation.points(alice), 0);
    }

    function test_EmptySignatureRejected() public {
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(alice);
        // InvalidSignatureLength with the length (0) as the error argument.
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidAttestationSignature.selector, bytes32(uint256(0))));
        qm.completeQuestWithAttestation(attestedQuest, deadline, "");
    }

    function test_ZeroSignatureRejected() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = new bytes(65); // r = s = 0, v = 0
        vm.prank(alice);
        // InvalidSignature: error argument is bytes32(0).
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidAttestationSignature.selector, bytes32(uint256(0))));
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
    }

    function test_ShortSignatureRejected() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = new bytes(10);
        vm.prank(alice);
        // InvalidSignatureLength with the length (10) as the error argument.
        vm.expectRevert(
            abi.encodeWithSelector(IQuestManager.InvalidAttestationSignature.selector, bytes32(uint256(10)))
        );
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
    }

    // --- Interaction with the rest of the completion rules ---

    function test_NonHolderCannotCompleteWithAttestation() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, dave, attestedQuest, qm.nonces(dave), deadline);
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSelector(IAgentGate.NotAgentHolder.selector, dave));
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(dave), 0);
        assertEq(qm.nonces(dave), 0, "failed completion consumed a nonce");
    }

    function test_FailedCompletionDoesNotBurnNonce() public {
        // Capped attested quest (1 completion): alice takes the only slot,
        // then bob's valid attestation fails with QuestFull — and bob's
        // nonce must NOT be consumed by the failed completion.
        vm.prank(creator);
        uint256 capped = qm.createQuest(
            "Capped",
            "one slot only",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            1
        );
        uint256 deadline = block.timestamp + 1 days;
        bytes memory aliceSig = _sign(VERIFIER_KEY, alice, capped, qm.nonces(alice), deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(capped, deadline, aliceSig);
        assertEq(qm.nonces(alice), 1);

        bytes memory bobSig = _sign(VERIFIER_KEY, bob, capped, qm.nonces(bob), deadline);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestFull.selector, capped));
        qm.completeQuestWithAttestation(capped, deadline, bobSig);
        assertEq(qm.nonces(bob), 0, "failed completion consumed a nonce");
    }

    function test_AttestedFarmingBoundedByCooldown() public {
        // Daily attested quest: even with a fresh attestation every time,
        // the cooldown caps awards at one per day.
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig1 = _sign(VERIFIER_KEY, alice, dailyAttestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(dailyAttestedQuest, deadline, sig1);
        assertEq(reputation.points(alice), 10);

        // Fresh attestation, same day: cooldown still blocks it.
        bytes memory sig2 = _sign(VERIFIER_KEY, alice, dailyAttestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IQuestManager.CooldownActive.selector, alice, dailyAttestedQuest, block.timestamp + 1 days
            )
        );
        qm.completeQuestWithAttestation(dailyAttestedQuest, deadline, sig2);
        assertEq(reputation.points(alice), 10);

        // Next day, a fresh attestation works.
        vm.warp(block.timestamp + 1 days);
        uint256 deadline2 = block.timestamp + 1 days;
        bytes memory sig3 = _sign(VERIFIER_KEY, alice, dailyAttestedQuest, qm.nonces(alice), deadline2);
        vm.prank(alice);
        qm.completeQuestWithAttestation(dailyAttestedQuest, deadline2, sig3);
        assertEq(reputation.points(alice), 20);
    }

    function test_AttestedCompletionWhilePausedReverts() public {
        qm.grantRole(qm.PAUSER_ROLE(), admin);
        qm.pause();
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(qm.nonces(alice), 0);
    }

    // --- Fuzz: any in-range deadline works; any wrong nonce fails ---

    function testFuzz_ValidAttestationAlwaysCompletes(uint256 deadlineOffset) public {
        deadlineOffset = bound(deadlineOffset, 0, qm.MAX_ATTESTATION_LIFETIME());
        uint256 deadline = block.timestamp + deadlineOffset;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, qm.nonces(alice), deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 100);
        assertEq(qm.nonces(alice), 1);
    }

    function testFuzz_WrongNonceAlwaysRejected(uint256 wrongNonce) public {
        wrongNonce = bound(wrongNonce, 1, type(uint256).max);
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, wrongNonce, deadline);
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function _split(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
