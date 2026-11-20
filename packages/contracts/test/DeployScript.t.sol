// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DeployAgentHub} from "../script/DeployAgentHub.s.sol";
import {DeployLocalTestStack} from "../script/DeployLocalTestStack.s.sol";
import {DeployMock} from "../script/DeployMock.s.sol";
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

/// @notice Test-only harness exposing the internal _verifyWiring so
/// its negative paths can be tested directly (PH7-L17): deploy()
/// always builds correct wiring, so a missing or misplaced role is
/// unreachable through the public entry point. The test deploys a
/// correct stack, tampers with the timelock roles (as the timelock
/// itself, the only admin), and asserts _verifyWiring reverts with
/// the right check name.
contract DeployAgentHubHarness is DeployAgentHub {
    function verifyWiring(
        Deployment memory deployment,
        DeployParams memory params,
        address deployer,
        address effectivePauser
    ) external view {
        _verifyWiring(deployment, params, deployer, effectivePauser);
    }
}

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
    // PHASE 8 (PH7-M03): the quest creator is a genuine Safe too — a
    // second MockSafeProxy (2-of-3, distinct owners) built from the
    // SAME singleton in setUp, so it passes the same explicit-path
    // validation as the admin multisig (same singleton + same proxy
    // codehash — all MockSafeProxy instances share one bytecode).
    address internal creator;
    address internal pauser = makeAddr("pauser");
    address internal verifier = makeAddr("verifier");
    address internal alice = makeAddr("alice");

    address internal constant OFFICIAL = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    // Anvil default test account 0 key — public, local simulation only.
    // (Phase 9.1 fix: this was ...f4f3ff80, a one-character typo that
    // derives 0x7f22... instead of anvil account 0 0xf39F... — harmless
    // in tests, which derive the deployer from this constant, but wrong
    // against a real anvil. Now matches DeployLocalTestStack.)
    uint256 internal constant ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

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
        creator = _creatorSafe(address(singleton));
        vm.warp(1_000_000);
    }

    /// @notice Build a 2-of-3 MockSafeProxy creator from `singleton_`
    /// (PH7-M03: on 31337 both Safes validate against the same explicit
    /// singleton + codehash, so the creator must share the singleton).
    function _creatorSafe(address singleton_) internal returns (address) {
        address[] memory creatorOwners = new address[](3);
        creatorOwners[0] = makeAddr("creator-owner-1");
        creatorOwners[1] = makeAddr("creator-owner-2");
        creatorOwners[2] = makeAddr("creator-owner-3");
        return address(new MockSafeProxy(singleton_, creatorOwners, 2));
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
        // PHASE 8 (PH7-M03): the creator is a second canonical Safe
        // (distinct proxy + owners) on production chains too.
        address[] memory creatorOwners = new address[](3);
        creatorOwners[0] = makeAddr("creator-owner-1");
        creatorOwners[1] = makeAddr("creator-owner-2");
        creatorOwners[2] = makeAddr("creator-owner-3");
        address canonicalCreator = deployCanonicalSafe(creatorOwners, 2);
        return DeployAgentHub.DeployParams({
            agentId: address(0),
            adminMultisig: canonicalSafe,
            questCreator: canonicalCreator,
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

        // PHASE 8 (PH7-M04): the mock is owned by the admin multisig,
        // not the deployer — the deployer keeps no mint power either.
        assertEq(MockAgentId(d.mockAgentId).owner(), multisig, "mock owner is not the multisig");
    }

    function test_DeployedStackWorksEndToEnd() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        MockAgentId mock = MockAgentId(d.mockAgentId);
        QuestManager qm = QuestManager(d.questManager);
        Reputation reputation = Reputation(d.reputation);

        // PHASE 8 (PH7-M04): the mock's owner is the admin multisig —
        // smoke-test minting goes through the Safe, not the deployer.
        vm.prank(multisig);
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
            0,
            1
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

    function test_DeployDefaultsPauserToMultisig() public {
        // FINAL REMEDIATION (Phase 2): pauser == address(0) is NOT an
        // error — PAUSER_ROLE defaults to the verified admin multisig
        // (the production default). The old behavior (revert) was
        // replaced by this default by design.
        DeployAgentHub.DeployParams memory params = _params();
        params.pauser = address(0);
        DeployAgentHub.Deployment memory d = script.deploy(params, deployer);
        QuestManager qm = QuestManager(d.questManager);
        assertTrue(qm.hasRole(qm.PAUSER_ROLE(), multisig), "multisig is not pauser by default");
        assertFalse(qm.hasRole(qm.PAUSER_ROLE(), pauser), "explicit pauser got the role by default");
    }

    function test_DeployExplicitPauserOverridesDefault() public {
        // An explicit pauser still works — it is a documented non-default
        // configuration (see docs/ROLE_MATRIX.md).
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        QuestManager qm = QuestManager(d.questManager);
        assertTrue(qm.hasRole(qm.PAUSER_ROLE(), pauser));
        assertFalse(qm.hasRole(qm.PAUSER_ROLE(), multisig));
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
        // PH7-M03: the creator Safe must be built from the SAME
        // singleton the params point at — both Safes validate against
        // the same explicit values on 31337.
        params.questCreator = _creatorSafe(address(singleton));
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

    // --- PHASE 8 (PH7-M03): QUEST_CREATOR must be a genuine Safe ---

    function test_DeployRejectsEoaCreator() public {
        address eoa = makeAddr("eoa-creator");
        DeployAgentHub.DeployParams memory params = _params();
        params.questCreator = eoa;
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.NotASafe.selector, eoa, "no code"));
        script.deploy(params, deployer);
    }

    function test_DeployRejectsNonSafeCreatorContract() public {
        // A contract WITHOUT the Safe interface: getThreshold staticcall
        // reverts (no fallback), so validation fails closed — same as
        // for the admin multisig.
        MockAgentId notSafe = new MockAgentId();
        DeployAgentHub.DeployParams memory params = _params();
        params.questCreator = address(notSafe);
        vm.expectRevert(
            abi.encodeWithSelector(SafeValidation.NotASafe.selector, address(notSafe), "getThreshold failed")
        );
        script.deploy(params, deployer);
    }

    function test_DeployRejectsThresholdOneCreatorSafe() public {
        // 1-of-3 is a single key with extra steps — below the minimum.
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("o1");
        owners[1] = makeAddr("o2");
        owners[2] = makeAddr("o3");
        MockSafe weak = new MockSafe(owners, 1);
        DeployAgentHub.DeployParams memory params = _params();
        params.questCreator = address(weak);
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.UnsafeThreshold.selector, address(weak), 1, 3));
        script.deploy(params, deployer);
    }

    function test_DeployAcceptsDistinctCreatorSafe() public {
        // A creator Safe DISTINCT from the admin multisig (different
        // owners, 3-of-3) deploys fine and receives the creator role.
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("c1");
        owners[1] = makeAddr("c2");
        owners[2] = makeAddr("c3");
        MockSafeProxy strictCreator = new MockSafeProxy(safeSingleton, owners, 3);
        DeployAgentHub.DeployParams memory params = _params();
        params.questCreator = address(strictCreator);
        DeployAgentHub.Deployment memory d = script.deploy(params, deployer);
        QuestManager qm = QuestManager(d.questManager);
        assertTrue(qm.hasRole(qm.QUEST_CREATOR_ROLE(), address(strictCreator)));
        assertFalse(qm.hasRole(qm.QUEST_CREATOR_ROLE(), multisig));
    }

    // --- PHASE 9 (Workstream 2): admin and creator Safes must DIFFER ---
    // The checklist (§1 item 4) and DEPLOYMENT_PLAN.md require the
    // creator Safe to be DISTINCT from the admin multisig, but before
    // Phase 9 nothing enforced it: the same Safe passed both
    // validations and the deploy succeeded, silently collapsing the
    // separation of duties M03 was meant to create (one compromised
    // Safe owner set would control both admin and quest creation).
    // deploy() now reverts with AdminAndCreatorMustDiffer.

    function test_DeployRejectsSameSafeForAdminAndCreator() public {
        DeployAgentHub.DeployParams memory params = _params();
        params.questCreator = multisig; // same Safe as adminMultisig
        vm.expectRevert(DeployAgentHub.AdminAndCreatorMustDiffer.selector);
        script.deploy(params, deployer);
    }

    function test_TestnetRejectsSameSafeForAdminAndCreator() public {
        // Canonical path (chain 97): the distinctness check is
        // chain-agnostic (it runs before the Safe validations), so the
        // same genuine canonical Safe for both roles reverts here too.
        vm.chainId(97);
        DeployAgentHub.DeployParams memory params = _canonicalParams();
        params.questCreator = params.adminMultisig;
        vm.expectRevert(DeployAgentHub.AdminAndCreatorMustDiffer.selector);
        script.deploy(params, deployer);
    }

    function test_TestnetRejectsEoaCreator() public {
        // Canonical path (chain 97): an EOA creator reverts even with
        // a genuine canonical admin Safe.
        vm.chainId(97);
        DeployAgentHub.DeployParams memory params = _canonicalParams();
        address eoa = makeAddr("eoa-creator-97");
        params.questCreator = eoa;
        vm.expectRevert(abi.encodeWithSelector(SafeValidation.NotASafe.selector, eoa, "no code"));
        script.deploy(params, deployer);
    }

    // --- PHASE 8 (PH7-M06): DeployLocalTestStack is Anvil-only ---

    function test_LocalTestStackRejectsTestnetChain() public {
        DeployLocalTestStack stack = new DeployLocalTestStack();
        vm.chainId(97);
        vm.expectRevert("DeployLocalTestStack: local Anvil only");
        stack.run();
    }

    function test_LocalTestStackRejectsMainnetChain() public {
        DeployLocalTestStack stack = new DeployLocalTestStack();
        vm.chainId(56);
        vm.expectRevert("DeployLocalTestStack: local Anvil only");
        stack.run();
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

    // --- PHASE 9.1 (PH7-L17): _verifyWiring checks CANCELLER_ROLE ---
    // ROLE_MATRIX.md promises Timelock CANCELLER_ROLE to the admin
    // multisig (OZ grants it to every proposer in the constructor),
    // but _verifyWiring never asserted it. The positive test checks
    // the deployed wiring; the two negative tests tamper with the
    // timelock roles and assert _verifyWiring reverts with the right
    // check name (via the harness above — deploy() always builds
    // correct wiring, so the failure modes are unreachable directly).

    function test_CancellerRoleHeldByMultisig() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        TimelockController timelock = TimelockController(payable(d.timelock));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), multisig), "multisig lacks CANCELLER_ROLE");
        assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), deployer), "deployer holds CANCELLER_ROLE");
        assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), creator), "creator holds CANCELLER_ROLE");
        assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), pauser), "pauser holds CANCELLER_ROLE");
        assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), verifier), "verifier holds CANCELLER_ROLE");
    }

    function test_VerifyWiringRevertsWhenCancellerMissing() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        DeployAgentHubHarness harness = new DeployAgentHubHarness();
        TimelockController timelock = TimelockController(payable(d.timelock));
        // Hoist before prank: the role getter IS a call and would
        // consume the prank (same lesson as IntegrationTest).
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        // Tamper: the timelock itself (its only admin) revokes the
        // multisig's canceller role.
        vm.prank(d.timelock);
        timelock.revokeRole(cancellerRole, multisig);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.WiringCheckFailed.selector, "timelock.canceller"));
        harness.verifyWiring(d, _params(), deployer, pauser);
    }

    function test_VerifyWiringRevertsWhenDeployerHoldsCanceller() public {
        DeployAgentHub.Deployment memory d = script.deploy(_params(), deployer);
        DeployAgentHubHarness harness = new DeployAgentHubHarness();
        TimelockController timelock = TimelockController(payable(d.timelock));
        // Hoist before prank: the role getter IS a call and would
        // consume the prank (same lesson as IntegrationTest).
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        // Tamper: the deployer is granted the canceller role — the
        // deployer must keep NO privilege of any kind.
        vm.prank(d.timelock);
        timelock.grantRole(cancellerRole, deployer);
        vm.expectRevert(abi.encodeWithSelector(DeployAgentHub.WiringCheckFailed.selector, "deployer.canceller"));
        harness.verifyWiring(d, _params(), deployer, pauser);
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
        vm.setEnv("CONFIRM_TESTNET_DEPLOY", "false");
        // PHASE 9.1 (PH7-L18): run() writes the deployment artifact by
        // default — tests opt out, or the mainnet/testnet scenarios
        // below would write fake 56/97 deployment records. The
        // artifact format is covered by DeploymentArtifactTest.
        vm.setEnv("WRITE_DEPLOYMENT_ARTIFACT", "false");
    }

    /// @notice The nine env-driven run() scenarios in ONE test, run
    /// sequentially. This is deliberate, not laziness: forge runs tests
    /// in parallel threads and vm.setEnv is process-global, so separate
    /// run() tests with CONFLICTING env values flaked against
    /// each other (observed: NoCodeAtAgentId from a leaked
    /// AGENT_ID_ADDRESS, MainnetDeployNotConfirmed from a leaked
    /// CONFIRM_MAINNET_DEPLOY, LocalSafeConfigMissing from leaked
    /// SAFE_* values). Inside one test there is no interleaving — every
    /// env set sits immediately before its run() call. Scenarios (1)–(6)
    /// cover DeployAgentHub.run(); (7)–(9) cover DeployMock.run()
    /// (PHASE 9: the mock script gained the same testnet guard).
    function test_RunEnvDrivenPaths() public {
        // (1) Local deploy via run(): mock Agent ID is deployed, the
        // broadcast deployer (Anvil account 0) keeps nothing.
        _setRunEnv();
        DeployAgentHub.Deployment memory dLocal = script.run();
        assertTrue(dLocal.mockAgentId != address(0), "(1) mock not deployed");
        assertTrue(dLocal.questManager != address(0), "(1) no quest manager");
        address anvilDeployer = vm.addr(ANVIL_KEY);
        QuestManager qmLocal = QuestManager(dLocal.questManager);
        assertFalse(qmLocal.hasRole(qmLocal.DEFAULT_ADMIN_ROLE(), anvilDeployer), "(1) deployer kept admin");
        assertFalse(qmLocal.hasRole(qmLocal.VERIFIER_ROLE(), anvilDeployer), "(1) deployer kept verifier");
        assertTrue(qmLocal.hasRole(qmLocal.VERIFIER_ROLE(), verifier), "(1) verifier role missing");
        // PH7-M04: the mock is owned by the multisig, not the deployer.
        assertEq(MockAgentId(dLocal.mockAgentId).owner(), multisig, "(1) mock owner is not the multisig");

        // (2) FINAL REMEDIATION (Phase 2): PAUSER unset (zero) in run()
        // → PAUSER_ROLE defaults to the verified admin multisig.
        _setRunEnv();
        vm.setEnv("PAUSER", "0x0000000000000000000000000000000000000000");
        DeployAgentHub.Deployment memory dDefault = script.run();
        QuestManager qmDefault = QuestManager(dDefault.questManager);
        assertTrue(qmDefault.hasRole(qmDefault.PAUSER_ROLE(), multisig), "(2) multisig is not default pauser");
        assertFalse(qmDefault.hasRole(qmDefault.PAUSER_ROLE(), pauser), "(2) explicit pauser got the role");

        // (3) Mainnet without confirmation → reverts (never deploys).
        vm.chainId(56);
        _setRunEnv();
        vm.setEnv("AGENT_ID_ADDRESS", vm.toString(OFFICIAL));
        vm.setEnv("CONFIRM_MAINNET_DEPLOY", "false");
        vm.expectRevert(DeployAgentHub.MainnetDeployNotConfirmed.selector);
        script.run();

        // (4) Mainnet with confirmation → deploys with the official
        // Agent ID. Production chain: the multisig must be a canonical
        // Safe and the explicit local values must be cleared.
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("safe-owner-1");
        owners[1] = makeAddr("safe-owner-2");
        owners[2] = makeAddr("safe-owner-3");
        address canonicalSafe = deployCanonicalSafe(owners, 2);
        // PH7-M03: the creator must be a canonical Safe on chain 56 too.
        address[] memory creatorOwners = new address[](3);
        creatorOwners[0] = makeAddr("creator-owner-1");
        creatorOwners[1] = makeAddr("creator-owner-2");
        creatorOwners[2] = makeAddr("creator-owner-3");
        address canonicalCreator = deployCanonicalSafe(creatorOwners, 2);
        MockAgentId mock = new MockAgentId();
        vm.etch(OFFICIAL, address(mock).code);
        _setRunEnv();
        vm.setEnv("AGENT_ID_ADDRESS", vm.toString(OFFICIAL));
        vm.setEnv("CONFIRM_MAINNET_DEPLOY", "true");
        vm.setEnv("ADMIN_MULTISIG", vm.toString(canonicalSafe));
        vm.setEnv("QUEST_CREATOR", vm.toString(canonicalCreator));
        vm.setEnv("SAFE_SINGLETON", "0x0000000000000000000000000000000000000000");
        vm.setEnv("SAFE_PROXY_CODEHASH", "0x0000000000000000000000000000000000000000000000000000000000000000");
        DeployAgentHub.Deployment memory dMainnet = script.run();
        assertEq(dMainnet.mockAgentId, address(0), "(4) mock deployed on mainnet");
        assertEq(AgentGate(dMainnet.agentGate).agentIdContract(), OFFICIAL, "(4) wrong Agent ID");

        // (5) PHASE 8 (PH7-M05): testnet without confirmation → reverts
        // before any deployment, even with a genuine canonical Safe.
        vm.chainId(97);
        address[] memory owners97 = new address[](3);
        owners97[0] = makeAddr("safe-owner-1");
        owners97[1] = makeAddr("safe-owner-2");
        owners97[2] = makeAddr("safe-owner-3");
        address canonicalSafe97 = deployCanonicalSafe(owners97, 2);
        address[] memory creatorOwners97 = new address[](3);
        creatorOwners97[0] = makeAddr("creator-owner-1");
        creatorOwners97[1] = makeAddr("creator-owner-2");
        creatorOwners97[2] = makeAddr("creator-owner-3");
        address canonicalCreator97 = deployCanonicalSafe(creatorOwners97, 2);
        _setRunEnv();
        vm.setEnv("AGENT_ID_ADDRESS", "0x0000000000000000000000000000000000000000");
        vm.setEnv("CONFIRM_TESTNET_DEPLOY", "false");
        vm.setEnv("ADMIN_MULTISIG", vm.toString(canonicalSafe97));
        vm.setEnv("QUEST_CREATOR", vm.toString(canonicalCreator97));
        vm.setEnv("SAFE_SINGLETON", "0x0000000000000000000000000000000000000000");
        vm.setEnv("SAFE_PROXY_CODEHASH", "0x0000000000000000000000000000000000000000000000000000000000000000");
        vm.expectRevert(DeployAgentHub.TestnetDeployNotConfirmed.selector);
        script.run();

        // (6) Testnet with confirmation → deploys with a mock Agent ID
        // owned by the multisig (PH7-M04).
        _setRunEnv();
        vm.setEnv("AGENT_ID_ADDRESS", "0x0000000000000000000000000000000000000000");
        vm.setEnv("CONFIRM_TESTNET_DEPLOY", "true");
        vm.setEnv("ADMIN_MULTISIG", vm.toString(canonicalSafe97));
        vm.setEnv("QUEST_CREATOR", vm.toString(canonicalCreator97));
        vm.setEnv("SAFE_SINGLETON", "0x0000000000000000000000000000000000000000");
        vm.setEnv("SAFE_PROXY_CODEHASH", "0x0000000000000000000000000000000000000000000000000000000000000000");
        DeployAgentHub.Deployment memory dTestnet = script.run();
        assertTrue(dTestnet.mockAgentId != address(0), "(6) mock not deployed");
        assertEq(AgentGate(dTestnet.agentGate).agentIdContract(), dTestnet.mockAgentId, "(6) wrong Agent ID");
        assertEq(MockAgentId(dTestnet.mockAgentId).owner(), canonicalSafe97, "(6) mock owner is not the multisig");

        // (7) PHASE 9 (Workstream 2): DeployMock on testnet without
        // confirmation → reverts (the mock script had NO guard before
        // Phase 9 — it was an unguarded broadcast path to chain 97).
        // Chain is still 97 from scenario (6).
        DeployMock mockScript = new DeployMock();
        _setRunEnv();
        vm.setEnv("CONFIRM_TESTNET_DEPLOY", "false");
        vm.expectRevert(DeployMock.TestnetDeployNotConfirmed.selector);
        mockScript.run();

        // (8) DeployMock on testnet with confirmation → deploys; the
        // mock is owned by the broadcast deployer (Anvil account 0
        // here — on testnet the operator owns it until it is handed
        // over; DeployAgentHub's own mock goes to the multisig).
        _setRunEnv();
        vm.setEnv("CONFIRM_TESTNET_DEPLOY", "true");
        MockAgentId standaloneMock = mockScript.run();
        assertTrue(address(standaloneMock) != address(0), "(8) mock not deployed");
        assertEq(standaloneMock.owner(), anvilDeployer, "(8) mock owner is not the deployer");

        // (9) DeployMock on local Anvil without confirmation → deploys
        // (local chain is exempt from the guard, like DeployAgentHub).
        vm.chainId(31337);
        _setRunEnv();
        vm.setEnv("CONFIRM_TESTNET_DEPLOY", "false");
        MockAgentId localMock = mockScript.run();
        assertTrue(address(localMock) != address(0), "(9) local mock not deployed");
    }
}
