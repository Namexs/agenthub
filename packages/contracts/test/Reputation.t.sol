// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Reputation} from "../src/Reputation.sol";
import {IReputation} from "../src/interfaces/IReputation.sol";

contract ReputationTest is Test {
    Reputation internal reputation;
    address internal admin = makeAddr("admin");
    address internal questManager = makeAddr("questManager");
    address internal alice = makeAddr("alice");

    function setUp() public {
        reputation = new Reputation(admin);
        bytes32 scoreRole = reputation.SCORE_SOURCE_ROLE(); // hoist before prank
        vm.prank(admin);
        reputation.grantRole(scoreRole, questManager);
    }

    function test_InitialStateIsZero() public view {
        assertEq(reputation.points(alice), 0);
        assertEq(reputation.level(alice), 1);
        assertEq(reputation.totalEvents(alice), 0);
    }

    function test_AddPointsIncreasesTotalAndEvents() public {
        vm.prank(questManager);
        reputation.addPoints(alice, 100, 1);
        assertEq(reputation.points(alice), 100);
        assertEq(reputation.totalEvents(alice), 1);
        vm.prank(questManager);
        reputation.addPoints(alice, 50, 2);
        assertEq(reputation.points(alice), 150);
        assertEq(reputation.totalEvents(alice), 2);
    }

    function test_AddPointsEmitsEventWithQuestId() public {
        vm.expectEmit(true, true, false, true, address(reputation));
        emit IReputation.PointsAdded(alice, 7, 100, 100);
        vm.prank(questManager);
        reputation.addPoints(alice, 100, 7);
    }

    function test_AddPointsRequiresScoreSourceRole() public {
        bytes32 role = reputation.SCORE_SOURCE_ROLE();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        reputation.addPoints(alice, 100, 1);
        // Even the admin cannot add points directly — by design.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, role));
        reputation.addPoints(admin, 100, 1);
        assertEq(reputation.points(alice), 0);
        assertEq(reputation.points(admin), 0);
    }

    function test_AddPointsRejectsZeroAccount() public {
        vm.prank(questManager);
        vm.expectRevert(IReputation.ZeroAddress.selector);
        reputation.addPoints(address(0), 100, 1);
    }

    function test_AddPointsRejectsZeroPoints() public {
        vm.prank(questManager);
        vm.expectRevert(IReputation.InvalidPoints.selector);
        reputation.addPoints(alice, 0, 1);
    }

    function test_AddPointsRejectsAboveCap() public {
        uint256 tooMuch = reputation.MAX_POINTS_PER_EVENT() + 1;
        vm.prank(questManager);
        vm.expectRevert(IReputation.InvalidPoints.selector);
        reputation.addPoints(alice, tooMuch, 1);
    }

    function test_AddPointsAcceptsExactlyCap() public {
        uint256 cap = reputation.MAX_POINTS_PER_EVENT();
        vm.prank(questManager);
        reputation.addPoints(alice, cap, 1);
        assertEq(reputation.points(alice), cap);
    }

    function test_LevelsFollowThresholds() public {
        // Thresholds: L1=0, L2=100, L3=300, L4=700, L5=1500.
        assertEq(reputation.level(alice), 1);
        vm.startPrank(questManager);
        reputation.addPoints(alice, 99, 1);
        assertEq(reputation.level(alice), 1);
        reputation.addPoints(alice, 1, 1);
        assertEq(reputation.level(alice), 2);
        reputation.addPoints(alice, 200, 1);
        assertEq(reputation.level(alice), 3);
        reputation.addPoints(alice, 400, 1);
        assertEq(reputation.level(alice), 4);
        reputation.addPoints(alice, 800, 1);
        assertEq(reputation.level(alice), 5);
        vm.stopPrank();
    }

    function test_LevelThresholdGetter() public view {
        assertEq(reputation.levelThreshold(1), 0);
        assertEq(reputation.levelThreshold(2), 100);
        assertEq(reputation.levelThreshold(3), 300);
        assertEq(reputation.levelThreshold(4), 700);
        assertEq(reputation.levelThreshold(5), 1500);
    }

    function test_LevelThresholdRejectsInvalidLevel() public {
        vm.expectRevert(abi.encodeWithSelector(IReputation.InvalidLevel.selector, 0));
        reputation.levelThreshold(0);
        vm.expectRevert(abi.encodeWithSelector(IReputation.InvalidLevel.selector, 6));
        reputation.levelThreshold(6);
    }

    function test_PauseBlocksAddPointsButNotReads() public {
        vm.prank(admin);
        reputation.pause();
        vm.prank(questManager);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        reputation.addPoints(alice, 100, 1);
        assertEq(reputation.points(alice), 0);
        vm.prank(admin);
        reputation.unpause();
        vm.prank(questManager);
        reputation.addPoints(alice, 100, 1);
        assertEq(reputation.points(alice), 100);
    }

    function test_ConstructorRejectsZeroAdmin() public {
        vm.expectRevert(IReputation.ZeroAddress.selector);
        new Reputation(address(0));
    }

    function test_RevokingScoreSourceStopsPoints() public {
        bytes32 role = reputation.SCORE_SOURCE_ROLE(); // hoist before prank
        vm.prank(admin);
        reputation.revokeRole(role, questManager);
        vm.prank(questManager);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, questManager, role)
        );
        reputation.addPoints(alice, 100, 1);
    }

    function testFuzz_AddPointsAccumulates(uint256 a, uint256 b) public {
        a = bound(a, 1, reputation.MAX_POINTS_PER_EVENT());
        b = bound(b, 1, reputation.MAX_POINTS_PER_EVENT());
        vm.startPrank(questManager);
        reputation.addPoints(alice, a, 1);
        reputation.addPoints(alice, b, 2);
        vm.stopPrank();
        assertEq(reputation.points(alice), a + b);
        assertEq(reputation.totalEvents(alice), 2);
    }
}
