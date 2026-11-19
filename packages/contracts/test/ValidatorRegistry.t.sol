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
import {StateChangingValidator, InvalidBoolValidator} from "./mocks/MaliciousValidators.t.sol";

/// @notice FINAL REMEDIATION (Phase 5) — approved validator REGISTRY
/// tests: metadata storage, empty-metadata rejection, revocation audit
/// trail, emergency revocation by PAUSER_ROLE, and the STATICCALL
/// enforcement that makes `view` real at the EVM level. The allowlist
/// behavior (approved/unapproved/revoked/zero/EOA at creation and
/// completion) is covered in ValidatorAllowlist.t.sol; the malicious
/// validator behavior (reverting, garbage, reentrant, always-true) in
/// Validator.t.sol.
contract ValidatorRegistryTest is Test {
    MockAgentId internal mockId;
    AgentGate internal gate;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;
    MockERC20 internal token;
    TokenBalanceValidator internal validator;

    address internal admin = address(this);
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal pauser = makeAddr("pauser");

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

        mockId.mint(alice);
        token.mint(alice, 100);
        vm.warp(1_000_000);
    }

    function _approve(address v) internal {
        qm.approveValidator(v, "TokenBalanceValidator", "1.0.0", "docs/token-balance-validator");
    }

    function _createOnChainQuest(address v) internal returns (uint256) {
        vm.prank(creator);
        return qm.createQuest(
            "Hold 100 Tokens",
            "Hold at least 100 tokens",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.OnChain,
            v,
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
    }

    // --- Registry metadata ---

    function test_ApproveStoresMetadata() public {
        qm.approveValidator(
            address(validator),
            "TokenBalanceValidator",
            "1.0.0",
            "https://agenthub.example/docs/validators/token-balance"
        );
        IQuestManager.ValidatorInfo memory info = qm.validatorInfo(address(validator));
        assertEq(info.name, "TokenBalanceValidator");
        assertEq(info.version, "1.0.0");
        assertEq(info.documentation, "https://agenthub.example/docs/validators/token-balance");
        assertEq(info.approvedAt, block.timestamp);
        assertTrue(info.approved);
        assertTrue(qm.approvedValidators(address(validator)));
    }

    function test_ApproveRejectsEmptyName() public {
        vm.expectRevert(IQuestManager.InvalidValidatorMetadata.selector);
        qm.approveValidator(address(validator), "", "1.0.0", "docs");
    }

    function test_ApproveRejectsEmptyVersion() public {
        vm.expectRevert(IQuestManager.InvalidValidatorMetadata.selector);
        qm.approveValidator(address(validator), "TokenBalanceValidator", "", "docs");
    }

    function test_ApproveRejectsEmptyDocumentation() public {
        vm.expectRevert(IQuestManager.InvalidValidatorMetadata.selector);
        qm.approveValidator(address(validator), "TokenBalanceValidator", "1.0.0", "");
    }

    function test_RevokeKeepsMetadata() public {
        _approve(address(validator));
        qm.revokeValidator(address(validator));
        IQuestManager.ValidatorInfo memory info = qm.validatorInfo(address(validator));
        assertFalse(info.approved, "revocation did not clear approved");
        assertFalse(qm.approvedValidators(address(validator)));
        // Audit trail: the metadata survives revocation.
        assertEq(info.name, "TokenBalanceValidator");
        assertEq(info.version, "1.0.0");
        assertEq(info.documentation, "docs/token-balance-validator");
        assertEq(info.approvedAt, block.timestamp);
    }

    function test_ReapproveUpdatesMetadata() public {
        _approve(address(validator));
        qm.revokeValidator(address(validator));
        vm.warp(block.timestamp + 1 days);
        qm.approveValidator(address(validator), "TokenBalanceValidator", "2.0.0", "docs/token-balance-v2");
        IQuestManager.ValidatorInfo memory info = qm.validatorInfo(address(validator));
        assertTrue(info.approved);
        assertEq(info.version, "2.0.0");
        assertEq(info.documentation, "docs/token-balance-v2");
        assertEq(info.approvedAt, block.timestamp);
    }

    // --- Emergency revocation ---

    function test_EmergencyRevokeByPauserBlocksCompletions() public {
        _approve(address(validator));
        uint256 id = _createOnChainQuest(address(validator));
        vm.prank(pauser);
        qm.emergencyRevokeValidator(address(validator));
        assertFalse(qm.approvedValidators(address(validator)));
        // Existing quest: completions are frozen immediately.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.ValidatorNotApproved.selector, address(validator)));
        qm.completeQuest(id);
        // New quests cannot use it either.
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

    function test_EmergencyRevokeByNonPauserReverts() public {
        _approve(address(validator));
        // The admin holds DEFAULT_ADMIN_ROLE but NOT PAUSER_ROLE — the
        // fast path is deliberately separate from the slow path.
        vm.expectRevert();
        qm.emergencyRevokeValidator(address(validator));
        vm.prank(creator);
        vm.expectRevert();
        qm.emergencyRevokeValidator(address(validator));
        assertTrue(qm.approvedValidators(address(validator)));
    }

    function test_EmergencyRevokeIdempotent() public {
        _approve(address(validator));
        vm.startPrank(pauser);
        qm.emergencyRevokeValidator(address(validator));
        qm.emergencyRevokeValidator(address(validator));
        vm.stopPrank();
        assertFalse(qm.approvedValidators(address(validator)));
    }

    // --- STATICCALL enforcement (Phase 5) ---

    function test_StateChangingValidatorBlocked() public {
        StateChangingValidator evil = new StateChangingValidator();
        _approve(address(evil));
        uint256 id = _createOnChainQuest(address(evil));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.ValidatorCallFailed.selector, address(evil)));
        qm.completeQuest(id);
        assertEq(evil.counter(), 0, "state change leaked through the staticcall");
        assertEq(reputation.points(alice), 0);
        assertFalse(qm.hasCompleted(alice, id));
    }

    function test_InvalidBoolValidatorReverts() public {
        InvalidBoolValidator bad = new InvalidBoolValidator();
        _approve(address(bad));
        uint256 id = _createOnChainQuest(address(bad));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IQuestManager.InvalidValidatorReturndata.selector, address(bad)));
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 0);
        assertFalse(qm.hasCompleted(alice, id));
    }
}
