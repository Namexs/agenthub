// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SafeValidation, ISafe} from "./SafeValidation.sol";

/// @title ValidateSafe
/// @notice Standalone pre-deploy check for the ADMIN_MULTISIG address.
/// Run BEFORE DeployAgentHub to confirm the multisig is a genuine Safe
/// with an adequate threshold — without deploying anything:
///   ADMIN_MULTISIG=<0x..> forge script script/ValidateSafe.s.sol
///       --fork-url <rpc-url>   # production chains (56 / 97)
/// The same validation is enforced inside DeployAgentHub.deploy(), so this
/// script is the early, human-readable check; the deploy script is the
/// enforcement that cannot be skipped. No broadcast, no key needed.
/// @dev FINAL REMEDIATION (Phase 1): on production chains the check now
/// verifies the singleton + proxy codehash against the canonical Safe
/// sets, not just getThreshold/getOwners. On the LOCAL chain (31337)
/// canonical Safes are not deployed, so the operator must pass the
/// expected values explicitly:
///   SAFE_SINGLETON=<0x..> SAFE_PROXY_CODEHASH=<0x..> forge script ...
/// The explicit path reverts on any chain other than 31337.
contract ValidateSafe is Script {
    /// @notice Env-driven entry point: ADMIN_MULTISIG (required),
    /// SAFE_SINGLETON + SAFE_PROXY_CODEHASH (local chain only, both or
    /// neither). Thin wrapper over runWith — see below.
    function run() external returns (uint256 threshold, address[] memory owners) {
        address safe = vm.envAddress("ADMIN_MULTISIG");
        address expectedSingleton = vm.envOr("SAFE_SINGLETON", address(0));
        bytes32 expectedProxyCodehash = vm.envOr("SAFE_PROXY_CODEHASH", bytes32(0));
        return runWith(safe, expectedSingleton, expectedProxyCodehash);
    }

    /// @notice Parameterized core (no env): the same check run() performs,
    /// testable without process-global env vars (vm.setEnv races across
    /// parallel forge test threads — see SafeValidationTest).
    /// @dev Pass expectedSingleton == address(0) AND
    /// expectedProxyCodehash == bytes32(0) for the canonical
    /// (production-chain) path; pass both for the explicit (local) path.
    /// Passing exactly one reverts.
    function runWith(address safe, address expectedSingleton, bytes32 expectedProxyCodehash)
        public
        returns (uint256 threshold, address[] memory owners)
    {
        if (expectedSingleton != address(0) || expectedProxyCodehash != bytes32(0)) {
            require(
                expectedSingleton != address(0) && expectedProxyCodehash != bytes32(0),
                "ValidateSafe: set both SAFE_SINGLETON and SAFE_PROXY_CODEHASH"
            );
            SafeValidation.validate(safe, expectedSingleton, expectedProxyCodehash);
        } else {
            SafeValidation.validate(safe);
        }
        threshold = ISafe(safe).getThreshold();
        owners = ISafe(safe).getOwners();
        console.log("Safe:", safe);
        console.log("Threshold:", threshold);
        console.log("Owners:", owners.length);
        console.log("OK: ADMIN_MULTISIG is a genuine Safe with threshold >= 2");
    }
}
