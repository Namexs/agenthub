// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DeployAgentHub} from "../script/DeployAgentHub.s.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice TEMUAN 4 deployment-script tests: the full stack deploys in the
/// right order with the right roles, the deployer keeps nothing, mainnet
/// rejects mocks, and the env-driven run() entry point works end-to-end.
/// No real network is touched: everything runs on the local test EVM.
/// @dev The run() test uses the well-known Anvil test-account-0 private key
/// (public, no real funds) via vm.setEnv, for local simulation only.
contract DeployScriptTest is Test {
    DeployAgentHub internal script;

    // Direct deploy() calls originate from the script contract,
    // so the script IS the deployer in those tests.
    address internal deployer;
    address internal multisig = makeAddr("multisig");
    address internal creator = makeAddr("creator");
    address internal pauser = makeAddr("pauser");
    address internal verifier = makeAddr("verifier");
    address internal alice = makeAddr("alice");

    address internal constant OFFICIAL = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    // Anvil default test account 0 key — public, local simulation only.
    uint256 internal constant ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f3ff80;

    function setUp() public {
        script = new DeployAgentHub();
        deployer = address(script);
        vm.warp(1_000_000);
    }

    function _params() internal view returns (DeployAgentHub.DeployParams memory) {
        return DeployAgentHub.DeployParams({
            agentId: address(0), // deploy a mock
            adminMultisig: multisig,
            questCreator: creator,
            pauser: pauser,
            verifier: verifier
        });
    }

    function test_LocalDeployWiresEverything() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);

        assertTrue(d.mockAgentId != address(0), "mock not deployed");
        assertTrue(d.agentGate != address(0));
        assertTrue(d.timelock != address(0));
        assertTrue(d.reputation != address(0));
        assertTrue(d.achievement != address(0));
        assertTrue(d.questManager != address(0));

        AgentGate gate = AgentGate(d.agentGate);
        QuestManager qm = QuestManager(d.questManager);
        Reputation reputation = Reputation(d.reputation);
        Achievement achievement = Achievement(d.achievement);
        TimelockController timelock = TimelockController(payable(d.timelock));

        // Identity wiring.
        assertEq(gate.agentIdContract(), d.mockAgentId);
        assertEq(gate.expectedChainId(), block.chainid);
        assertEq(address(qm.gate()), d.agentGate);
        assertEq(address(qm.reputation()), d.reputation);
        assertEq(address(qm.achievement()), d.achievement);

        // Timelock wiring: self-administered, multisig proposes + executes.
        assertEq(timelock.getMinDelay(), 2 days);
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), multisig));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), multisig));
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), d.timelock));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), multisig));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer));

        // Admin is the timelock everywhere.
        assertTrue(reputation.hasRole(reputation.DEFAULT_ADMIN_ROLE(), d.timelock));
        assertTrue(achievement.hasRole(achievement.DEFAULT_ADMIN_ROLE(), d.timelock));
        assertTrue(qm.hasRole(qm.DEFAULT_ADMIN_ROLE(), d.timelock));

        // Operational roles.
        assertTrue(reputation.hasRole(reputation.SCORE_SOURCE_ROLE(), d.questManager));
        assertTrue(achievement.hasRole(achievement.ISSUER_ROLE(), d.questManager));
        assertTrue(achievement.hasRole(achievement.BADGE_MANAGER_ROLE(), multisig));
        assertTrue(qm.hasRole(qm.QUEST_CREATOR_ROLE(), creator));
        assertTrue(qm.hasRole(qm.PAUSER_ROLE(), pauser));
        assertTrue(qm.hasRole(qm.VERIFIER_ROLE(), verifier));

        // The deployer keeps NOTHING (SEC-002).
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
    }

    function test_DeployedStackWorksEndToEnd() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        MockAgentId mock = MockAgentId(d.mockAgentId);
        QuestManager qm = QuestManager(d.questManager);
        Reputation reputation = Reputation(d.reputation);

        // The mock's owner is the deployer (the script contract here).
        vm.prank(deployer);
        mock.mint(alice);
        vm.prank(creator);
        uint256 id = qm.createQuest(
            "First Quest",
            "deployed-stack smoke test",
            IQuestManager.QuestType.OneTime,
            IQuestManager.ValidationKind.CheckIn,
            address(0),
            100,
            0,
            block.timestamp,
            block.timestamp + 30 days,
            0
        );
        vm.prank(alice);
        qm.completeQuest(id);
        assertEq(reputation.points(alice), 100);
    }

    function test_DeployWithExplicitAgentIdSkipsMock() public {
        MockAgentId existing = new MockAgentId();
        DeployAgentHub.DeployParams memory params = _params();
        params.agentId = address(existing);
        DeployAgentHub.Deployment memory d = script.deploy(params, deployer);
        assertEq(d.mockAgentId, address(0), "mock deployed despite explicit address");
        assertEq(AgentGate(d.agentGate).agentIdContract(), address(existing));
    }

    function test_DeployWithoutVerifierSkipsRole() public {
        DeployAgentHub.DeployParams memory params = _params();
        params.verifier = address(0);
        DeployAgentHub.Deployment memory d = script.deploy(params, deployer);
        QuestManager qm = QuestManager(d.questManager);
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), verifier));
    }

    function test_DeployRejectsZeroMultisig() public {
        DeployAgentHub.DeployParams memory params = _params();
        params.adminMultisig = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.ZeroAddress.selector, "adminMultisig"));
        script.deploy(params, deployer);
    }

    function test_DeployRejectsZeroCreator() public {
        DeployAgentHub.DeployParams memory params = _params();
        params.questCreator = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.ZeroAddress.selector, "questCreator"));
        script.deploy(params, deployer);
    }

    function test_DeployRejectsZeroPauser() public {
        DeployAgentHub.DeployParams memory params = _params();
        params.pauser = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.ZeroAddress.selector, "pauser"));
        script.deploy(params, deployer);
    }

    function test_DeployRejectsUnsupportedChain() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.UnsupportedChain.selector, 1));
        script.deploy(_params(), deployer);
    }

    function test_MainnetRejectsMockAgentId() public {
        vm.chainId(56);
        MockAgentId mock = new MockAgentId();
        DeployAgentHub.DeployParams memory params = _params();
        params.agentId = address(mock);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.MainnetRequiresOfficialAgentId.selector, address(mock)));
        script.deploy(params, deployer);
    }

    function test_MainnetRejectsZeroAgentId() public {
        vm.chainId(56);
        DeployAgentHub.DeployParams memory params = _params();
        params.agentId = address(0);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.MainnetRequiresOfficialAgentId.selector, address(0)));
        script.deploy(params, deployer);
    }

    function test_MainnetAcceptsOfficialAgentId() public {
        vm.chainId(56);
        // Etch mock code at the official address so the gate's code check
        // passes (the real mainnet contract cannot be tested locally).
        MockAgentId mock = new MockAgentId();
        vm.etch(OFFICIAL, address(mock).code);
        DeployAgentHub.DeployParams memory params = _params();
        params.agentId = OFFICIAL;
        DeployAgentHub.Deployment memory d = script.deploy(params, deployer);
        assertEq(d.mockAgentId, address(0), "mock deployed on mainnet");
        assertEq(AgentGate(d.agentGate).agentIdContract(), OFFICIAL);
    }

    function test_TestnetAcceptsMock() public {
        vm.chainId(97);
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        assertTrue(d.mockAgentId != address(0));
        assertEq(AgentGate(d.agentGate).agentIdContract(), d.mockAgentId);
    }

    // --- run() entry point (env-driven) ---

    function _setRunEnv() internal {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(bytes32(ANVIL_KEY)));
        vm.setEnv("ADMIN_MULTISIG", vm.toString(multisig));
        vm.setEnv("QUEST_CREATOR", vm.toString(creator));
        vm.setEnv("PAUSER", vm.toString(pauser));
        vm.setEnv("VERIFIER", vm.toString(verifier));
    }

    function test_RunDeploysLocalStack() public {
        _setRunEnv();
        // No AGENT_ID_ADDRESS set: a mock is deployed (local chain).
        DeployAgentHub.Deployment memory d = script.run();
        assertTrue(d.mockAgentId != address(0));
        assertTrue(d.questManager != address(0));
        // The broadcast deployer is Anvil account 0, and it keeps nothing.
        address anvilDeployer = vm.addr(ANVIL_KEY);
        QuestManager qm = QuestManager(d.questManager);
        assertFalse(qm.hasRole(qm.DEFAULT_ADMIN_ROLE(), anvilDeployer));
        assertFalse(qm.hasRole(qm.VERIFIER_ROLE(), anvilDeployer));
        assertTrue(qm.hasRole(qm.VERIFIER_ROLE(), verifier));
    }

    function test_RunRefusesMainnetWithoutConfirmation() public {
        vm.chainId(56);
        _setRunEnv();
        vm.setEnv("AGENT_ID_ADDRESS", vm.toString(OFFICIAL));
        // Explicitly false: vm.setEnv persists across tests in one run,
        // so a sibling test's "true" would otherwise leak in here.
        vm.setEnv("CONFIRM_MAINNET_DEPLOY", "false");
        vm.expectRevert(DeployAgentHub.MainnetDeployNotConfirmed.selector);
        script.run();
    }

    function test_RunMainnetWithConfirmationDeploys() public {
        vm.chainId(56);
        _setRunEnv();
        vm.setEnv("AGENT_ID_ADDRESS", vm.toString(OFFICIAL));
        vm.setEnv("CONFIRM_MAINNET_DEPLOY", "true");
        MockAgentId mock = new MockAgentId();
        vm.etch(OFFICIAL, address(mock).code);
        DeployAgentHub.Deployment memory d = script.run();
        assertEq(d.mockAgentId, address(0));
        assertEq(AgentGate(d.agentGate).agentIdContract(), OFFICIAL);
    }
}
