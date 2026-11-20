// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {QuestManager} from "../src/QuestManager.sol";

/// @title ProposeGrantVerifier
/// @notice Post-deployment helper (PH7-L19): prepares a
/// TimelockController proposal granting VERIFIER_ROLE on QuestManager
/// to a second verifier. R-010 requires >= 3 verifiers before the
/// first threshold-2 quest on mainnet; this script is how the second
/// (and third) verifier is added without hand-assembling calldata.
/// @dev THE GRANT GOES THROUGH THE TIMELOCK — there is no direct-grant
/// path in this script. The grant calldata is only ever executed by
/// the TimelockController itself (the QuestManager admin); the script
/// never calls QuestManager.grantRole directly. Flow:
///   1. PROPOSE — buildProposal() validates (timelock is the QM admin,
///      verifier does not already hold the role, timelock minDelay is
///      exactly 2 days) and computes the proposal: target, calldata,
///      salt, operation id, ready-at time.
///   2. SCHEDULE — the proposer (admin multisig Safe, the only
///      PROPOSER_ROLE holder) executes timelock.schedule with the
///      printed arguments via a Safe transaction. A Safe has no
///      private key, so the script cannot broadcast the schedule as
///      the Safe on a live network — run() defaults to preview-only.
///      scheduleGrant() performs the schedule when the CALLER is a
///      proposer (fork simulation with an unlocked proposer, or an
///      EOA-proposer setup via SCHEDULE=true + PROPOSER_PRIVATE_KEY).
///   3. DELAY — 2 days (the timelock minDelay). The grant is NOT
///      effective during this window; execute() reverts, and the
///      multisig can still cancel via CANCELLER_ROLE.
///   4. EXECUTE — after the delay, the executor (admin multisig)
///      executes the operation and the grant lands.
/// See script/ProposeGrantVerifier.md for the operator runbook.
/// @dev Usage (preview — nothing is sent, needs an RPC for live state):
///   TIMELOCK_ADDRESS=<0x..> QUEST_MANAGER_ADDRESS=<0x..> VERIFIER=<0x..>
///   forge script script/ProposeGrantVerifier.s.sol --rpc-url <url>
/// Schedule via a Safe transaction with the printed arguments, or —
/// only when the proposer is a key, never the Safe — with:
///   SCHEDULE=true PROPOSER_PRIVATE_KEY=<key> forge script ... --broadcast
contract ProposeGrantVerifier is Script {
    /// @notice The AGENTHUB timelock delay (matches DeployAgentHub).
    uint256 public constant TIMELOCK_DELAY = 2 days;

    error ZeroAddress(string param);
    error NoCodeAtAddress(address account, string param);
    error VerifierAlreadyHasRole(address verifier);
    error TimelockNotQuestManagerAdmin(address timelock, address questManager);
    error UnexpectedTimelockDelay(uint256 actual, uint256 expected);

    struct Proposal {
        bytes32 operationId;
        address timelock;
        address questManager;
        address verifier;
        bytes32 salt;
        uint256 delay;
        uint256 readyAt;
        bytes data;
    }

    /// @notice Env-driven entry point for `forge script`: previews the
    /// proposal and prints the operator summary. Preview-only by
    /// default — nothing is sent unless SCHEDULE=true (see header).
    function run() external returns (Proposal memory proposal) {
        address timelock = vm.envAddress("TIMELOCK_ADDRESS");
        address questManager = vm.envAddress("QUEST_MANAGER_ADDRESS");
        address verifier = vm.envAddress("VERIFIER");
        bytes32 salt = vm.envOr("PROPOSAL_SALT", bytes32(0));
        proposal = buildProposal(timelock, questManager, verifier, salt);
        _printProposal(proposal);
        // Explicit opt-in only: broadcast the schedule call from the
        // proposer key. The AGENTHUB proposer is a Safe (no key), so
        // this path is for EOA-proposer setups and fork simulations —
        // the timelock itself reverts if the key is not a proposer.
        if (vm.envOr("SCHEDULE", false)) {
            uint256 proposerKey = vm.envUint("PROPOSER_PRIVATE_KEY");
            vm.startBroadcast(proposerKey);
            scheduleGrant(timelock, questManager, verifier, salt);
            vm.stopBroadcast();
            console.log("ProposeGrantVerifier: proposal SCHEDULED (see operation id above).");
        } else {
            console.log("ProposeGrantVerifier: preview only - nothing scheduled.");
            console.log("Schedule via a Safe transaction with the arguments above,");
            console.log("or re-run with SCHEDULE=true + PROPOSER_PRIVATE_KEY (EOA proposer only).");
        }
    }

    /// @notice Builds (and validates) the grant proposal WITHOUT
    /// scheduling it: the preview the operator reviews before the
    /// Safe schedules it. A zero salt derives deterministically from
    /// the verifier address, so re-running the preview for the same
    /// verifier reproduces the same operation id.
    function buildProposal(address timelockAddr, address questManagerAddr, address verifier, bytes32 salt)
        public
        view
        returns (Proposal memory proposal)
    {
        if (verifier == address(0)) revert ZeroAddress("verifier");
        if (timelockAddr.code.length == 0) revert NoCodeAtAddress(timelockAddr, "timelock");
        if (questManagerAddr.code.length == 0) revert NoCodeAtAddress(questManagerAddr, "questManager");
        TimelockController timelock = TimelockController(payable(timelockAddr));
        QuestManager qm = QuestManager(questManagerAddr);
        if (qm.hasRole(qm.VERIFIER_ROLE(), verifier)) revert VerifierAlreadyHasRole(verifier);
        // The grant can only land if the timelock is the QM admin —
        // check it now, not after a 2-day delay.
        if (!qm.hasRole(qm.DEFAULT_ADMIN_ROLE(), timelockAddr)) {
            revert TimelockNotQuestManagerAdmin(timelockAddr, questManagerAddr);
        }
        uint256 minDelay = timelock.getMinDelay();
        if (minDelay != TIMELOCK_DELAY) revert UnexpectedTimelockDelay(minDelay, TIMELOCK_DELAY);
        if (salt == bytes32(0)) salt = keccak256(abi.encodePacked("agenthub-grant-verifier", verifier));
        bytes memory data = abi.encodeCall(IAccessControl.grantRole, (qm.VERIFIER_ROLE(), verifier));
        bytes32 operationId = timelock.hashOperation(questManagerAddr, 0, data, bytes32(0), salt);
        proposal = Proposal({
            operationId: operationId,
            timelock: timelockAddr,
            questManager: questManagerAddr,
            verifier: verifier,
            salt: salt,
            delay: TIMELOCK_DELAY,
            readyAt: block.timestamp + TIMELOCK_DELAY,
            data: data
        });
    }

    /// @notice Builds the proposal AND schedules it on the timelock
    /// with the 2-day delay. The CALLER must hold PROPOSER_ROLE on
    /// the timelock (enforced by the timelock itself — a non-proposer
    /// reverts); in production the caller is the admin multisig Safe
    /// executing this via its own transaction, or a fork simulation
    /// with the proposer impersonated. There is deliberately no
    /// direct-grant path: the grant only takes effect when the
    /// timelock executes the scheduled operation after the delay.
    function scheduleGrant(address timelockAddr, address questManagerAddr, address verifier, bytes32 salt)
        public
        returns (Proposal memory proposal)
    {
        proposal = buildProposal(timelockAddr, questManagerAddr, verifier, salt);
        TimelockController(payable(timelockAddr))
            .schedule(proposal.questManager, 0, proposal.data, bytes32(0), proposal.salt, proposal.delay);
    }

    function _printProposal(Proposal memory proposal) internal pure {
        console.log("=== Grant VERIFIER_ROLE proposal (via TimelockController) ===");
        console.log("Timelock:");
        console.log(proposal.timelock);
        console.log("QuestManager (target):");
        console.log(proposal.questManager);
        console.log("Verifier (grantee):");
        console.log(proposal.verifier);
        console.log("Operation id:");
        console.logBytes32(proposal.operationId);
        console.log("Salt:");
        console.logBytes32(proposal.salt);
        // NOTE: single-string logs only — the multi-arg console.log
        // overloads do not render in `forge script` output (verified
        // on forge 1.9.0: (string, uint) lines silently vanish).
        console.log(string.concat("Delay (seconds): ", vm.toString(proposal.delay)));
        console.log(string.concat("Ready at (unix): ", vm.toString(proposal.readyAt)));
        console.log("Calldata (grantRole):");
        console.logBytes(proposal.data);
        console.log("Schedule with: timelock.schedule(target, 0, <calldata>, 0x0, <salt>, 172800)");
        console.log("Execute after the delay with: timelock.execute(target, 0, <calldata>, 0x0, <salt>)");
    }
}
