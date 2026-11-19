// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Economic attack simulations: cooldown farming, reward-cap
/// circumvention, Sybil attempts, and total-emission bounds. Every test
/// proves the economic invariant holds under adversarial behavior.
contract EconomicAttackTest is Test {
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

    function setUp() public {
        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new Reputation(admin);
        achievement = new Achievement(admin);
        qm = new QuestManager(address(gate), address(reputation), address(achievement), admin);

        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);

        mockId.mint(alice);
        mockId.mint(bob);
        mockId.mint(carol);
        vm.warp(1_000_000);
    }

    function _createQuest(IQuestManager.QuestType questType, uint256 reward, uint256 maxCompletions, uint256 window)
        internal
        returns (uint256)
    {
        vm.prank(creator);
        return qm.createQuest(
            "Q",
            "economic target",
            questType,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            reward,
            0,
            block.timestamp,
            block.timestamp + window,
            maxCompletions,
            1
        );
    }

    /// @dev PHASE 6 (R-010): the try/catch attempt lives in its own
    /// function so the farming loops below stay shallow enough for the
    /// via-IR code generator (an inlined try/catch inside the loop hit
    /// "stack too deep" under via-IR; see foundry.toml). Behavior is
    /// identical: one pranked completion attempt, true on success.
    function _tryComplete(address who, uint256 id) internal returns (bool) {
        vm.prank(who);
        try qm.completeQuest(id) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice ATTACK: hammer a daily quest every hour for 30 days.
    /// EXPECTED: exactly 30 awards (one per day), never more — the
    /// cooldown caps farming at reward * days.
    function test_CooldownFarmingBoundedToOnePerDay() public {
        uint256 id = _createQuest(IQuestManager.QuestType.DailyCheckIn, 10, 0, 40 days);
        uint256 successes = 0;
        for (uint256 i = 0; i < 24 * 30; i++) {
            if (_tryComplete(alice, id)) {
                successes++;
            }
            // vm.getBlockTimestamp(), NOT block.timestamp: under via-IR
            // the Yul optimizer hoists block.timestamp out of the loop
            // (it cannot see that vm.warp mutates it), so every
            // iteration would warp to the same time and the cooldown
            // would never lapse. The cheatcode call is not hoisted.
            vm.warp(vm.getBlockTimestamp() + 1 hours);
        }
        assertEq(successes, 30, "daily quest awarded more than once per day");
        assertEq(reputation.points(alice), 300, "points exceed cooldown bound");
    }

    /// @notice ATTACK: same farming against a weekly quest for 28 days.
    /// EXPECTED: exactly 4 awards.
    function test_WeeklyFarmingBoundedToOnePerWeek() public {
        uint256 id = _createQuest(IQuestManager.QuestType.Weekly, 70, 0, 40 days);
        uint256 successes = 0;
        for (uint256 i = 0; i < 24 * 28; i++) {
            if (_tryComplete(alice, id)) {
                successes++;
            }
            // vm.getBlockTimestamp(), NOT block.timestamp: under via-IR
            // the Yul optimizer hoists block.timestamp out of the loop
            // (it cannot see that vm.warp mutates it), so every
            // iteration would warp to the same time and the cooldown
            // would never lapse. The cheatcode call is not hoisted.
            vm.warp(vm.getBlockTimestamp() + 1 hours);
        }
        assertEq(successes, 4, "weekly quest awarded more than once per week");
        assertEq(reputation.points(alice), 280);
    }

    /// @notice Total emission of a capped quest is bounded by cap * reward,
    /// no matter how many holders try to complete it.
    function test_CappedQuestTotalEmissionBounded() public {
        uint256 id = _createQuest(IQuestManager.QuestType.OneTime, 50, 2, 30 days);
        vm.prank(alice);
        qm.completeQuest(id);
        vm.prank(bob);
        qm.completeQuest(id);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestFull.selector, id));
        qm.completeQuest(id);
        uint256 total = reputation.points(alice) + reputation.points(bob) + reputation.points(carol);
        assertEq(total, 100, "emission exceeded cap * reward");
    }

    /// @notice A quest at the maximum reward cannot mint more than
    /// MAX_REWARD_POINTS per completion, per holder.
    function test_MaxRewardQuestEmissionBounded() public {
        uint256 cap = qm.MAX_REWARD_POINTS();
        uint256 id = _createQuest(IQuestManager.QuestType.OneTime, cap, 0, 30 days);
        vm.prank(alice);
        qm.completeQuest(id);
        vm.prank(bob);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), cap);
        assertEq(reputation.points(bob), cap);
        assertEq(reputation.points(alice) + reputation.points(bob), 2 * cap);
    }

    /// @notice ATTACK: 10 Sybil addresses with NO Agent ID try to farm.
    /// EXPECTED: zero points across all of them.
    /// @dev PHASE 6 (R-010): the attempts and the points assertions run
    /// in TWO loops on purpose — one loop holding prank + expectRevert
    /// + call + assertEq together hit "stack too deep" under the
    /// via-IR code generator (see foundry.toml). The same 10 attempts
    /// and the same 10 zero-points assertions run; only the order
    /// changed (assertions after the attempts, per address).
    function test_SybilWithoutAgentIdsEarnsNothing() public {
        uint256 id = _createQuest(IQuestManager.QuestType.OneTime, 100, 0, 30 days);
        for (uint256 i = 0; i < 10; i++) {
            address sybil = address(uint160(0x5000 + i));
            vm.prank(sybil);
            vm.expectRevert();
            qm.completeQuest(id);
        }
        for (uint256 i = 0; i < 10; i++) {
            address sybil = address(uint160(0x5000 + i));
            assertEq(reputation.points(sybil), 0);
        }
        assertEq(qm.getQuest(id).completions, 0);
    }

    /// @notice A creator cannot create a quest with a reward above the cap,
    /// so no single quest can inflate the economy.
    function test_CreatorCannotExceedRewardCap() public {
        uint256 tooMuch = qm.MAX_REWARD_POINTS() + 1;
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            "Inflation",
            "too big",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            tooMuch,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            1
        );
    }
}
