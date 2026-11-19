// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Exhaustive role matrix: every privileged function is attempted by
/// an unauthorized account (must revert) and by the rightful role holder
/// (must succeed). Also proves the admin has NO implicit powers beyond
/// DEFAULT_ADMIN_ROLE (no score minting, no badge issuance).
contract AccessControlTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal pauser = makeAddr("pauser");
    address internal stranger = makeAddr("stranger");
    address internal alice = makeAddr("alice");

    uint256 internal constant BADGE_ID = 1;

    function setUp() public {
        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new Reputation(admin);
        achievement = new Achievement(admin);
        qm = new QuestManager(address(gate), address(reputation), address(achievement), admin);

        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        // Explicit setup grant (SEC-002): constructors grant admin only.
        achievement.grantRole(achievement.BADGE_MANAGER_ROLE(), admin);
        achievement.defineBadge(BADGE_ID, "First Quest", "ipfs://badge1");
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);
        qm.grantRole(qm.PAUSER_ROLE(), pauser);
        mockId.mint(alice);
        vm.warp(1_000_000);
    }

    function _expectUnauthorized(address account, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role));
    }

    // --- QuestManager ---

    function test_CreateQuestRoleMatrix() public {
        bytes32 role = qm.QUEST_CREATOR_ROLE();
        vm.prank(stranger);
        _expectUnauthorized(stranger, role);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0,
            1
        );
        // Admin WITHOUT the creator role also fails.
        vm.prank(admin);
        _expectUnauthorized(admin, role);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0,
            1
        );
        // Creator succeeds.
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0,
            1
        );
        assertEq(qm.getQuest(id).creator, creator);
    }

    function test_DeactivateQuestRoleMatrix() public {
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0,
            1
        );
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.NotQuestCreatorOrAdmin.selector, stranger, id));
        qm.deactivateQuest(id);
        // Creator succeeds on their own quest.
        vm.prank(creator);
        qm.deactivateQuest(id);
        assertFalse(qm.getQuest(id).active);
    }

    function test_PauseUnpauseRoleMatrix() public {
        bytes32 pauserRole = qm.PAUSER_ROLE();
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        // Stranger cannot pause.
        vm.prank(stranger);
        _expectUnauthorized(stranger, pauserRole);
        qm.pause();
        // Admin (without PAUSER_ROLE) cannot pause either.
        vm.prank(admin);
        _expectUnauthorized(admin, pauserRole);
        qm.pause();
        // Pauser can pause.
        vm.prank(pauser);
        qm.pause();
        assertTrue(qm.paused());
        // Pauser cannot unpause.
        vm.prank(pauser);
        _expectUnauthorized(pauser, adminRole);
        qm.unpause();
        // Admin can unpause.
        vm.prank(admin);
        qm.unpause();
        assertFalse(qm.paused());
    }

    // --- Reputation ---

    function test_AddPointsRoleMatrix() public {
        bytes32 role = reputation.SCORE_SOURCE_ROLE();
        // Stranger cannot add points.
        vm.prank(stranger);
        _expectUnauthorized(stranger, role);
        reputation.addPoints(alice, 10, 1);
        // Admin cannot add points (no implicit mint power).
        vm.prank(admin);
        _expectUnauthorized(admin, role);
        reputation.addPoints(alice, 10, 1);
        // Only QuestManager (score source) can.
        vm.prank(address(qm));
        reputation.addPoints(alice, 10, 1);
        assertEq(reputation.points(alice), 10);
    }

    function test_ReputationPauseRoleMatrix() public {
        bytes32 adminRole = reputation.DEFAULT_ADMIN_ROLE();
        vm.prank(stranger);
        _expectUnauthorized(stranger, adminRole);
        reputation.pause();
        vm.prank(admin);
        reputation.pause();
        assertTrue(reputation.paused());
        vm.prank(admin);
        reputation.unpause();
        assertFalse(reputation.paused());
    }

    // --- Achievement ---

    function test_DefineBadgeRoleMatrix() public {
        bytes32 role = achievement.BADGE_MANAGER_ROLE();
        vm.prank(stranger);
        _expectUnauthorized(stranger, role);
        achievement.defineBadge(2, "X", "ipfs://x");
        vm.prank(admin); // admin was explicitly granted BADGE_MANAGER_ROLE in setUp
        achievement.defineBadge(2, "X", "ipfs://x");
        assertTrue(achievement.isBadgeDefined(2));
    }

    function test_IssueRoleMatrix() public {
        bytes32 role = achievement.ISSUER_ROLE();
        vm.prank(stranger);
        _expectUnauthorized(stranger, role);
        achievement.issue(alice, BADGE_ID);
        // Admin cannot issue directly (no implicit mint power).
        vm.prank(admin);
        _expectUnauthorized(admin, role);
        achievement.issue(alice, BADGE_ID);
        // Only QuestManager (issuer) can.
        vm.prank(address(qm));
        achievement.issue(alice, BADGE_ID);
        assertTrue(achievement.hasBadge(alice, BADGE_ID));
    }

    function test_AchievementPauseRoleMatrix() public {
        bytes32 adminRole = achievement.DEFAULT_ADMIN_ROLE();
        vm.prank(stranger);
        _expectUnauthorized(stranger, adminRole);
        achievement.pause();
        vm.prank(admin);
        achievement.pause();
        assertTrue(achievement.paused());
    }

    // --- Role administration ---

    function test_GrantRoleRequiresAdmin() public {
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        bytes32 creatorRole = qm.QUEST_CREATOR_ROLE();
        vm.prank(stranger);
        _expectUnauthorized(stranger, adminRole);
        qm.grantRole(creatorRole, stranger);
        // Even a role holder cannot grant their own role to others.
        vm.prank(creator);
        _expectUnauthorized(creator, adminRole);
        qm.grantRole(creatorRole, stranger);
        assertFalse(qm.hasRole(creatorRole, stranger));
        // Admin can grant and revoke.
        qm.grantRole(creatorRole, stranger);
        assertTrue(qm.hasRole(creatorRole, stranger));
        qm.revokeRole(creatorRole, stranger);
        assertFalse(qm.hasRole(creatorRole, stranger));
    }

    // --- TEMUAN 1: VERIFIER_ROLE ---

    function test_VerifierRoleMatrix() public {
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        bytes32 verifierRole = qm.VERIFIER_ROLE();
        address verifier = makeAddr("verifier");
        // Stranger cannot grant the verifier role.
        vm.prank(stranger);
        _expectUnauthorized(stranger, adminRole);
        qm.grantRole(verifierRole, verifier);
        // A creator cannot grant it either (only admin).
        vm.prank(creator);
        _expectUnauthorized(creator, adminRole);
        qm.grantRole(verifierRole, verifier);
        assertFalse(qm.hasRole(verifierRole, verifier));
        // Admin grants and revokes.
        qm.grantRole(verifierRole, verifier);
        assertTrue(qm.hasRole(verifierRole, verifier));
        // A verifier holds NO other powers: cannot create quests...
        // (Hoist the role lookups: an external call after prank would
        // consume the prank before the target call.)
        bytes32 creatorRole = qm.QUEST_CREATOR_ROLE();
        bytes32 pauserRole = qm.PAUSER_ROLE();
        vm.prank(verifier);
        _expectUnauthorized(verifier, creatorRole);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0,
            1
        );
        // ...and cannot pause.
        vm.prank(verifier);
        _expectUnauthorized(verifier, pauserRole);
        qm.pause();
        // Admin revokes (rotation).
        qm.revokeRole(verifierRole, verifier);
        assertFalse(qm.hasRole(verifierRole, verifier));
    }

    function test_RenounceRoleIsIrreversibleForCaller() public {
        bytes32 creatorRole = qm.QUEST_CREATOR_ROLE();
        vm.prank(creator);
        qm.renounceRole(creatorRole, creator);
        assertFalse(qm.hasRole(creatorRole, creator));
        vm.prank(creator);
        _expectUnauthorized(creator, creatorRole);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0,
            1
        );
    }
}
