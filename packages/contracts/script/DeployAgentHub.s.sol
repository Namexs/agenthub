// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeValidation} from "./SafeValidation.sol";
import {AgentGate} from "../src/AgentGate.sol";
import {QuestManager} from "../src/QuestManager.sol";
import {Reputation} from "../src/Reputation.sol";
import {Achievement} from "../src/Achievement.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @title DeployAgentHub
/// @notice Deploys the full AGENTHUB stack in dependency order:
/// MockAgentId (testnet/local only, when no Agent ID address is given)
/// -> AgentGate -> TimelockController -> Reputation -> Achievement
/// -> QuestManager, then wires roles and hands admin to the timelock.
/// @dev SAFETY:
/// - Mainnet (56) REQUIRES the official Agent ID address AND the explicit
///   opt-in CONFIRM_MAINNET_DEPLOY=true. Without both, the script reverts.
///   There is NO automatic mainnet deployment.
/// - The deployer ends with ZERO privileges: admin goes to the timelock
///   (2-day delay, multisig proposes + executes), operational roles go to
///   the configured addresses, and the deployer renounces admin on every
///   contract. Post-deploy assertions verify this on-chain.
/// - FINAL REMEDIATION (Phase 1): ADMIN_MULTISIG is validated as a GENUINE
///   Safe BEFORE anything is deployed (SafeValidation library): the
///   singleton must be a canonical Safe singleton (v1.3.0 / v1.4.1) and
///   the proxy's runtime codehash must be a canonical Safe proxy codehash,
///   with threshold >= 2. An EOA, a non-Safe contract, a fake "Safe", or
///   a 1-of-n "multisig" aborts the deployment. On the LOCAL chain (31337)
///   canonical Safes are not deployed, so the operator must pass the
///   expected singleton + proxy codehash explicitly (SAFE_SINGLETON /
///   SAFE_PROXY_CODEHASH); that path reverts on any other chain.
///   Run script/ValidateSafe.s.sol first for the human-readable check;
///   the check inside deploy() cannot be skipped.
/// - `run()` is the env-driven entry point for `forge script`. `deploy()`
///   is the parameterized core, unit-tested without env vars or keys.
/// @dev Usage (dry-run / simulation only — never --broadcast without a
/// reviewed decision, see docs/DEPLOYMENT_PLAN.md):
///   DEPLOYER_PRIVATE_KEY=<key> ADMIN_MULTISIG=<0x..> QUEST_CREATOR=<0x..>
///   PAUSER=<0x..> [VERIFIER=<0x..>] [AGENT_ID_ADDRESS=<0x..>]
///   [SAFE_SINGLETON=<0x..> SAFE_PROXY_CODEHASH=<0x..>]   # local (31337) only
///   forge script script/DeployAgentHub.s.sol
contract DeployAgentHub is Script {
    /// @notice Timelock delay for admin actions (matches IntegrationTest).
    uint256 public constant TIMELOCK_DELAY = 2 days;

    /// @notice The official Binance Agent ID contract (BSC mainnet).
    address public constant OFFICIAL_AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    error UnsupportedChain(uint256 chainId);
    error MainnetRequiresOfficialAgentId(address agentId);
    error MainnetDeployNotConfirmed();
    error ZeroAddress(string param);
    error WiringCheckFailed(string check);
    /// @dev FINAL REMEDIATION (Phase 1): on the local chain (31337) the
    /// operator must supply the expected Safe singleton + proxy codehash
    /// explicitly (canonical Safes are not deployed locally).
    error LocalSafeConfigMissing();
    /// @dev FINAL REMEDIATION (Phase 1): explicit Safe values are a
    /// local-only escape hatch — production chains enforce the canonical
    /// singleton + codehash sets and reject any override.
    error ExplicitSingletonNotAllowedOnProduction();

    struct DeployParams {
        /// @dev Agent ID contract to trust. address(0) on testnet/local
        /// means "deploy MockAgentId". On mainnet MUST be OFFICIAL_AGENT_ID.
        address agentId;
        /// @dev Multisig: timelock proposer/executor/admin + badge manager.
        address adminMultisig;
        /// @dev Address receiving QUEST_CREATOR_ROLE.
        address questCreator;
        /// @dev Address receiving PAUSER_ROLE (fast pause, no timelock).
        address pauser;
        /// @dev Optional first verifier (VERIFIER_ROLE). address(0) = none.
        address verifier;
        /// @dev LOCAL CHAIN (31337) ONLY: expected Safe singleton for the
        /// explicit validation path. MUST be address(0) on 56/97
        /// (canonical enforcement). MUST be non-zero on 31337.
        address safeSingleton;
        /// @dev LOCAL CHAIN (31337) ONLY: expected Safe proxy codehash for
        /// the explicit validation path. MUST be bytes32(0) on 56/97.
        /// MUST be non-zero on 31337.
        bytes32 safeProxyCodehash;
    }

    struct Deployment {
        address mockAgentId; // address(0) when a real Agent ID was given
        address agentGate;
        address timelock;
        address reputation;
        address achievement;
        address questManager;
    }

    /// @notice Env-driven entry point for `forge script`.
    function run() external returns (Deployment memory deployment) {
        if (block.chainid != 56 && block.chainid != 97 && block.chainid != 31337) {
            revert UnsupportedChain(block.chainid);
        }
        // Mainnet requires an explicit opt-in — the script never deploys
        // to mainnet "by accident" (e.g. a wrong --rpc-url).
        if (block.chainid == 56 && !vm.envOr("CONFIRM_MAINNET_DEPLOY", false)) {
            revert MainnetDeployNotConfirmed();
        }
        DeployParams memory params = DeployParams({
            agentId: vm.envOr("AGENT_ID_ADDRESS", address(0)),
            adminMultisig: vm.envAddress("ADMIN_MULTISIG"),
            questCreator: vm.envAddress("QUEST_CREATOR"),
            pauser: vm.envAddress("PAUSER"),
            verifier: vm.envOr("VERIFIER", address(0)),
            safeSingleton: vm.envOr("SAFE_SINGLETON", address(0)),
            safeProxyCodehash: vm.envOr("SAFE_PROXY_CODEHASH", bytes32(0))
        });
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // The deployer address is DERIVED from the key, never msg.sender:
        // under startBroadcast the calls originate from the key's address.
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);
        deployment = deploy(params, deployer);
        vm.stopBroadcast();
        console.log("MockAgentId:", deployment.mockAgentId);
        console.log("AgentGate:", deployment.agentGate);
        console.log("TimelockController:", deployment.timelock);
        console.log("Reputation:", deployment.reputation);
        console.log("Achievement:", deployment.achievement);
        console.log("QuestManager:", deployment.questManager);
    }

    /// @notice Parameterized deployment core (no env, no broadcast).
    /// @dev `deployer` is the address that temporarily holds admin on the
    /// three AccessControl contracts and MUST renounce it here. The caller
    /// must ensure calls originate from `deployer`: run() does this via
    /// startBroadcast; direct callers pass the address their calls
    /// originate from (e.g. address(this) for the script itself).
    function deploy(DeployParams memory params, address deployer) public returns (Deployment memory deployment) {
        if (block.chainid != 56 && block.chainid != 97 && block.chainid != 31337) {
            revert UnsupportedChain(block.chainid);
        }
        if (deployer == address(0)) revert ZeroAddress("deployer");
        if (params.adminMultisig == address(0)) revert ZeroAddress("adminMultisig");
        if (params.questCreator == address(0)) revert ZeroAddress("questCreator");
        if (params.pauser == address(0)) revert ZeroAddress("pauser");
        // FINAL REMEDIATION (Phase 1): the admin multisig must be a
        // GENUINE Safe — checked BEFORE deploying anything, so a
        // misconfigured ADMIN_MULTISIG aborts the whole deployment instead
        // of silently centralizing the project. Production chains (56/97)
        // enforce the canonical singleton + proxy codehash sets; the
        // local chain (31337) uses the explicit path with
        // operator-supplied expected values (canonical Safes are not
        // deployed locally). Explicit values are REJECTED on production
        // chains — there is no override for the canonical check.
        if (block.chainid == 31337) {
            if (params.safeSingleton == address(0) || params.safeProxyCodehash == bytes32(0)) {
                revert LocalSafeConfigMissing();
            }
            SafeValidation.validate(params.adminMultisig, params.safeSingleton, params.safeProxyCodehash);
        } else {
            if (params.safeSingleton != address(0) || params.safeProxyCodehash != bytes32(0)) {
                revert ExplicitSingletonNotAllowedOnProduction();
            }
            SafeValidation.validate(params.adminMultisig);
        }
        // Mainnet lock (defense in depth — AgentGate enforces it too):
        // the official Agent ID is the ONLY accepted identity on chain 56.
        if (block.chainid == 56 && params.agentId != OFFICIAL_AGENT_ID) {
            revert MainnetRequiresOfficialAgentId(params.agentId);
        }

        // --- 1. Identity: mock on testnet/local when no address given. ---
        address agentId = params.agentId;
        if (agentId == address(0)) {
            MockAgentId mock = new MockAgentId();
            agentId = address(mock);
            deployment.mockAgentId = agentId;
        }

        // --- 2. AgentGate (trusts exactly one Agent ID contract). ---
        AgentGate gate = new AgentGate(agentId, block.chainid);
        deployment.agentGate = address(gate);

        // --- 3. Timelock: 2-day delay, multisig proposes + executes. ---
        // No optional admin is granted (admin = address(0)): per the OZ
        // guidance the admin role "should be subsequently renounced in
        // favor of administration through timelocked proposals", so we
        // skip it entirely — DEFAULT_ADMIN_ROLE belongs to the timelock
        // itself, and timelock config changes go through proposals.
        address[] memory proposers = new address[](1);
        proposers[0] = params.adminMultisig;
        address[] memory executors = new address[](1);
        executors[0] = params.adminMultisig;
        TimelockController timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(0));
        deployment.timelock = address(timelock);

        // --- 4. Reputation + Achievement (deployer as temporary admin). ---
        Reputation reputation = new Reputation(deployer);
        Achievement achievement = new Achievement(deployer);
        deployment.reputation = address(reputation);
        deployment.achievement = address(achievement);

        // --- 5. QuestManager (deployer as temporary admin). ---
        QuestManager qm = new QuestManager(address(gate), address(reputation), address(achievement), deployer);
        deployment.questManager = address(qm);

        // --- 6. Role wiring (before handing admin to the timelock). ---
        reputation.grantRole(reputation.SCORE_SOURCE_ROLE(), address(qm));
        achievement.grantRole(achievement.ISSUER_ROLE(), address(qm));
        achievement.grantRole(achievement.BADGE_MANAGER_ROLE(), params.adminMultisig);
        qm.grantRole(qm.QUEST_CREATOR_ROLE(), params.questCreator);
        qm.grantRole(qm.PAUSER_ROLE(), params.pauser);
        if (params.verifier != address(0)) {
            qm.grantRole(qm.VERIFIER_ROLE(), params.verifier);
        }

        // --- 7. Hand admin to the timelock; the deployer renounces. ---
        reputation.grantRole(reputation.DEFAULT_ADMIN_ROLE(), address(timelock));
        achievement.grantRole(achievement.DEFAULT_ADMIN_ROLE(), address(timelock));
        qm.grantRole(qm.DEFAULT_ADMIN_ROLE(), address(timelock));
        reputation.renounceRole(reputation.DEFAULT_ADMIN_ROLE(), deployer);
        achievement.renounceRole(achievement.DEFAULT_ADMIN_ROLE(), deployer);
        qm.renounceRole(qm.DEFAULT_ADMIN_ROLE(), deployer);

        // --- 8. Post-deploy verification: revert if wiring is wrong. ---
        _verifyWiring(deployment, params, deployer);
    }

    function _verifyWiring(Deployment memory deployment, DeployParams memory params, address deployer) internal view {
        AgentGate gate = AgentGate(deployment.agentGate);
        Reputation reputation = Reputation(deployment.reputation);
        Achievement achievement = Achievement(deployment.achievement);
        QuestManager qm = QuestManager(deployment.questManager);
        TimelockController timelock = TimelockController(payable(deployment.timelock));

        // Identity wiring.
        address expectedAgentId = deployment.mockAgentId != address(0) ? deployment.mockAgentId : params.agentId;
        if (gate.agentIdContract() != expectedAgentId) revert WiringCheckFailed("gate.agentId");
        if (gate.expectedChainId() != block.chainid) revert WiringCheckFailed("gate.chainId");
        if (address(qm.gate()) != address(gate)) revert WiringCheckFailed("qm.gate");
        if (address(qm.reputation()) != address(reputation)) revert WiringCheckFailed("qm.reputation");
        if (address(qm.achievement()) != address(achievement)) revert WiringCheckFailed("qm.achievement");

        // Timelock wiring.
        if (timelock.getMinDelay() != TIMELOCK_DELAY) revert WiringCheckFailed("timelock.delay");
        if (!timelock.hasRole(timelock.PROPOSER_ROLE(), params.adminMultisig)) {
            revert WiringCheckFailed("timelock.proposer");
        }
        if (!timelock.hasRole(timelock.EXECUTOR_ROLE(), params.adminMultisig)) {
            revert WiringCheckFailed("timelock.executor");
        }
        // Self-administered: only the timelock itself holds its admin role.
        if (!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock))) {
            revert WiringCheckFailed("timelock.selfAdmin");
        }
        if (timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), params.adminMultisig)) {
            revert WiringCheckFailed("timelock.multisigAdmin");
        }

        // Admin is the timelock everywhere.
        if (!reputation.hasRole(reputation.DEFAULT_ADMIN_ROLE(), address(timelock))) {
            revert WiringCheckFailed("reputation.admin");
        }
        if (!achievement.hasRole(achievement.DEFAULT_ADMIN_ROLE(), address(timelock))) {
            revert WiringCheckFailed("achievement.admin");
        }
        if (!qm.hasRole(qm.DEFAULT_ADMIN_ROLE(), address(timelock))) {
            revert WiringCheckFailed("qm.admin");
        }

        // Operational roles went to the right addresses.
        if (!reputation.hasRole(reputation.SCORE_SOURCE_ROLE(), address(qm))) {
            revert WiringCheckFailed("reputation.scoreSource");
        }
        if (!achievement.hasRole(achievement.ISSUER_ROLE(), address(qm))) {
            revert WiringCheckFailed("achievement.issuer");
        }
        if (!achievement.hasRole(achievement.BADGE_MANAGER_ROLE(), params.adminMultisig)) {
            revert WiringCheckFailed("achievement.badgeManager");
        }
        if (!qm.hasRole(qm.QUEST_CREATOR_ROLE(), params.questCreator)) {
            revert WiringCheckFailed("qm.creator");
        }
        if (!qm.hasRole(qm.PAUSER_ROLE(), params.pauser)) {
            revert WiringCheckFailed("qm.pauser");
        }
        if (params.verifier != address(0) && !qm.hasRole(qm.VERIFIER_ROLE(), params.verifier)) {
            revert WiringCheckFailed("qm.verifier");
        }

        // NO privilege is left with the deployer (SEC-002).
        if (reputation.hasRole(reputation.DEFAULT_ADMIN_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.reputationAdmin");
        }
        if (achievement.hasRole(achievement.DEFAULT_ADMIN_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.achievementAdmin");
        }
        if (qm.hasRole(qm.DEFAULT_ADMIN_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.qmAdmin");
        }
        if (reputation.hasRole(reputation.SCORE_SOURCE_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.scoreSource");
        }
        if (achievement.hasRole(achievement.ISSUER_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.issuer");
        }
        if (achievement.hasRole(achievement.BADGE_MANAGER_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.badgeManager");
        }
        if (qm.hasRole(qm.QUEST_CREATOR_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.creator");
        }
        if (qm.hasRole(qm.PAUSER_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.pauser");
        }
        if (qm.hasRole(qm.VERIFIER_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.verifier");
        }
        if (timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer)) {
            revert WiringCheckFailed("deployer.timelockAdmin");
        }
    }
}
