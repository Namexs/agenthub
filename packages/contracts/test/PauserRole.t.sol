// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DeployAgentHub} from "../script/DeployAgentHub.s.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockSafeProxy, MockSafeSingleton} from "./mocks/MockSafeProxy.sol";
import {CanonicalSafeHelper} from "./mocks/CanonicalSafe.sol";

/// @notice FINAL REMEDIATION (Phase 2) — PAUSER_ROLE consistency tests.
/// The production default is: PAUSER_ROLE goes to the verified admin
/// multisig (pauser == address(0) in DeployParams); the deployer keeps
/// nothing; admin is the timelock; sensitive actions go through the
/// 2-day timelock. These tests deploy the real stack via
/// DeployAgentHub.deploy() and assert the post-handover state + behavior.
contract PauserRoleTest is CanonicalSafeHelper {
    DeployAgentHub internal script;
    DeployAgentHub.Deployment internal d;
    QuestManager internal qm;
    Reputation internal reputation;
    Achievement internal achievement;
    TimelockController internal timelock;
    MockAgentId internal mockId;

    address internal deployer;
    address internal multisig;
    // PHASE 8 (PH7-M03): the quest creator is a genuine Safe — a second
    // MockSafeProxy built from the same singleton in setUp.
    address internal creator;
    address internal verifier = makeAddr("verifier");
    address internal stranger = makeAddr("stranger");
    address internal alice = makeAddr("alice");

    function setUp() public {
        script = new DeployAgentHub();
        deployer = address(script);
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("safe-owner-1");
        owners[1] = makeAddr("safe-owner-2");
        owners[2] = makeAddr("safe-owner-3");
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        MockSafeProxy proxy = new MockSafeProxy(address(singleton), owners, 2);
        multisig = address(proxy);
        address[] memory creatorOwners = new address[](3);
        creatorOwners[0] = makeAddr("creator-owner-1");
        creatorOwners[1] = makeAddr("creator-owner-2");
        creatorOwners[2] = makeAddr("creator-owner-3");
        MockSafeProxy creatorProxy = new MockSafeProxy(address(singleton), creatorOwners, 2);
        creator = address(creatorProxy);
        vm.warp(1_000_000);
        // Default configuration: pauser == address(0) → multisig.
        d = script.deploy(
            DeployAgentHub.DeployParams({
                agentId: address(0),
                adminMultisig: multisig,
                questCreator: creator,
                pauser: address(0),
                verifier: verifier,
                safeSingleton: address(singleton),
                safeProxyCodehash: address(proxy).codehash
            }),
            deployer
        );
        qm = QuestManager(d.questManager);
        reputation = Reputation(d.reputation);
        achievement = Achievement(d.achievement);
        timelock = TimelockController(payable(d.timelock));
        mockId = MockAgentId(d.mockAgentId);
    }

    function _expectUnauthorized(address account, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role));
    }

    function test_DeployerHasNoOperationalRoleAfterHandover() public view {
        // The deployer keeps NOTHING — admin, operational, or timelock.
        assertFalse(reputation.hasRole(reputation.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(achievement.hasRole(achievement.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(qm.hasRole(qm.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(reputation.hasRole(reputation.SCORE_SOURCE_ROLE(), deployer));
        assertFalse(achievement.hasRole(achievement.ISSUER_ROLE(), deployer));
        assertFalse(achievement.hasRole(achievement.BADGE_MANAGER_ROLE(), deployer));
        assertFalse(qm.hasRole(qm.QUEST_CREATOR_ROLE(), deployer));
        assertFalse(qm.hasRole(qm.PAUSER_ROLE(), deployer));
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), deployer));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), deployer));
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), deployer));
        assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), deployer));
        // PH7-M04: the deployer does not own the mock either.
        assertEq(mockId.owner(), multisig);
    }

    function test_DefaultPauserIsMultisig() public view {
        assertTrue(qm.hasRole(qm.PAUSER_ROLE(), multisig));
    }

    function test_OnlyMultisigCanPause() public {
        vm.prank(multisig);
        qm.pause();
        assertTrue(qm.paused());
    }

    function test_NonRoleCannotPause() public {
        bytes32 role = qm.PAUSER_ROLE();
        address[4] memory callers = [creator, verifier, stranger, deployer];
        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);
            _expectUnauthorized(callers[i], role);
            qm.pause();
        }
        assertFalse(qm.paused());
    }

    function test_NonRoleCannotUnpause() public {
        vm.prank(multisig);
        qm.pause();
        bytes32 role = qm.DEFAULT_ADMIN_ROLE();
        address[4] memory callers = [creator, verifier, stranger, multisig];
        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);
            _expectUnauthorized(callers[i], role);
            qm.unpause();
        }
        assertTrue(qm.paused(), "unpaused by a non-admin");
    }

    function test_AdminHandoverCorrect() public view {
        // Admin is the timelock on all three AccessControl contracts.
        assertTrue(reputation.hasRole(reputation.DEFAULT_ADMIN_ROLE(), d.timelock));
        assertTrue(achievement.hasRole(achievement.DEFAULT_ADMIN_ROLE(), d.timelock));
        assertTrue(qm.hasRole(qm.DEFAULT_ADMIN_ROLE(), d.timelock));
        // Timelock self-administers; the multisig proposes + executes
        // but does NOT hold the timelock's admin role (config changes
        // go through proposals, not direct multisig calls).
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), d.timelock));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), multisig));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), multisig));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), multisig));
        assertEq(timelock.getMinDelay(), 2 days);
        // Role separation: no address holds two operational roles by
        // default (multisig holds PAUSER + BADGE_MANAGER + timelock
        // proposer/executor — all admin-side; creator/verifier are separate).
        assertFalse(qm.hasRole(qm.QUEST_CREATOR_ROLE(), multisig));
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), multisig));
        assertFalse(qm.hasRole(qm.PAUSER_ROLE(), creator));
        assertFalse(qm.hasRole(qm.PAUSER_ROLE(), verifier));
        assertTrue(reputation.hasRole(reputation.SCORE_SOURCE_ROLE(), d.questManager));
        assertTrue(achievement.hasRole(achievement.ISSUER_ROLE(), d.questManager));
    }

    function test_TimelockDelayEnforced() public {
        vm.prank(multisig);
        qm.pause();
        assertTrue(qm.paused());
        // Schedule unpause through the timelock (multisig proposes).
        bytes32 salt = keccak256("unpause-1");
        vm.prank(multisig);
        timelock.schedule(d.questManager, 0, abi.encodeCall(QuestManager.unpause, ()), bytes32(0), salt, 2 days);
        // Execute BEFORE the delay: must revert. The expected-states
        // bitmap is 1 << OperationState.Ready (Ready = 2 in OZ 5.0.2).
        bytes32 opId =
            timelock.hashOperation(d.questManager, 0, abi.encodeCall(QuestManager.unpause, ()), bytes32(0), salt);
        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, opId, bytes32(uint256(4))
            )
        );
        timelock.execute(d.questManager, 0, abi.encodeCall(QuestManager.unpause, ()), bytes32(0), salt);
        assertTrue(qm.paused(), "unpaused before the timelock delay");
        // Execute AFTER the delay: succeeds, unpause takes effect.
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(multisig);
        timelock.execute(d.questManager, 0, abi.encodeCall(QuestManager.unpause, ()), bytes32(0), salt);
        assertFalse(qm.paused());
    }

    function test_RoleRevocationWorks() public {
        // NOTE: role lookups are hoisted BEFORE vm.prank — prank applies
        // to the NEXT call, and qm.PAUSER_ROLE() is itself a call that
        // would consume it (this failed the first version of this test).
        bytes32 pauserRole = qm.PAUSER_ROLE();
        // The timelock (admin) revokes PAUSER_ROLE from the multisig:
        // the multisig can no longer pause.
        vm.prank(d.timelock);
        qm.revokeRole(pauserRole, multisig);
        assertFalse(qm.hasRole(pauserRole, multisig));
        vm.prank(multisig);
        _expectUnauthorized(multisig, pauserRole);
        qm.pause();
        // Re-grant restores the ability (also via the timelock admin).
        vm.prank(d.timelock);
        qm.grantRole(pauserRole, multisig);
        vm.prank(multisig);
        qm.pause();
        assertTrue(qm.paused());
    }

    function test_PauseStopsCompletionsUntilTimelockUnpause() public {
        // PH7-M04: the mock is owned by the multisig — mint via the Safe.
        vm.prank(multisig);
        mockId.mint(alice);
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "Pausable Quest",
            "pause test",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            10,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0,
            1
        );
        vm.prank(multisig);
        qm.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        qm.completeQuest(id);
        // Unpause via the timelock (2-day delay), then completion works.
        bytes32 salt = keccak256("unpause-2");
        vm.prank(multisig);
        timelock.schedule(d.questManager, 0, abi.encodeCall(QuestManager.unpause, ()), bytes32(0), salt, 2 days);
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(multisig);
        timelock.execute(d.questManager, 0, abi.encodeCall(QuestManager.unpause, ()), bytes32(0), salt);
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 10);
    }
}
