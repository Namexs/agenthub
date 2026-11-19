// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {TokenBalanceValidator} from "../src/validators/TokenBalanceValidator.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {AlwaysTrueValidator} from "./mocks/MaliciousValidators.t.sol";

/// @notice PRE-TESTNET CLEANUP (item 6) — validator allowlist tests.
/// OnChain quests may only use validators the admin has approved. This
/// closes the documented "creator picks any validator" caveat: a
/// compromised creator can no longer smuggle a rubber-stamp validator
/// into a quest. Revocation is checked at creation AND at completion, so
/// it takes effect immediately for existing quests too.
contract ValidatorAllowlistTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;
    MockERC20 internal token;
    TokenBalanceValidator internal validator;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal pauser = makeAddr("pauser");
    address internal verifier = makeAddr("verifier");
    address internal stranger = makeAddr("stranger");
    address internal alice = makeAddr("alice");

    uint256 internal constant THRESHOLD = 100;

    function setUp() public {
        mockId = new MockAgentId();
        gate = new AgentGate(address(mockId), block.chainid);
        reputation = new Reputation(admin);
        achievement = new Achievement(admin);
        qm = new QuestManager(address(gate), address(reputation), address(achievement), admin);
        token = new MockERC20();
        validator = new TokenBalanceValidator(address(token), THRESHOLD);

        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), creator);
        qm.grantRole(qm.PAUSER_ROLE(), pauser);
        qm.grantRole(qm.VERIFIER_ROLE(), verifier);

        mockId.mint(alice);
        token.mint(alice, 100);
        vm.warp(1_000_000);
    }

    function _expectUnauthorized(address account, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role));
    }

    function _createOnChainQuest(address validator_, uint256 reward) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Hold 100 Tokens",
            "Hold at least 100 tokens",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.OnChain,
            validator_,
            reward,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    function _createDailyOnChainQuest(address validator_, uint256 reward) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Daily Hold",
            "Hold 100 tokens, daily",
            IQuestManager.QuestType.DailyCheckIn,
            IQuestManager.ValidationKind.OnChain,
            validator_,
            reward,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    // --- Approval administration ---

    function test_ApproveValidatorByAdminWorks() public {
        assertFalse(qm.approvedValidators(address(validator)));
        vm.expectEmit(true, false, false, true, address(qm));
        emit IQuestManager.ValidatorApproved(address(validator));
        qm.approveValidator(address(validator));
        assertTrue(qm.approvedValidators(address(validator)));
    }

    function test_ApproveValidatorRejectsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidValidator.selector, address(0)));
        qm.approveValidator(address(0));
    }

    function test_ApproveValidatorRejectsEoa() public {
        address eoa = makeAddr("eoa-validator");
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidValidator.selector, eoa));
        qm.approveValidator(eoa);
    }

    function test_ApproveValidatorOnlyAdmin() public {
        bytes32 role = qm.DEFAULT_ADMIN_ROLE();
        address[4] memory callers = [creator, pauser, verifier, stranger];
        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);
            _expectUnauthorized(callers[i], role);
            qm.approveValidator(address(validator));
        }
        assertFalse(qm.approvedValidators(address(validator)));
    }

    function test_RevokeValidatorByAdminWorks() public {
        qm.approveValidator(address(validator));
        assertTrue(qm.approvedValidators(address(validator)));
        vm.expectEmit(true, false, false, true, address(qm));
        emit IQuestManager.ValidatorRevoked(address(validator));
        qm.revokeValidator(address(validator));
        assertFalse(qm.approvedValidators(address(validator)));
    }

    function test_RevokeValidatorOnlyAdmin() public {
        qm.approveValidator(address(validator));
        bytes32 role = qm.DEFAULT_ADMIN_ROLE();
        address[4] memory callers = [creator, pauser, verifier, stranger];
        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);
            _expectUnauthorized(callers[i], role);
            qm.revokeValidator(address(validator));
        }
        assertTrue(qm.approvedValidators(address(validator)));
    }

    function test_RevokeIsIdempotent() public {
        // Revoking a validator that was never approved must not revert:
        // an emergency revocation can never be blocked by stale state.
        qm.revokeValidator(address(validator));
        assertFalse(qm.approvedValidators(address(validator)));
        qm.approveValidator(address(validator));
        qm.revokeValidator(address(validator));
        qm.revokeValidator(address(validator));
        assertFalse(qm.approvedValidators(address(validator)));
    }

    function test_ApproveIsIdempotent() public {
        qm.approveValidator(address(validator));
        qm.approveValidator(address(validator));
        assertTrue(qm.approvedValidators(address(validator)));
    }

    // --- Creation-time enforcement ---

    function test_CreateQuestRejectsUnapprovedValidator() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.ValidatorNotApproved.selector, address(validator)));
        qm.createQuest(
            "Hold 100 Tokens",
            "Hold at least 100 tokens",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.OnChain,
            address(validator),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    function test_CreateQuestAcceptsApprovedValidator() public {
        qm.approveValidator(address(validator));
        uint256 id = _createOnChainQuest(address(validator), 100);
        assertEq(qm.getQuest(id).validator, address(validator));
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
    }

    function test_UnapprovedRubberStampCannotBeSmuggled() public {
        // The key anti-smuggling test: a creator cannot attach an
        // always-true validator unless the admin approved it first.
        AlwaysTrueValidator rubber = new AlwaysTrueValidator();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.ValidatorNotApproved.selector, address(rubber)));
        qm.createQuest(
            "Free Points",
            "rubber-stamp quest",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.OnChain,
            address(rubber),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
        assertEq(qm.questCount(), 0, "smuggled quest was created");
    }

    // --- Completion-time enforcement (revocation takes effect now) ---

    function test_RevocationBlocksCompletionOfExistingQuest() public {
        qm.approveValidator(address(validator));
        uint256 id = _createDailyOnChainQuest(address(validator), 10);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 10);

        qm.revokeValidator(address(validator));
        vm.warp(block.timestamp + 1 days); // cooldown over, validator gone
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.ValidatorNotApproved.selector, address(validator)));
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 10, "points awarded after revocation");
        assertEq(qm.getQuest(id).completions, 1);
    }

    function test_ReapprovalRestoresCompletion() public {
        qm.approveValidator(address(validator));
        uint256 id = _createDailyOnChainQuest(address(validator), 10);
        vm.prank(alice);
        qm.completeQuest(id);
        qm.revokeValidator(address(validator));
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.ValidatorNotApproved.selector, address(validator)));
        qm.completeQuest(id);

        qm.approveValidator(address(validator));
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 20);
    }

    // --- Fuzz: no validator is approved by default ---

    function testFuzz_RandomAddressesAreNotApproved(address candidate) public view {
        vm.assume(candidate != address(validator));
        assertFalse(qm.approvedValidators(candidate));
    }
}
