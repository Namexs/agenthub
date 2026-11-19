// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Stateful handler: random actors complete random quests and warp
/// time. Ghost state tracks the expected outcome of every successful call so
/// the invariants can prove the contracts never diverge from it.
contract InvariantHandler is Test {
    QuestManager public qm;
    address[] public actors;
    uint256[] public questIds;
    mapping(uint256 => uint256) public questReward;
    mapping(uint256 => uint256) public questBadge;
    mapping(uint256 => uint256) public questCap;

    mapping(address => uint256) public expectedPoints;
    mapping(address => uint256) public expectedEvents;
    mapping(address => uint256) public expectedBadgeCount;
    mapping(address => mapping(uint256 => bool)) public badgeHeld;
    mapping(uint256 => uint256) public expectedCompletions;

    constructor(
        QuestManager qm_,
        address[] memory actors_,
        uint256[] memory questIds_,
        uint256[] memory rewards_,
        uint256[] memory badges_,
        uint256[] memory caps_
    ) {
        qm = qm_;
        actors = actors_;
        questIds = questIds_;
        for (uint256 i = 0; i < questIds_.length; i++) {
            questReward[questIds_[i]] = rewards_[i];
            questBadge[questIds_[i]] = badges_[i];
            questCap[questIds_[i]] = caps_[i];
        }
    }

    /// @notice Random actor attempts a random quest. Reverts are legitimate
    /// (cooldown, duplicate, non-holder, cap) — ghosts update only on success.
    function completeQuest(uint256 actorSeed, uint256 questSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 questId = questIds[questSeed % questIds.length];
        vm.prank(actor);
        try qm.completeQuest(questId) {
            expectedPoints[actor] += questReward[questId];
            expectedEvents[actor] += 1;
            expectedCompletions[questId] += 1;
            uint256 badgeId = questBadge[questId];
            if (badgeId != 0 && !badgeHeld[actor][badgeId]) {
                badgeHeld[actor][badgeId] = true;
                expectedBadgeCount[actor] += 1;
            }
        } catch {}
    }

    /// @notice Advance time by 0..3 days (quests live 90 days, so the window
    /// stays open across a run of depth-15 calls).
    function warpTime(uint256 seconds_) external {
        vm.warp(block.timestamp + bound(seconds_, 0, 3 days));
    }
}

contract InvariantTest is StdInvariant, Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;
    InvariantHandler internal handler;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave"); // NO Agent ID — the Sybil control

    address[] internal actors;
    uint256[] internal questIds;

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

        mockId.mint(alice);
        mockId.mint(bob);
        mockId.mint(carol);
        // dave deliberately gets NO Agent ID.
        vm.warp(1_000_000);

        // Four quests: one-time+badge, daily, weekly, capped one-time.
        vm.startPrank(creator);
        questIds.push(
            qm.createQuest(
                "OneTime", "one-time + badge", IQuestManager.QuestType.OneTime, 100, BADGE_ID,
                block.timestamp, block.timestamp + 90 days, 0
            )
        );
        questIds.push(
            qm.createQuest(
                "Daily", "daily", IQuestManager.QuestType.DailyCheckIn, 10, 0,
                block.timestamp, block.timestamp + 90 days, 0
            )
        );
        questIds.push(
            qm.createQuest(
                "Weekly", "weekly", IQuestManager.QuestType.Weekly, 70, 0,
                block.timestamp, block.timestamp + 90 days, 0
            )
        );
        questIds.push(
            qm.createQuest(
                "Capped", "capped at 2", IQuestManager.QuestType.OneTime, 50, 0,
                block.timestamp, block.timestamp + 90 days, 2
            )
        );
        vm.stopPrank();

        actors = [alice, bob, carol, dave];
        uint256[] memory rewards = new uint256[](4);
        rewards[0] = 100;
        rewards[1] = 10;
        rewards[2] = 70;
        rewards[3] = 50;
        uint256[] memory badges = new uint256[](4);
        badges[0] = BADGE_ID;
        uint256[] memory caps = new uint256[](4);
        caps[3] = 2;

        handler = new InvariantHandler(qm, actors, questIds, rewards, badges, caps);
        targetContract(address(handler));
    }

    /// @notice Sanity check that the handler actually drives successful
    /// completions — without this, the invariants could pass vacuously.
    function test_HandlerActuallyCompletesQuests() public {
        handler.completeQuest(0, 0); // alice, one-time + badge
        assertEq(handler.expectedPoints(alice), 100);
        assertEq(reputation.points(alice), 100);
        assertEq(handler.expectedBadgeCount(alice), 1);
        handler.completeQuest(0, 1); // alice, daily
        assertEq(handler.expectedPoints(alice), 110);
        handler.completeQuest(3, 0); // dave (no Agent ID) -> fails internally
        assertEq(handler.expectedPoints(dave), 0);
        assertEq(reputation.points(dave), 0);
        handler.warpTime(2 days);
        handler.completeQuest(0, 1); // alice, daily again after warp
        assertEq(handler.expectedPoints(alice), 120);
    }

    /// @notice Points in Reputation always equal the sum of rewards of
    /// successful completions — no phantom points, no lost points.
    function invariant_PointsMatchGhost() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(
                reputation.points(actors[i]),
                handler.expectedPoints(actors[i]),
                "points diverged from ghost"
            );
        }
    }

    /// @notice Event counts match successful completions exactly.
    function invariant_EventsMatchGhost() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(
                reputation.totalEvents(actors[i]),
                handler.expectedEvents(actors[i]),
                "events diverged from ghost"
            );
        }
    }

    /// @notice Completion counters match, and capped quests never exceed cap.
    function invariant_CompletionsMatchAndRespectCap() public view {
        for (uint256 i = 0; i < questIds.length; i++) {
            uint256 id = questIds[i];
            assertEq(
                qm.getQuest(id).completions,
                handler.expectedCompletions(id),
                "completions diverged from ghost"
            );
            uint256 cap = handler.questCap(id);
            if (cap > 0) {
                assertLe(qm.getQuest(id).completions, cap, "cap exceeded");
            }
        }
    }

    /// @notice Badge balances match the ghost: one token per distinct badge.
    function invariant_BadgesMatchGhost() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(
                achievement.balanceOf(actors[i]),
                handler.expectedBadgeCount(actors[i]),
                "badge balance diverged from ghost"
            );
            assertEq(
                achievement.hasBadge(actors[i], BADGE_ID),
                handler.badgeHeld(actors[i], BADGE_ID),
                "badge flag diverged from ghost"
            );
        }
    }

    /// @notice The non-holder NEVER earns points or badges, no matter how
    /// many completions are attempted on their behalf.
    function invariant_NonHolderEarnsNothing() public view {
        assertEq(reputation.points(dave), 0, "non-holder gained points");
        assertEq(reputation.totalEvents(dave), 0, "non-holder gained events");
        assertEq(achievement.balanceOf(dave), 0, "non-holder gained a badge");
    }
}
