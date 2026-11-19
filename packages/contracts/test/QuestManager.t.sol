// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {IReputation} from "../src/interfaces/IReputation.sol";
import {IAchievement} from "../src/interfaces/IAchievement.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Minimal IReputation stub: records addPoints calls.
contract StubReputation is IReputation {
    mapping(address => uint256) public points;
    mapping(address => uint256) public totalEvents;
    uint256 public addPointsCalls;

    function level(address) external pure returns (uint8) {
        return 1;
    }

    function levelThreshold(uint8) external pure returns (uint256) {
        return 0;
    }

    function addPoints(address account, uint256 pointsAmount, uint256) external {
        points[account] += pointsAmount;
        totalEvents[account] += 1;
        addPointsCalls += 1;
    }
}

/// @notice Minimal IAchievement stub: records defineBadge/issue calls.
contract StubAchievement is IAchievement {
    mapping(uint256 => bool) public defined;
    mapping(address => mapping(uint256 => bool)) public badges;
    mapping(uint256 => uint256) public tokenBadge;
    uint256 public issueCalls;
    uint256 private _nextTokenId = 1;

    function defineBadge(uint256 badgeId, string calldata, string calldata) external {
        defined[badgeId] = true;
    }

    function issue(address account, uint256 badgeId) external returns (uint256 tokenId) {
        require(defined[badgeId], "badge not defined");
        require(!badges[account][badgeId], "already has badge");
        tokenId = _nextTokenId++;
        badges[account][badgeId] = true;
        tokenBadge[tokenId] = badgeId;
        issueCalls += 1;
    }

    function hasBadge(address account, uint256 badgeId) external view returns (bool) {
        return badges[account][badgeId];
    }

    function badgeOf(uint256 tokenId) external view returns (uint256) {
        return tokenBadge[tokenId];
    }

    function isBadgeDefined(uint256 badgeId) external view returns (bool) {
        return defined[badgeId];
    }
}

