// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice End-to-end wiring tests with REAL contracts (no stubs):
/// AgentGate -> QuestManager -> Reputation + Achievement, plus the
/// production privilege model: DEFAULT_ADMIN_ROLE held by a
/// TimelockController (2-day minDelay), deployer renounces admin.
contract IntegrationTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;
    TimelockController internal timelock;

    address internal deployer = address(this);
    address internal multisig = makeAddr("multisig");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant TIMELOCK_DELAY = 2 days;
    uint256 internal constant BADGE_ID = 1;

    function setUp() public {
        // --- Deploy the full stack, deployer as temporary admin. ---
        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new Reputation(deployer);
        achievement = new Achievement(deployer);
        qm = new QuestManager(address(gate), address(reputation), address(achievement), deployer);

        // --- Wire roles: QuestManager is the ONLY score source / issuer. ---
        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        // Explicit setup grants (SEC-002): constructors grant admin only.
        achievement.grantRole(achievement.BADGE_MANAGER_ROLE(), deployer);
        achievement.defineBadge(BADGE_ID, "First Quest", "ipfs://badge1");
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);
        // PAUSER_ROLE goes to the multisig directly: pause must be FAST
        // (no timelock delay) in an emergency; unpause stays admin-only
        // (via the timelock) so a compromised pauser cannot resume alone.
        qm.grantRole(qm.PAUSER_ROLE(), multisig);

        // --- Timelock: 2-day delay, multisig proposes + executes. ---
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        // --- Hand admin to the timelock, then the deployer renounces. ---
        qm.grantRole(qm.DEFAULT_ADMIN_ROLE(), address(timelock));
        reputation.grantRole(reputation.DEFAULT_ADMIN_ROLE(), address(timelock));
        achievement.grantRole(achievement.DEFAULT_ADMIN_ROLE(), address(timelock));
        qm.renounceRole(qm.DEFAULT_ADMIN_ROLE(), deployer);
        reputation.renounceRole(reputation.DEFAULT_ADMIN_ROLE(), deployer);
        achievement.renounceRole(achievement.DEFAULT_ADMIN_ROLE(), deployer);
        // SEC-002: also renounce the setup-only operational role — the
        // deployer needed BADGE_MANAGER_ROLE only to define the first badge.
        achievement.renounceRole(achievement.BADGE_MANAGER_ROLE(), deployer);

        mockId.mint(alice);
        mockId.mint(bob);
        vm.warp(1_000_000);
    }

    function _createQuest() internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "First Quest",
            "Complete your first quest",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            BADGE_ID,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    function test_EndToEndCompletionAwardsPointsAndBadge() public {
        uint256 id = _createQuest();
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
        assertEq(reputation.level(alice), 2); // 100 points -> level 2
        assertTrue(achievement.hasBadge(alice, BADGE_ID));
        assertEq(achievement.balanceOf(alice), 1);
        assertEq(achievement.badgeOf(1), BADGE_ID);
        assertEq(achievement.ownerOf(1), alice);
        // Bob is unaffected.
        assertEq(reputation.points(bob), 0);
        assertFalse(achievement.hasBadge(bob, BADGE_ID));
    }

    function test_DeployerLostAdminAfterRenounce() public {
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        bytes32 creatorRole = qm.QUEST_CREATOR_ROLE(); // hoist before expectRevert
        assertFalse(qm.hasRole(adminRole, deployer));
        assertTrue(qm.hasRole(adminRole, address(timelock)));
        // SEC-002 regression: the deployer must hold NO operational role
        // after renouncing admin — constructors grant admin only.
        assertFalse(qm.hasRole(qm.PAUSER_ROLE(), deployer));
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), deployer));
        assertFalse(achievement.hasRole(achievement.BADGE_MANAGER_ROLE(), deployer));
        assertFalse(reputation.hasRole(reputation.SCORE_SOURCE_ROLE(), deployer));
        assertFalse(achievement.hasRole(achievement.ISSUER_ROLE(), deployer));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, deployer, adminRole)
        );
        qm.grantRole(creatorRole, alice);
    }

    function test_TimelockCanGrantRoleAfterDelay() public {
        // Multisig schedules a role grant through the timelock.
        bytes memory payload = abi.encodeWithSelector(IAccessControl.grantRole.selector, qm.QUEST_CREATOR_ROLE(), bob);
        bytes32 salt = bytes32(uint256(1));
        vm.prank(multisig);
        timelock.schedule(address(qm), 0, payload, bytes32(0), salt, TIMELOCK_DELAY);

        // Executing before the delay reverts.
        vm.prank(multisig);
        vm.expectRevert();
        timelock.execute(address(qm), 0, payload, bytes32(0), salt);
        assertFalse(qm.hasRole(qm.QUEST_CREATOR_ROLE(), bob));

        // After the delay, execution succeeds and Bob can create quests.
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(multisig);
        timelock.execute(address(qm), 0, payload, bytes32(0), salt);
        assertTrue(qm.hasRole(qm.QUEST_CREATOR_ROLE(), bob));
        vm.prank(bob);
        uint256 id = qm.createQuest(
            "Bob Quest",
            "created via timelock-granted role",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 7 days,
            0
        );
        assertEq(qm.getQuest(id).creator, bob);
    }

    /// @notice TEMUAN 1: in production the verifier role is granted through
    /// the timelock (2-day delay), like every other admin action — a
    /// compromised deployer key cannot mint itself a verifier role.
    function test_TimelockCanGrantVerifierRoleAfterDelay() public {
        address verifier = makeAddr("verifier");
        bytes memory payload = abi.encodeWithSelector(IAccessControl.grantRole.selector, qm.VERIFIER_ROLE(), verifier);
        bytes32 salt = bytes32(uint256(5));
        vm.prank(multisig);
        timelock.schedule(address(qm), 0, payload, bytes32(0), salt, TIMELOCK_DELAY);
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), verifier));
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(multisig);
        timelock.execute(address(qm), 0, payload, bytes32(0), salt);
        assertTrue(qm.hasRole(qm.VERIFIER_ROLE(), verifier));
    }

    function test_TimelockRejectsShortDelay() public {
        bytes memory payload = abi.encodeWithSelector(IAccessControl.grantRole.selector, qm.QUEST_CREATOR_ROLE(), bob);
        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, 1 days, TIMELOCK_DELAY)
        );
        timelock.schedule(address(qm), 0, payload, bytes32(0), bytes32(uint256(2)), 1 days);
    }

    function test_NonProposerCannotSchedule() public {
        bytes memory payload = abi.encodeWithSelector(IAccessControl.grantRole.selector, qm.QUEST_CREATOR_ROLE(), bob);
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, proposerRole)
        );
        timelock.schedule(address(qm), 0, payload, bytes32(0), bytes32(uint256(3)), TIMELOCK_DELAY);
    }

    function test_EmergencyPauseIsFastUnpauseNeedsTimelock() public {
        uint256 id = _createQuest();
        // Multisig pauses DIRECTLY (PAUSER_ROLE, no timelock delay).
        vm.prank(multisig);
        qm.pause();
        assertTrue(qm.paused());
        vm.prank(alice);
        vm.expectRevert();
        qm.completeQuest(id);

        // Multisig CANNOT unpause directly (admin-only).
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, multisig, adminRole)
        );
        qm.unpause();

        // Unpause goes through the timelock with the 2-day delay.
        bytes memory payload = abi.encodeWithSelector(QuestManager.unpause.selector);
        bytes32 salt = bytes32(uint256(4));
        vm.prank(multisig);
        timelock.schedule(address(qm), 0, payload, bytes32(0), salt, TIMELOCK_DELAY);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(multisig);
        timelock.execute(address(qm), 0, payload, bytes32(0), salt);
        assertFalse(qm.paused());
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
    }
}
