// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DeployAgentHub} from "../script/DeployAgentHub.s.sol";
import {ProposeGrantVerifier} from "../script/ProposeGrantVerifier.s.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockSafeProxy, MockSafeSingleton} from "./mocks/MockSafeProxy.sol";

/// @notice PHASE 9.1 (PH7-L19): the second-verifier grant goes through
/// the timelock — scheduled, 2-day delay, then executed. No direct
/// grant path exists: only the timelock itself is the QuestManager
/// admin. Local chain only — nothing is broadcast.
/// @dev The proposer on the production stack is the admin multisig
/// Safe, which has no private key: the script PREPARES the proposal
/// (buildProposal) and the Safe schedules it with the printed
/// arguments. The tests mirror that split — the schedule/execute flow
/// runs against the real stack with the Safe as proposer, and
/// scheduleGrant itself is covered end-to-end against a synthetic
/// timelock whose proposer is the script contract.
contract ProposeGrantVerifierTest is Test {
    DeployAgentHub internal deployScript;
    ProposeGrantVerifier internal proposer;

    DeployAgentHub.Deployment internal d;
    QuestManager internal qm;
    TimelockController internal timelock;

    address internal multisig;
    address internal creator;
    address internal safeSingleton;
    bytes32 internal safeProxyCodehash;
    address internal pauser = makeAddr("pauser");
    address internal verifier1 = makeAddr("verifier1");
    address internal verifier2 = makeAddr("verifier2");
    address internal alice = makeAddr("alice");
    bytes32 internal salt = bytes32(uint256(0xA11CE));

    // OZ OperationState: Unset=0, Waiting=1, Ready=2, Done=3 — the
    // execute-before-ready revert encodes Ready as bitmap 1 << 2.
    bytes32 internal constant READY_BITMAP = bytes32(uint256(4));

    function setUp() public {
        deployScript = new DeployAgentHub();
        proposer = new ProposeGrantVerifier();
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("safe-owner-1");
        owners[1] = makeAddr("safe-owner-2");
        owners[2] = makeAddr("safe-owner-3");
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        multisig = address(new MockSafeProxy(address(singleton), owners, 2));
        safeSingleton = address(singleton);
        safeProxyCodehash = multisig.codehash;
        address[] memory creatorOwners = new address[](3);
        creatorOwners[0] = makeAddr("creator-owner-1");
        creatorOwners[1] = makeAddr("creator-owner-2");
        creatorOwners[2] = makeAddr("creator-owner-3");
        creator = address(new MockSafeProxy(address(singleton), creatorOwners, 2));
        vm.warp(1_000_000);
        d = deployScript.deploy(_params(), address(deployScript));
        qm = QuestManager(d.questManager);
        timelock = TimelockController(payable(d.timelock));
    }

    function _params() internal view returns (DeployAgentHub.DeployParams memory) {
        return DeployAgentHub.DeployParams({
            agentId: address(0), // deploy a mock
            adminMultisig: multisig,
            questCreator: creator,
            pauser: pauser,
            verifier: verifier1,
            safeSingleton: safeSingleton,
            safeProxyCodehash: safeProxyCodehash
        });
    }

    /// @notice Synthetic stack for scheduleGrant end-to-end tests: a
    /// timelock with the PROPOSER script contract as proposer (so
    /// scheduleGrant can schedule) and this test as executor, admin
    /// over a fresh QuestManager.
    function _syntheticStack(uint256 delay) internal returns (TimelockController synthTimelock, QuestManager synthQm) {
        MockAgentId mockId = new MockAgentId();
        AgentGate gate = new AgentGate(address(mockId), block.chainid);
        Reputation reputation = new Reputation(address(this));
        Achievement achievement = new Achievement(address(this));
        synthQm = new QuestManager(address(gate), address(reputation), address(achievement), address(this));
        address[] memory proposers = new address[](1);
        proposers[0] = address(proposer);
        address[] memory executors = new address[](1);
        executors[0] = address(this);
        synthTimelock = new TimelockController(delay, proposers, executors, address(0));
        synthQm.grantRole(synthQm.DEFAULT_ADMIN_ROLE(), address(synthTimelock));
        synthQm.renounceRole(synthQm.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_BuildProposalProducesCorrectOperation() public view {
        ProposeGrantVerifier.Proposal memory p = proposer.buildProposal(address(timelock), address(qm), verifier2, salt);
        assertEq(p.timelock, address(timelock));
        assertEq(p.questManager, address(qm));
        assertEq(p.verifier, verifier2);
        assertEq(p.salt, salt);
        assertEq(p.delay, 2 days, "delay is not 2 days");
        assertEq(p.readyAt, block.timestamp + 2 days, "readyAt is not now + 2 days");
        assertEq(p.data, abi.encodeCall(IAccessControl.grantRole, (qm.VERIFIER_ROLE(), verifier2)), "wrong calldata");
        assertEq(
            p.operationId,
            timelock.hashOperation(address(qm), 0, p.data, bytes32(0), salt),
            "operation id does not match the timelock hash"
        );
    }

    function test_DefaultSaltIsDerivedFromVerifier() public view {
        ProposeGrantVerifier.Proposal memory p =
            proposer.buildProposal(address(timelock), address(qm), verifier2, bytes32(0));
        assertEq(p.salt, keccak256(abi.encodePacked("agenthub-grant-verifier", verifier2)), "wrong default salt");
    }

    function test_ScheduleExecuteGrantsVerifierAfterDelay() public {
        ProposeGrantVerifier.Proposal memory p = proposer.buildProposal(address(timelock), address(qm), verifier2, salt);
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), verifier2), "verifier2 already has the role");

        // 2. SCHEDULE — the multisig (proposer) schedules with the
        // script's exact arguments.
        vm.prank(multisig);
        timelock.schedule(address(qm), 0, p.data, bytes32(0), p.salt, p.delay);
        assertTrue(timelock.isOperationPending(p.operationId), "operation not pending");
        assertFalse(timelock.isOperationReady(p.operationId), "operation ready too early");
        assertEq(timelock.getTimestamp(p.operationId), block.timestamp + 2 days, "wrong ready timestamp");

        // 3. DELAY — the grant is NOT effective: execute reverts.
        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, p.operationId, READY_BITMAP
            )
        );
        timelock.execute(address(qm), 0, p.data, bytes32(0), p.salt);
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), verifier2), "grant effective before delay");

        // One second before the delay: still not ready.
        vm.warp(block.timestamp + 2 days - 1);
        assertFalse(timelock.isOperationReady(p.operationId), "operation ready 1s early");

        // 4. EXECUTE — after the delay, the multisig (executor)
        // executes and the grant lands.
        vm.warp(block.timestamp + 1);
        assertTrue(timelock.isOperationReady(p.operationId), "operation not ready after delay");
        vm.prank(multisig);
        timelock.execute(address(qm), 0, p.data, bytes32(0), p.salt);
        assertTrue(timelock.isOperationDone(p.operationId), "operation not done");
        assertTrue(qm.hasRole(qm.VERIFIER_ROLE(), verifier2), "grant did not land after execute");
    }

    function test_ScheduleGrantEndToEnd() public {
        // scheduleGrant itself, against a timelock whose proposer is
        // the script contract: schedule -> delay -> execute -> grant.
        (TimelockController synthTimelock, QuestManager synthQm) = _syntheticStack(2 days);
        ProposeGrantVerifier.Proposal memory p =
            proposer.scheduleGrant(address(synthTimelock), address(synthQm), verifier2, salt);
        assertTrue(synthTimelock.isOperationPending(p.operationId), "operation not pending");
        assertFalse(synthQm.hasRole(synthQm.VERIFIER_ROLE(), verifier2), "grant effective before delay");
        vm.warp(block.timestamp + 2 days);
        synthTimelock.execute(address(synthQm), 0, p.data, bytes32(0), p.salt);
        assertTrue(synthQm.hasRole(synthQm.VERIFIER_ROLE(), verifier2), "grant did not land after execute");
    }

    function test_NonProposerCannotSchedule() public {
        // Hoist before prank/expectRevert: the role getter IS a call
        // and would consume either (same lesson as IntegrationTest).
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        // scheduleGrant against the production timelock: the script
        // contract is NOT a proposer there, so the timelock reverts.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(proposer), proposerRole
            )
        );
        proposer.scheduleGrant(address(timelock), address(qm), verifier2, salt);
        // And a direct schedule call from a non-proposer reverts too.
        ProposeGrantVerifier.Proposal memory p = proposer.buildProposal(address(timelock), address(qm), verifier2, salt);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, proposerRole)
        );
        vm.prank(alice);
        timelock.schedule(address(qm), 0, p.data, bytes32(0), p.salt, p.delay);
    }

    function test_DirectGrantReverts() public {
        // There is NO direct-grant path: even the multisig cannot
        // grant VERIFIER_ROLE — only the timelock (the QM admin) can.
        // Hoist before prank/expectRevert: the role getters ARE calls
        // and would consume either (same lesson as IntegrationTest).
        bytes32 adminRole = qm.DEFAULT_ADMIN_ROLE();
        bytes32 verifierRole = qm.VERIFIER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, multisig, adminRole)
        );
        vm.prank(multisig);
        qm.grantRole(verifierRole, verifier2);
        assertFalse(qm.hasRole(verifierRole, verifier2));
    }

    function test_CancelBeforeExecutePreventsGrant() public {
        ProposeGrantVerifier.Proposal memory p = proposer.buildProposal(address(timelock), address(qm), verifier2, salt);
        vm.prank(multisig);
        timelock.schedule(address(qm), 0, p.data, bytes32(0), p.salt, p.delay);
        // The multisig holds CANCELLER_ROLE (PH7-L17) and cancels
        // before the delay passes.
        vm.prank(multisig);
        timelock.cancel(p.operationId);
        assertFalse(timelock.isOperationPending(p.operationId), "cancelled operation still pending");
        vm.warp(block.timestamp + 2 days);
        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, p.operationId, READY_BITMAP
            )
        );
        timelock.execute(address(qm), 0, p.data, bytes32(0), p.salt);
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), verifier2), "grant landed after cancel");
    }

    function test_BuildProposalRejectsZeroVerifier() public {
        vm.expectRevert(abi.encodeWithSelector(ProposeGrantVerifier.ZeroAddress.selector, "verifier"));
        proposer.buildProposal(address(timelock), address(qm), address(0), salt);
    }

    function test_BuildProposalRejectsExistingVerifier() public {
        // verifier1 already holds the role from deployment.
        assertTrue(qm.hasRole(qm.VERIFIER_ROLE(), verifier1));
        vm.expectRevert(abi.encodeWithSelector(ProposeGrantVerifier.VerifierAlreadyHasRole.selector, verifier1));
        proposer.buildProposal(address(timelock), address(qm), verifier1, salt);
    }

    function test_BuildProposalRejectsNonAdminTimelock() public {
        // A genuine 2-day timelock that is NOT the QuestManager admin.
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        TimelockController stranger = new TimelockController(2 days, proposers, executors, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                ProposeGrantVerifier.TimelockNotQuestManagerAdmin.selector, address(stranger), address(qm)
            )
        );
        proposer.buildProposal(address(stranger), address(qm), verifier2, salt);
    }

    function test_BuildProposalRejectsWrongDelay() public {
        // A timelock with a 1-day minDelay that IS the QM admin — the
        // script refuses anything but the 2-day AGENTHUB policy.
        (TimelockController shortTimelock, QuestManager synthQm) = _syntheticStack(1 days);
        vm.expectRevert(abi.encodeWithSelector(ProposeGrantVerifier.UnexpectedTimelockDelay.selector, 1 days, 2 days));
        proposer.buildProposal(address(shortTimelock), address(synthQm), verifier2, salt);
    }

    function test_BuildProposalRejectsNoCodeAddresses() public {
        address eoa = makeAddr("no-code");
        vm.expectRevert(abi.encodeWithSelector(ProposeGrantVerifier.NoCodeAtAddress.selector, eoa, "timelock"));
        proposer.buildProposal(eoa, address(qm), verifier2, salt);
        vm.expectRevert(abi.encodeWithSelector(ProposeGrantVerifier.NoCodeAtAddress.selector, eoa, "questManager"));
        proposer.buildProposal(address(timelock), eoa, verifier2, salt);
    }
}