contract QuestManagerTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    StubReputation internal reputation;
    StubAchievement internal achievement;
    QuestManager internal qm;

    address internal admin = makeAddr("admin");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant BADGE_ID = 1;

    function setUp() public {
        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new StubReputation();
        achievement = new StubAchievement();
        qm = new QuestManager(address(gate), address(reputation), address(achievement), admin);
        achievement.defineBadge(BADGE_ID, "First Quest", "ipfs://badge1");

        vm.startPrank(admin);
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);
        // Explicit setup grant (SEC-002): the constructor no longer grants
        // PAUSER_ROLE — the admin holds it here only for the pause tests.
        qm.grantRole(qm.PAUSER_ROLE(), admin);
        vm.stopPrank();

        mockId.mint(alice);
        mockId.mint(bob);
        vm.warp(1_000_000); // avoid timestamp-1 edge cases
    }

    function _createOneTime(uint256 reward, uint256 badgeId, uint256 maxCompletions) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "First Quest",
            "Complete your first quest",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            reward,
            badgeId,
            block.timestamp,
            block.timestamp + 30 days,
            maxCompletions
        );
    }

    function _createDaily(uint256 reward) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Daily Check-in",
            "Check in every day",
            IQuestManager.QuestType.DailyCheckIn,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            reward,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    function _createWeekly(uint256 reward) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Weekly Quest",
            "Check in every week",
            IQuestManager.QuestType.Weekly,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            reward,
            0,
            block.timestamp,
            block.timestamp + 90 days,
            0
        );
    }

    // --- createQuest ---

    function test_CreateQuestStoresAllFields() public {
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            BADGE_ID,
            1_000_000,
            2_000_000,
            10
        );
        assertEq(id, 1);
        IQuestManager.Quest memory q = qm.getQuest(id);
        assertEq(q.id, 1);
        assertEq(q.creator, creator);
        assertEq(q.title, "T");
        assertEq(q.rewardPoints, 100);
        assertEq(q.badgeId, BADGE_ID);
        assertEq(q.maxCompletions, 10);
        assertEq(q.completions, 0);
        assertTrue(q.active);
        // TEMUAN 1: the validation kind is stored and readable on-chain.
        assertTrue(q.validationKind == IQuestManager.ValidationKind.CheckIn);
        assertEq(q.validator, address(0));
        assertEq(qm.questCount(), 1);
    }

    function test_CreateQuestRequiresCreatorRole() public {
        // Hoist the role lookup BEFORE prank/expectRevert: a contract call
        // between them would consume the prank / the expected revert.
        bytes32 role = qm.QUEST_CREATOR_ROLE();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsEmptyTitle() public {
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            "",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsOversizedTitle() public {
        string memory longTitle = new string(129);
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            longTitle,
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsOversizedDescription() public {
        string memory longDesc = new string(1025);
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            "T",
            longDesc,
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsZeroReward() public {
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            0,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsRewardAboveCap() public {
        uint256 tooMuch = qm.MAX_REWARD_POINTS() + 1; // hoist: view call first
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            tooMuch,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsBadWindow() public {
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp + 2 days,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsEndedQuest() public {
        vm.prank(creator);
        vm.expectRevert(IQuestManager.InvalidQuestParams.selector);
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp - 2 days,
            block.timestamp - 1 days,
            0
        );
    }

    function test_CreateQuestRejectsUndefinedBadge() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IAchievement.BadgeNotDefined.selector, 999));
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            999,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    // --- completeQuest: happy path ---

    function test_CompleteOneTimeAwardsPointsAndBadge() public {
        uint256 id = _createOneTime(100, BADGE_ID, 0);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
        assertEq(reputation.totalEvents(alice), 1);
        assertTrue(achievement.hasBadge(alice, BADGE_ID));
        assertTrue(qm.hasCompleted(alice, id));
        assertEq(qm.getQuest(id).completions, 1);
    }

    function test_CompleteQuestRequiresAgentId() public {
        address stranger = makeAddr("stranger");
        uint256 id = _createOneTime(100, 0, 0);
        vm.prank(stranger);
        vm.expectRevert();
        qm.completeQuest(id);
        assertEq(reputation.points(stranger), 0);
    }

    function test_CompleteNonexistentQuestReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotFound.selector, 999));
        qm.completeQuest(999);
    }

    function test_DuplicateOneTimeReverts() public {
        uint256 id = _createOneTime(100, 0, 0);
        vm.prank(alice);
        qm.completeQuest(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AlreadyCompleted.selector, alice, id));
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100); // no double award
    }

    function test_CommunityQuestIsOneTimePerAccount() public {
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "Community",
            "Join the community",
            IQuestManager.QuestType.Community,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            50,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
        vm.prank(alice);
        qm.completeQuest(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AlreadyCompleted.selector, alice, id));
        qm.completeQuest(id);
        // Another holder can still complete it.
        vm.prank(bob);
        qm.completeQuest(id);
        assertEq(reputation.points(bob), 50);
    }

    // --- Cooldowns ---

    function test_DailyCooldownEnforced() public {
        uint256 id = _createDaily(10);
        vm.prank(alice);
        qm.completeQuest(id);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IQuestManager.CooldownActive.selector, alice, id, block.timestamp + 1 days)
        );
        qm.completeQuest(id);
        assertEq(qm.nextCompletionAt(alice, id), block.timestamp + 1 days);
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 20);
    }

    function test_WeeklyCooldownEnforced() public {
        uint256 id = _createWeekly(70);
        vm.prank(alice);
        qm.completeQuest(id);
        vm.warp(block.timestamp + 6 days);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IQuestManager.CooldownActive.selector, alice, id, block.timestamp + 1 days)
        );
        qm.completeQuest(id);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 140);
    }

    function test_NextCompletionAtForFreshUserIsZero() public {
        uint256 id = _createDaily(10);
        assertEq(qm.nextCompletionAt(alice, id), 0);
    }

    function test_NextCompletionAtForCompletedOneTimeIsMax() public {
        uint256 id = _createOneTime(100, 0, 0);
        assertEq(qm.nextCompletionAt(alice, id), 0);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(qm.nextCompletionAt(alice, id), type(uint256).max);
    }

    // --- Caps, windows, deactivation, pause ---

    function test_MaxCompletionsCapEnforced() public {
        uint256 id = _createOneTime(100, 0, 1);
        vm.prank(alice);
        qm.completeQuest(id);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestFull.selector, id));
        qm.completeQuest(id);
    }

    function test_QuestNotStartedReverts() public {
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "Future",
            "Starts later",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            0
        );
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotStarted.selector, id));
        qm.completeQuest(id);
    }

    function test_QuestEndedReverts() public {
        uint256 id = _createOneTime(100, 0, 0);
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestEnded.selector, id));
        qm.completeQuest(id);
    }

    function test_DeactivatedQuestCannotComplete() public {
        uint256 id = _createOneTime(100, 0, 0);
        vm.prank(creator);
        qm.deactivateQuest(id);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotActive.selector, id));
        qm.completeQuest(id);
    }

    function test_DeactivateByCreatorOrAdminOnly() public {
        uint256 id = _createOneTime(100, 0, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.NotQuestCreatorOrAdmin.selector, alice, id));
        qm.deactivateQuest(id);
        vm.prank(admin);
        qm.deactivateQuest(id);
        assertFalse(qm.getQuest(id).active);
    }

    function test_PauseBlocksCompletionButNotReads() public {
        uint256 id = _createOneTime(100, 0, 0);
        vm.prank(admin);
        qm.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        qm.completeQuest(id);
        // Reads keep working while paused.
        assertEq(qm.getQuest(id).id, id);
        assertEq(qm.questCount(), 1);
        vm.prank(admin);
        qm.unpause();
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
    }

    function test_OnlyPauserCanPauseAndOnlyAdminCanUnpause() public {
        bytes32 pauserRole = qm.PAUSER_ROLE(); // hoist before prank
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pauserRole)
        );
        qm.pause();
        vm.prank(admin);
        qm.pause();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, creator, 0x00));
        qm.unpause();
    }

    // --- Badge edge cases ---

    function test_BadgeAlreadyHeldIsSkippedNotReverted() public {
        // Alice already holds the badge (issued directly on the stub).
        achievement.issue(alice, BADGE_ID);
        uint256 callsBefore = achievement.issueCalls();
        uint256 id = _createOneTime(100, BADGE_ID, 0);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
        assertEq(achievement.issueCalls(), callsBefore); // no second issuance
    }

    function test_QuestCompletedEventCarriesBadgeTokenId() public {
        // SEC-003 regression: the minted badge token id must be visible in
        // the completion event (Slither unused-return).
        uint256 id = _createOneTime(100, BADGE_ID, 0);
        vm.expectEmit(true, true, false, true, address(qm));
        emit IQuestManager.QuestCompleted(id, alice, 100, 1);
        vm.prank(alice);
        qm.completeQuest(id);
    }

    function test_QuestCompletedEventHasZeroTokenIdWithoutBadge() public {
        uint256 id = _createOneTime(100, 0, 0);
        vm.expectEmit(true, true, false, true, address(qm));
        emit IQuestManager.QuestCompleted(id, alice, 100, 0);
        vm.prank(alice);
        qm.completeQuest(id);
    }

    function test_GetQuestRevertsForUnknownId() public {
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotFound.selector, 42));
        qm.getQuest(42);
    }

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(IQuestManager.ZeroAddress.selector);
        new QuestManager(address(0), address(reputation), address(achievement), admin);
    }

    // --- TEMUAN 3: dependency validation ---

    function test_ConstructorRejectsEoaDependencies() public {
        address eoa = makeAddr("eoa");
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.NoCodeAtDependency.selector, eoa));
        new QuestManager(eoa, address(reputation), address(achievement), admin);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.NoCodeAtDependency.selector, eoa));
        new QuestManager(address(gate), eoa, address(achievement), admin);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.NoCodeAtDependency.selector, eoa));
        new QuestManager(address(gate), address(reputation), eoa, admin);
    }

    // --- TEMUAN 1: validation-kind rules at creation ---

    function test_CreateQuestRejectsOnChainWithoutValidator() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidValidator.selector, address(0)));
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.OnChain,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsOnChainWithEoaValidator() public {
        address eoa = makeAddr("eoa-validator");
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidValidator.selector, eoa));
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.OnChain,
            eoa,
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsValidatorForCheckIn() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidValidator.selector, address(mockId)));
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(mockId),
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateQuestRejectsValidatorForAttested() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidValidator.selector, address(mockId)));
        qm.createQuest(
            "T",
            "D",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.Attested,
            address(mockId),
            100,
            0,
            block.timestamp,
            block.timestamp + 1 days,
            0
        );
    }

    function test_CreateAttestedQuestStoresKind() public {
        vm.prank(creator);
        uint256 id = qm.createQuest(
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
        IQuestManager.Quest memory q = qm.getQuest(id);
        assertTrue(q.validationKind == IQuestManager.ValidationKind.Attested);
        assertEq(q.validator, address(0));
    }

    // --- TEMUAN 1: completion-path gating ---

    function test_CompleteQuestRevertsForAttestedQuest() public {
        vm.prank(creator);
        uint256 id = qm.createQuest(
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
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AttestationRequired.selector, id));
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 0);
    }

    function test_CompleteWithAttestationRevertsForCheckInQuest() public {
        uint256 id = _createOneTime(100, 0, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.QuestNotAttested.selector, id));
        qm.completeQuestWithAttestation(id, block.timestamp + 1 days, "");
    }

    // --- Fuzz: valid quests are always stored correctly ---

    function testFuzz_CreateQuestStoresParams(uint256 reward, uint256 maxCompletions, uint256 duration) public {
        reward = bound(reward, 1, qm.MAX_REWARD_POINTS());
        duration = bound(duration, 1, 365 days);
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "Fuzz Quest",
            "fuzz",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            reward,
            0,
            block.timestamp,
            block.timestamp + duration,
            maxCompletions
        );
        IQuestManager.Quest memory q = qm.getQuest(id);
        assertEq(q.rewardPoints, reward);
        assertEq(q.maxCompletions, maxCompletions);
        assertEq(q.endTime, block.timestamp + duration);
    }
}
