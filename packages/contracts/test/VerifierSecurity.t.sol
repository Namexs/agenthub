// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice FINAL REMEDIATION (Phase 6) — verifier security regression
/// tests for the front-running and attribution gaps the Phase 6 audit
/// checked. The core attestation properties (replay, wrong
/// nonce/account/quest/chain/contract, unauthorized signer, expiry,
/// deadline bounds, malleability, rotation, nonce-not-burned) are
/// covered in Attestation.t.sol; this file covers what it did not:
/// (1) a third party cannot submit someone else's attestation,
/// (2) the verifier itself cannot submit for a user,
/// (3) the deadline boundary (deadline == block.timestamp),
/// (4) AttestationUsed attributes the completion to the signing
/// verifier, (5) nonces are isolated per account.
contract VerifierSecurityTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant VERIFIER_KEY = 0xA11CE5;
    uint256 internal constant VERIFIER2_KEY = 0x5EED;
    address internal verifier;
    address internal verifier2;

    uint256 internal attestedQuest;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        verifier = vm.addr(VERIFIER_KEY);
        verifier2 = vm.addr(VERIFIER2_KEY);

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

        mockId.mint(alice);
        mockId.mint(bob);
        vm.warp(1_000_000);

        vm.prank(creator);
        attestedQuest = qm.createQuest(
            "Post on X",
            "Share AGENTHUB on X",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
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

    function test_FrontRunnerCannotSubmitOthersAttestation() public {
        // The verifier attests Alice's completion; Bob sees the
        // attestation (e.g. in the mempool) and tries to submit it
        // himself. _verifyAttestation binds the account to msg.sender,
        // so the signature recovers a garbage signer with no role.
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, 0, deadline);
        address garbage = ECDSA.recover(_digest(bob, attestedQuest, 0, deadline), sig);
        assertTrue(garbage != verifier, "test setup: garbage signer collided with verifier");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, garbage));
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(bob), 0, "front-runner got the points");
        assertEq(reputation.points(alice), 0, "victim got points from a stolen submission");
        assertEq(qm.nonces(alice), 0, "victim nonce consumed by the attack");
        assertEq(qm.nonces(bob), 0, "attacker nonce consumed");
        // Alice can still use her attestation afterwards.
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 100);
    }

    function test_VerifierCannotSubmitForUser() public {
        // Even the verifier itself cannot complete a quest FOR a user:
        // the attestation is bound to the submitting account.
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, 0, deadline);
        address garbage = ECDSA.recover(_digest(verifier, attestedQuest, 0, deadline), sig);
        vm.prank(verifier);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.UnauthorizedVerifier.selector, garbage));
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
        assertEq(reputation.points(alice), 0);
        assertEq(qm.nonces(alice), 0);
    }

    function test_DeadlineAtCurrentBlockAccepted() public {
        // deadline == block.timestamp is NOT expired (the check is
        // deadline < block.timestamp). Boundary pinned deliberately.
        bytes memory sig = _sign(VERIFIER_KEY, alice, attestedQuest, 0, block.timestamp);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, block.timestamp, sig);
        assertEq(reputation.points(alice), 100);
    }

    function test_AttestationUsedEventAttributesSigner() public {
        // The second verifier attests; the event must name verifier2,
        // not verifier — monitoring can attribute every attested
        // completion to the signer who authorized it.
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _sign(VERIFIER2_KEY, alice, attestedQuest, 0, deadline);
        vm.expectEmit(true, true, true, true, address(qm));
        emit IQuestManager.AttestationUsed(alice, attestedQuest, 0, verifier2);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, sig);
    }

    function test_NoncesAreIsolatedPerAccount() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory aliceSig = _sign(VERIFIER_KEY, alice, attestedQuest, 0, deadline);
        vm.prank(alice);
        qm.completeQuestWithAttestation(attestedQuest, deadline, aliceSig);
        assertEq(qm.nonces(alice), 1);
        assertEq(qm.nonces(bob), 0, "alice completion touched bob nonce");
        // Bob completes the same quest with HIS nonce 0.
        bytes memory bobSig = _sign(VERIFIER_KEY, bob, attestedQuest, 0, deadline);
        vm.prank(bob);
        qm.completeQuestWithAttestation(attestedQuest, deadline, bobSig);
        assertEq(reputation.points(bob), 100);
        assertEq(qm.nonces(bob), 1);
    }
}
