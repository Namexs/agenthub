// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Gnosis Safe interface, as needed for pre-deploy checks.
/// Real Safe contracts (v1.3.0 / v1.4.1) expose both functions as views.
interface ISafe {
    function getThreshold() external view returns (uint256 threshold);
    function getOwners() external view returns (address[] memory owners);
}

/// @title SafeValidation
/// @notice Pre-deployment validation for the ADMIN_MULTISIG address.
/// The admin multisig becomes the timelock proposer/executor and the badge
/// manager, so deploying with the wrong address (an EOA, a random contract,
/// or a 1-of-n "multisig") would silently centralize the whole project.
/// This library fails closed: any doubt aborts the deployment.
/// @dev What the check proves: the address is a contract exposing the Safe
/// `getThreshold`/`getOwners` interface, with threshold >= 2 and threshold
/// <= owner count. What it does NOT prove: that the contract is a genuine
/// Safe deployed by the official factory (a contract could implement the
/// same two functions). The operator MUST also verify the Safe in the Safe
/// web app before deploying (see docs/DEPLOYMENT_PLAN.md) — the on-chain
/// check is the last line of defense, not the only one.
/// @dev Implementation notes: low-level staticcall + returndata checks,
/// mirroring AgentGate's SEC-001 fail-closed pattern — a plain interface
/// call would NOT catch malformed returndata (ABI-decoding errors are not
/// caught by try/catch). For getOwners the returndata is length-checked
/// (>= 64 bytes: offset + length words) before abi.decode; a malicious
/// offset inside an otherwise well-formed blob still reverts the decode,
/// which is the safe outcome in a deploy script (deployment aborts).
library SafeValidation {
    /// @notice Minimum Safe threshold for AGENTHUB deployments. A
    /// "multisig" with threshold 1 is a single key with extra steps — it
    /// defeats the entire timelock + multisig admin model. Production
    /// minimum is 2-of-n; 2-of-3 is the recommended testnet setup.
    uint256 internal constant MIN_SAFE_THRESHOLD = 2;

    /// @dev The candidate is not a usable Safe. `reason` is short and
    /// human-readable ("no code", "getThreshold failed", "getOwners failed").
    error NotASafe(address candidate, string reason);
    /// @dev The Safe's threshold is below the minimum, or exceeds its
    /// owner count (a Safe that can never reach quorum).
    error UnsafeThreshold(address safe, uint256 threshold, uint256 ownerCount);

    /// @notice Validate `candidate` as the admin Safe (minimum threshold 2).
    function validate(address candidate) internal view {
        validate(candidate, MIN_SAFE_THRESHOLD);
    }

    /// @notice Validate `candidate` as the admin Safe with an explicit
    /// minimum threshold (used by tests; production uses the default).
    function validate(address candidate, uint256 minThreshold) internal view {
        // An EOA answers a staticcall with empty returndata and success —
        // so the code check MUST come first.
        if (candidate.code.length == 0) revert NotASafe(candidate, "no code");
        uint256 threshold = _getThreshold(candidate);
        address[] memory owners = _getOwners(candidate);
        if (threshold < minThreshold || threshold > owners.length || owners.length < minThreshold) {
            revert UnsafeThreshold(candidate, threshold, owners.length);
        }
    }

    function _getThreshold(address candidate) private view returns (uint256 threshold) {
        (bool success, bytes memory data) = candidate.staticcall(abi.encodeWithSelector(ISafe.getThreshold.selector));
        if (!success || data.length != 32) revert NotASafe(candidate, "getThreshold failed");
        assembly {
            threshold := mload(add(data, 32))
        }
    }

    function _getOwners(address candidate) private view returns (address[] memory owners) {
        (bool success, bytes memory data) = candidate.staticcall(abi.encodeWithSelector(ISafe.getOwners.selector));
        if (!success || data.length < 64) revert NotASafe(candidate, "getOwners failed");
        owners = abi.decode(data, (address[]));
    }
}
