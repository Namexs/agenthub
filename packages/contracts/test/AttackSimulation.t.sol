// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {IAchievement} from "../src/interfaces/IAchievement.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {
    GarbageAgentId,
    RevertingAgentId,
    RevertingReputation,
    ReentrantReceiver,
    MaliciousHolder
} from "./mocks/Malicious.t.sol";

/// @notice Adversarial simulations against the real wired stack.
/// Every test names the attack, attempts it, and proves the system state
/// stays within the security invariants (no double award, no partial state,
/// fail-closed on malicious input).
contract AttackSimulationTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal victim = makeAddr("victim");

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
        mockId.mint(victim);
        vm.warp(1_000_000);
    }

    function _createQuest(uint256 reward, uint256 badgeId) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Quest",
            "attack target",
            IQuestManager.QuestType.OneTime,
            reward,
            badgeId,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    /// @notice ATTACK: reenter via the ERC-721 receiver callback during
    /// badge issuance. EXPECTED: _mint never invokes the callback, so the
    /// reentry code never runs and exactly one badge is minted.
    function test_ReentrancyViaBadgeCallbackImpossible() public {
        uint256 questId = _createQuest(100, BADGE_ID);
        ReentrantReceiver receiver = new ReentrantReceiver(address(achievement), address(qm), questId, BADGE_ID);
        // Grant ISSUER_ROLE to this test so it can issue directly to the
        // receiver (simulating what QuestManager does internally).
        achievement.grantRole(achievement.ISSUER_ROLE(), address(this));
        uint256 tokenId = achievement.issue(address(receiver), BADGE_ID);
        assertEq(receiver.callbackCount(), 0, "callback fired - reentry surface exists");
        assertEq(achievement.balanceOf(address(receiver)), 1);
        assertEq(achievement.ownerOf(tokenId), address(receiver));
    }

    /// @notice ATTACK: complete a quest from inside the Agent ID mint
    /// callback, then complete again directly. EXPECTED: at most ONE award.
    function test_MintCallbackCompletionBoundedToOne() public {
        uint256 questId = _createQuest(100, BADGE_ID);
        MaliciousHolder holder = new MaliciousHolder(address(qm), questId);
        mockId.mint(address(holder)); // callback fires here, attempts completion
        assertEq(holder.callbackCount(), 1);
        // The callback-path completion succeeded (holder legitimately held
        // the ID at that point) — exactly once.
        assertEq(reputation.points(address(holder)), 100);
        assertTrue(achievement.hasBadge(address(holder), BADGE_ID));
        // Any further attempt reverts.
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.AlreadyCompleted.selector, address(holder), questId));
        holder.attack();
        assertEq(reputation.points(address(holder)), 100, "double award via reentry");
    }

    /// @notice ATTACK: Agent ID contract returns malformed data / reverts.
    /// EXPECTED: the gate fails closed; completion reverts; no points.
    function test_MaliciousAgentIdFailsClosed() public {
        // --- Garbage returndata ---
        AgentGate garbageGate = new AgentGate(address(new GarbageAgentId()), block.chainid);
        QuestManager garbageQm =
            new QuestManager(address(garbageGate), address(reputation), address(achievement), admin);
        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(garbageQm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(garbageQm));
        garbageQm.grantRole(garbageQm.QUEST_CREATOR_ROLE(), creator);
        vm.prank(creator);
        uint256 gid = garbageQm.createQuest(
            "G", "g", IQuestManager.QuestType.OneTime, 100, 0, block.timestamp, block.timestamp + 30 days, 0
        );
        vm.prank(alice);
        vm.expectRevert();
        garbageQm.completeQuest(gid);
        assertEq(reputation.points(alice), 0);

        // --- Reverting balanceOf ---
        AgentGate revertingGate = new AgentGate(address(new RevertingAgentId()), block.chainid);
        QuestManager revertingQm =
            new QuestManager(address(revertingGate), address(reputation), address(achievement), admin);
        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(revertingQm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(revertingQm));
        revertingQm.grantRole(revertingQm.QUEST_CREATOR_ROLE(), creator);
        vm.prank(creator);
        uint256 rid = revertingQm.createQuest(
            "R", "r", IQuestManager.QuestType.OneTime, 100, 0, block.timestamp, block.timestamp + 30 days, 0
        );
        vm.prank(alice);
        vm.expectRevert();
        revertingQm.completeQuest(rid);
        assertEq(reputation.points(alice), 0);
    }

    /// @notice ATTACK/FAULT: downstream Reputation reverts mid-completion.
    /// EXPECTED: the whole completion reverts atomically — no completion
    /// recorded, no badge issued, no partial state.
    function test_DownstreamRevertIsAtomic() public {
        RevertingReputation badRep = new RevertingReputation();
        QuestManager atomicQm = new QuestManager(address(gate), address(badRep), address(achievement), admin);
        achievement.grantRole(achievement.ISSUER_ROLE(), address(atomicQm));
        atomicQm.grantRole(atomicQm.QUEST_CREATOR_ROLE(), creator);
        vm.prank(creator);
        uint256 id = atomicQm.createQuest(
            "A", "a", IQuestManager.QuestType.OneTime, 100, BADGE_ID, block.timestamp, block.timestamp + 30 days, 0
        );
        vm.prank(alice);
        vm.expectRevert(RevertingReputation.DownstreamBoom.selector);
        atomicQm.completeQuest(id);
        assertEq(atomicQm.getQuest(id).completions, 0, "partial completion persisted");
        assertFalse(atomicQm.hasCompleted(alice, id), "partial completion flag persisted");
        assertFalse(achievement.hasBadge(alice, BADGE_ID), "badge issued despite revert");
    }

    /// @notice ATTACK/FAULT: completion runs out of gas mid-execution.
    /// EXPECTED: atomic revert — no state change — and the quest still
    /// works afterwards with a normal gas limit.
    function test_GasExhaustionIsAtomic() public {
        uint256 questId = _createQuest(100, BADGE_ID);
        bytes memory payload = abi.encodeWithSelector(IQuestManager.completeQuest.selector, questId);
        vm.prank(alice);
        (bool success,) = address(qm).call{gas: 5_000}(payload);
        assertFalse(success, "completion succeeded on 5k gas");
        assertEq(reputation.points(alice), 0, "points persisted after OOG");
        assertEq(qm.getQuest(questId).completions, 0, "completion persisted after OOG");
        assertFalse(achievement.hasBadge(alice, BADGE_ID), "badge persisted after OOG");
        // Normal completion still works afterwards.
        vm.prank(alice);
        qm.completeQuest(questId);
        assertEq(reputation.points(alice), 100);
    }

    /// @notice ATTACK: attacker completes a quest "for" a victim (replay /
    /// delegated completion). EXPECTED: completion always binds to
    /// msg.sender — there is no victim parameter, so the victim gains
    /// nothing and the attacker cannot spend the victim's one-time slot.
    function test_DelegatedCompletionImpossible() public {
        uint256 questId = _createQuest(100, BADGE_ID);
        vm.prank(alice);
        qm.completeQuest(questId);
        assertEq(reputation.points(alice), 100);
        assertEq(reputation.points(victim), 0, "victim credited by attacker's completion");
        assertFalse(qm.hasCompleted(victim, questId), "victim slot consumed");
        assertFalse(achievement.hasBadge(victim, BADGE_ID));
        // The victim can still complete their own slot afterwards.
        vm.prank(victim);
        qm.completeQuest(questId);
        assertEq(reputation.points(victim), 100);
    }

    /// @notice ATTACK: complete a one-time quest, transfer the Agent ID to
    /// a fresh address, complete again. EXPECTED: the Agent ID is soulbound
    /// — the transfer itself reverts, so the second claim is impossible.
    function test_AgentIdTransferBlockedSoNoDoubleClaim() public {
        uint256 questId = _createQuest(100, 0);
        vm.prank(alice);
        qm.completeQuest(questId);
        address fresh = makeAddr("fresh");
        vm.prank(alice);
        vm.expectRevert();
        mockId.transferFrom(alice, fresh, 1);
        assertEq(mockId.balanceOf(fresh), 0);
        vm.prank(fresh);
        vm.expectRevert();
        qm.completeQuest(questId);
    }
}
