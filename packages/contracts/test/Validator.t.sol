// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {TokenBalanceValidator} from "../src/validators/TokenBalanceValidator.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    RevertingValidator,
    GarbageValidator,
    ReentrantValidator,
    AlwaysTrueValidator
} from "./mocks/MaliciousValidators.t.sol";
import {GarbageAgentId, RevertingAgentId} from "./mocks/Malicious.t.sol";

/// @notice TEMUAN 1 on-chain validation tests: the reference
/// TokenBalanceValidator (fail-closed balance checks) and the OnChain
/// completion path, including malicious validators (reverting, garbage
/// returndata, reentrant) and the rubber-stamp trust caveat.
contract ValidatorTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;
    MockERC20 internal token;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant THRESHOLD = 100;

    function setUp() public {
        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new Reputation(admin);
        achievement = new Achievement(admin);
        qm = new QuestManager(address(gate), address(reputation), address(achievement), admin);
        token = new MockERC20();

        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);

        mockId.mint(alice);
        mockId.mint(bob);
        token.mint(alice, 100);
        // bob holds 0 tokens.
        vm.warp(1_000_000);
    }

    function _createOnChainQuest(address validator, uint256 reward) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Hold 100 Tokens",
            "Hold at least 100 tokens",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.OnChain,
            validator,
            reward,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    // --- TokenBalanceValidator unit tests ---

    function test_TokenBalanceValidatorAcceptsHolderAtThreshold() public {
        TokenBalanceValidator v = new TokenBalanceValidator(address(token), THRESHOLD);
        assertTrue(v.validate(alice, 1)); // exactly 100
        assertFalse(v.validate(bob, 1)); // 0
        assertFalse(v.validate(address(0), 1));
    }

    function test_TokenBalanceValidatorRejectsZeroToken() public {
        vm.expectRevert(TokenBalanceValidator.ZeroAddress.selector);
        new TokenBalanceValidator(address(0), THRESHOLD);
    }

    function test_TokenBalanceValidatorRejectsEoaToken() public {
        address eoa = makeAddr("eoa");
        vm.expectRevert(abi.encodeWithSelector(TokenBalanceValidator.NoCodeAtToken.selector, eoa));
        new TokenBalanceValidator(eoa, THRESHOLD);
    }

    function test_TokenBalanceValidatorFailsClosedOnRevertingToken() public {
        RevertingAgentId bad = new RevertingAgentId();
        TokenBalanceValidator v = new TokenBalanceValidator(address(bad), THRESHOLD);
        assertFalse(v.validate(alice, 1));
    }

    function test_TokenBalanceValidatorFailsClosedOnGarbageToken() public {
        GarbageAgentId garbage = new GarbageAgentId();
        TokenBalanceValidator v = new TokenBalanceValidator(address(garbage), THRESHOLD);
        assertFalse(v.validate(alice, 1));
    }

    function testFuzz_TokenBalanceThreshold(uint256 balance, uint256 threshold) public {
        threshold = bound(threshold, 0, 1_000_000);
        balance = bound(balance, 0, 1_000_000);
        MockERC20 t = new MockERC20();
        t.mint(alice, balance);
        TokenBalanceValidator v = new TokenBalanceValidator(address(t), threshold);
        assertEq(v.validate(alice, 1), balance >= threshold);
    }

    // --- OnChain completion path ---

    function test_OnChainQuestCompletionWithValidator() public {
        TokenBalanceValidator v = new TokenBalanceValidator(address(token), THRESHOLD);
        uint256 id = _createOnChainQuest(address(v), 100);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
        assertTrue(qm.hasCompleted(alice, id));
    }

    function test_OnChainQuestRejectsInsufficientBalance() public {
        TokenBalanceValidator v = new TokenBalanceValidator(address(token), THRESHOLD);
        uint256 id = _createOnChainQuest(address(v), 100);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.OnChainValidationFailed.selector, id, bob));
        qm.completeQuest(id);
        assertEq(reputation.points(bob), 0);
        assertFalse(qm.hasCompleted(bob, id));
        assertEq(qm.getQuest(id).completions, 0);
    }

    function test_OnChainQuestCompletionAfterGainingBalance() public {
        TokenBalanceValidator v = new TokenBalanceValidator(address(token), THRESHOLD);
        uint256 id = _createOnChainQuest(address(v), 100);
        vm.prank(bob);
        vm.expectRevert();
        qm.completeQuest(id);
        // Bob acquires the tokens; the check is live, not cached.
        token.mint(bob, 100);
        vm.prank(bob);
        qm.completeQuest(id);
        assertEq(reputation.points(bob), 100);
    }

    function test_OnChainQuestRechecksBalanceEveryCompletion() public {
        TokenBalanceValidator v = new TokenBalanceValidator(address(token), THRESHOLD);
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "Daily Hold",
            "Hold 100 tokens, daily",
            IQuestManager.QuestType.DailyCheckIn,
            IQuestManager.ValidationKind.OnChain,
            address(v),
            10,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 10);
        // Alice dumps her tokens, waits out the cooldown, tries again.
        vm.prank(alice);
        token.transfer(bob, 100);
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.OnChainValidationFailed.selector, id, alice));
        qm.completeQuest(id);
        // She buys back in and completes again.
        vm.prank(bob);
        token.transfer(alice, 100);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 20);
    }

    // --- Malicious validators ---

    function test_RevertingValidatorFailsClosed() public {
        RevertingValidator bad = new RevertingValidator();
        uint256 id = _createOnChainQuest(address(bad), 100);
        vm.prank(alice);
        vm.expectRevert(RevertingValidator.ValidatorBoom.selector);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 0);
        assertFalse(qm.hasCompleted(alice, id));
        assertEq(qm.getQuest(id).completions, 0, "partial completion persisted");
    }

    function test_GarbageValidatorFailsClosed() public {
        GarbageValidator garbage = new GarbageValidator();
        uint256 id = _createOnChainQuest(address(garbage), 100);
        vm.prank(alice);
        vm.expectRevert(); // ABI decode of 1-byte returndata reverts
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 0);
        assertFalse(qm.hasCompleted(alice, id));
    }

    function test_ReentrantValidatorCannotDoubleAward() public {
        ReentrantValidator evil = new ReentrantValidator(address(qm));
        uint256 id = _createOnChainQuest(address(evil), 100);
        evil.setQuest(id);
        vm.prank(alice);
        qm.completeQuest(id);
        // The reentry attempt inside validate() hit nonReentrant and died;
        // the outer completion awarded exactly once.
        assertEq(reputation.points(alice), 100, "double award via validator reentry");
        assertEq(qm.getQuest(id).completions, 1);
    }

    function test_AlwaysTrueValidatorBehavesLikeCheckIn() public {
        // DOCUMENTED TRUST CAVEAT: a rubber-stamp validator makes the
        // quest equivalent to a CheckIn quest. This test pins that
        // behavior — the mitigation is governance review of validators
        // before creators use them, not a code check (see
        // QUEST_VALIDATION_DESIGN.md).
        AlwaysTrueValidator rubber = new AlwaysTrueValidator();
        uint256 id = _createOnChainQuest(address(rubber), 100);
        vm.prank(bob); // bob holds 0 tokens
        qm.completeQuest(id);
        assertEq(reputation.points(bob), 100);
    }
}
