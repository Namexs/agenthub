// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DeployAgentHub} from "../script/DeployAgentHub.s.sol";
import {SafeValidation} from "../script/SafeValidation.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {IQuestManager} from "../src/interfaces/IQuestManager.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";
import {MockSafe} from "./mocks/MockSafe.sol";
import {MockSafeProxy, MockSafeSingleton} from "./mocks/MockSafeProxy.sol";
import {CanonicalSafeHelper} from "./mocks/CanonicalSafe.sol";

/// @notice TEMUAN 4 deployment-script tests: the full stack deploys in the
/// right order with the right roles, the deployer keeps nothing, mainnet
/// rejects mocks, and the env-driven run() entry point works end-to-end.
/// No real network is touched: everything runs on the local test EVM.
/// @dev The run() test uses the well-known Anvil test-account-0 private key
/// (public, no real funds) via vm.setEnv, for local simulation only.
contract DeployScriptTest is CanonicalSafeHelper {
    DeployAgentHub internal script;

    // Direct deploy() calls originate from the script contract,
    // so the script IS the deployer in those tests.
    address internal deployer;
    // FINAL REMEDIATION (Phase 1): the admin multisig is a MockSafeProxy
    // (2-of-3, proxy-shaped with a singleton) validated via the LOCAL
    // explicit path (31337) — deploy() now verifies the singleton +
    // proxy codehash, not just getThreshold/getOwners. Chain 56/97
    // tests use a canonical-bytecode proxy instead (see _canonicalParams).
    MockSafeProxy internal safeProxy;
    address internal multisig;
    address internal safeSingleton;
    bytes32 internal safeProxyCodehash;
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
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("safe-owner-1");
        owners[1] = makeAddr("safe-owner-2");
        owners[2] = makeAddr("safe-owner-3");
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        safeProxy = new MockSafeProxy(address(singleton), owners, 2);
        multisig = address(safeProxy);
        safeSingleton = address(singleton);
        safeProxyCodehash = address(safeProxy).codehash;
        vm.warp(1_000_000);
    }

    function _params() internal view returns (DeployAgentHub.DeployParams memory) {
        return DeployAgentHub.DeployParams({
            agentId: address(0), // deploy a mock
            adminMultisig: multisig,
            questCreator: creator,
            pauser: pauser,
            verifier: verifier,
            safeSingleton: safeSingleton,
            safeProxyCodehash: safeProxyCodehash
        });
    }

    /// @notice Params for chain 56/97 tests: a canonical-bytecode Safe
    /// proxy as the multisig, with NO explicit Safe values — production
    /// chains enforce the canonical singleton + codehash sets.
    function _canonicalParams() internal returns (DeployAgentHub.DeployParams memory) {
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("safe-owner-1");
        owners[1] = makeAddr("safe-owner-2");
        owners[2] = makeAddr("safe-owner-3");
        address canonicalSafe = deployCanonicalSafe(owners, 2);
        return DeployAgentHub.DeployParams({
            agentId: address(0),
            adminMultisig: canonicalSafe,
            questCreator: creator,
            pauser: pauser,
            verifier: verifier,
            safeSingleton: address(0),
            safeProxyCodehash: bytes32(0)
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

    // --- PRE-TESTNET CLEANUP (item 5): ADMIN_MULTISIG Safe validation ---

    function test_DeployRejectsEoaMultisig() public {
        address eoa = makeAddr("eoa-multisig");
        DeployAgentHub.DeployParams memory params = _params();
        params.adminMultisig = eoa;
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.NotASafe.selector, eoa, "no code"));
        script.deploy(params, deployer);
    }

    function test_DeployRejectsNonSafeContract() public {
        // A contract WITHOUT the Safe interface: getThreshold staticcall
        // reverts (no fallback), so validation fails closed.
        MockAgentId notSafe = new MockAgentId();
        DeployAgentHub.DeployParams memory params = _params();
        params.adminMultisig = address(notSafe);
        vm.expectRevert(
            abi.encodeWithSelector(SafeValidation.NotASafe.selector, address(notSafe), "getThreshold failed")
        );
        script.deploy(params, deployer);
    }

    function test_DeployRejectsThresholdOneSafe() public {
        // 1-of-3 is a single key with extra steps — below the minimum.
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("o1");
        owners[1] = makeAddr("o2");
        owners[2] = makeAddr("o3");
        MockSafe weak = new MockSafe(owners, 1);
        DeployAgentHub.DeployParams memory params = _params();
        params.adminMultisig = address(weak);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsafeThreshold.selector, address(weak), 1, 3));
        script.deploy(params, deployer);
    }

    function test_DeployRejectsThresholdAboveOwners() public {
        // Threshold 3 with 2 owners can never reach quorum — unusable Safe.
        address[] memory owners = new address[](2);
        owners[0] = makeAddr("o1");
        owners[1] = makeAddr("o2");
        MockSafe broken = new MockSafe(owners, 3);
        DeployAgentHub.DeployParams memory params = _params();
        params.adminMultisig = address(broken);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsafeThreshold.selector, address(broken), 3, 2));
        script.deploy(params, deployer);
    }

    function test_DeployAcceptsThresholdThreeOfThree() public {
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("o1");
        owners[1] = makeAddr("o2");
        owners[2] = makeAddr("o3");
        MockSafeSingleton singleton = new MockSafeSingleton("1.4.1");
        MockSafeProxy strict = new MockSafeProxy(address(singleton), owners, 3);
        DeployAgentHub.DeployParams memory params = _params();
        params.adminMultisig = address(strict);
        params.safeSingleton = address(singleton);
        params.safeProxyCodehash = address(strict).codehash;
        DeployAgentHub.Deployment memory d = script.deploy(params, deployer);
        assertTrue(d.questManager != address(0));
        TimelockController timelock = TimelockController(payable(d.timelock));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(strict)));
    }

    function test_DeployRejectsExplicitSafeValuesOnProduction() public {
        // FINAL REMEDIATION (Phase 1): explicit singleton/codehash are a
        // local-only escape hatch — passing them on chain 97 must revert
        // even though the multisig itself is a genuine canonical Safe.
        vm.chainId(97);
        DeployAgentHub.DeployParams memory params = _canonicalParams();
        params.safeSingleton = makeAddr("explicit-singleton");
        params.safeProxyCodehash = bytes32(uint256(1));
        vm.expectRevert(DeployAgentHub.ExplicitSingletonNotAllowedOnProduction.selector);
        script.deploy(params, deployer);
    }

    function test_DeployRejectsMissingLocalSafeConfig() public {
        // On 31337 the explicit Safe values are REQUIRED (canonical
        // Safes are not deployed locally) — omitting them reverts.
        DeployAgentHub.DeployParams memory params = _params();
        params.safeSingleton = address(0);
        params.safeProxyCodehash = bytes32(0);
        vm.expectRevert(DeployAgentHub.LocalSafeConfigMissing.selector);
        script.deploy(params, deployer);
    }

    function test_MainnetRejectsMockAgentId() public {
        vm.chainId(56);
        MockAgentId mock = new MockAgentId();
        DeployAgentHub.DeployParams memory params = _canonicalParams();
        params.agentId = address(mock);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.MainnetRequiresOfficialAgentId.selector, address(mock)));
        script.deploy(params, deployer);
    }

    function test_MainnetRejectsZeroAgentId() public {
        vm.chainId(56);
        DeployAgentHub.DeployParams memory params = _canonicalParams();
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
        DeployAgentHub.DeployParams memory params = _canonicalParams();
        params.agentId = OFFICIAL;
        DeployAgentHub.Deployment memory d = script.deploy(params, deployer);
        assertEq(d.mockAgentId, address(0), "mock deployed on mainnet");
        assertEq(AgentGate(d.agentGate).agentIdContract(), OFFICIAL);
    }

    function test_TestnetAcceptsMock() public {
        vm.chainId(97);
        DeployAgentHub.Deployment memory d = script.deploy(_canonicalParams(), deployer);
        assertTrue(d.mockAgentId != address(0));
        assertEq(AgentGate(d.agentGate).agentIdContract(), d.mockAgentId);
    }

    // --- run() entry point (env-driven) ---

    function _setRunEnv() internal {
        // NOTE: forge runs tests in parallel threads and vm.setEnv is
        // process-global, so EVERY env var run() reads must be set here,
        // immediately adjacent to the run() call — a var left unset can
        // be read as a sibling test's value (test_RunDeploysLocalStack
        // flaked with NoCodeAtAgentId when AGENT_ID_ADDRESS leaked in
        // from the mainnet tests). Tests that need different values
        // override them right after this call, still adjacent to run().
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(bytes32(ANVIL_KEY)));
        vm.setEnv("ADMIN_MULTISIG", vm.toString(multisig));
        vm.setEnv("QUEST_CREATOR", vm.toString(creator));
        vm.setEnv("PAUSER", vm.toString(pauser));
        vm.setEnv("VERIFIER", vm.toString(verifier));
        vm.setEnv("SAFE_SINGLETON", vm.toString(safeSingleton));
        vm.setEnv("SAFE_PROXY_CODEHASH", vm.toString(safeProxyCodehash));
        vm.setEnv("AGENT_ID_ADDRESS", "0x0000000000000000000000000000000000000000");
        vm.setEnv("CONFIRM_MAINNET_DEPLOY", "false");
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
        // Slow setup FIRST: forge runs tests in parallel threads and
        // vm.setEnv is process-global, so the env sets must sit
        // immediately adjacent to run() — any slow work between a setEnv
        // and run() lets a sibling test's values interleave (this flaked
        // with MainnetDeployNotConfirmed in the first version).
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("safe-owner-1");
        owners[1] = makeAddr("safe-owner-2");
        owners[2] = makeAddr("safe-owner-3");
        address canonicalSafe = deployCanonicalSafe(owners, 2);
        MockAgentId mock = new MockAgentId();
        vm.etch(OFFICIAL, address(mock).code);
        // Production chain: the multisig must be a canonical Safe and
        // the explicit local values must be cleared (a sibling test's
        // env would otherwise leak in and trip the production guard).
        _setRunEnv();
        vm.setEnv("AGENT_ID_ADDRESS", vm.toString(OFFICIAL));
        vm.setEnv("CONFIRM_MAINNET_DEPLOY", "true");
        vm.setEnv("ADMIN_MULTISIG", vm.toString(canonicalSafe));
        vm.setEnv("SAFE_SINGLETON", "0x0000000000000000000000000000000000000000");
        vm.setEnv("SAFE_PROXY_CODEHASH", "0x0000000000000000000000000000000000000000000000000000000000000000");
        DeployAgentHub.Deployment memory d = script.run();
        assertEq(d.mockAgentId, address(0));
        assertEq(AgentGate(d.agentGate).agentIdContract(), OFFICIAL);
    }
}
