// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SafeValidation, ISafe} from "./SafeValidation.sol";

/// @title ValidateSafe
/// @notice Standalone pre-deploy check for the ADMIN_MULTISIG address.
/// Run BEFORE DeployAgentHub to confirm the multisig is a real Safe with
/// an adequate threshold — without deploying anything:
///   ADMIN_MULTISIG=<0x..> forge script script/ValidateSafe.s.sol
/// The same validation is enforced inside DeployAgentHub.deploy(), so this
/// script is the early, human-readable check; the deploy script is the
/// enforcement that cannot be skipped. No broadcast, no key needed.
contract ValidateSafe is Script {
    function run() external returns (uint256 threshold, address[] memory owners) {
        address safe = vm.envAddress("ADMIN_MULTISIG");
        SafeValidation.validate(safe);
        threshold = ISafe(safe).getThreshold();
        owners = ISafe(safe).getOwners();
        console.log("Safe:", safe);
        console.log("Threshold:", threshold);
        console.log("Owners:", owners.length);
        console.log("OK: ADMIN_MULTISIG is a Safe with threshold >= 2");
    }
}
