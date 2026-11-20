// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Gnosis Safe interface, as needed for pre-deploy checks.
/// Real Safe contracts (v1.3.0 / v1.4.1) expose all four functions as views
/// (VERSION + getThreshold + getOwners via delegatecall into the singleton;
/// masterCopy on the proxy itself).
interface ISafe {
    function getThreshold() external view returns (uint256 threshold);
    function getOwners() external view returns (address[] memory owners);
    function masterCopy() external view returns (address singleton);
    function VERSION() external view returns (string memory version);
}

/// @title SafeValidation
/// @notice Pre-deployment validation for the ADMIN_MULTISIG address.
/// The admin multisig becomes the timelock proposer/executor and the badge
/// manager, so deploying with the wrong address (an EOA, a random contract,
/// a fake "Safe", or a 1-of-n "multisig") would silently centralize the
/// whole project. This library fails closed: any doubt aborts the deployment.
/// @dev FINAL REMEDIATION (Phase 1): the old check (getThreshold +
/// getOwners only) could be spoofed by any contract implementing two view
/// functions. The new check proves genuineness on-chain:
///   1. chainId is a supported production chain (56 / 97);
///   2. the address has code (rejects zero address and EOAs);
///   3. threshold >= 2 and threshold <= owner count;
///   4. masterCopy() is a canonical Safe singleton (v1.3.0 / v1.4.1);
///   5. the candidate's runtime codehash is a canonical Safe proxy
///      codehash — the canonical proxy bytecode does NOTHING but
///      delegatecall the singleton in slot 0, so a contract with that
///      bytecode and a canonical singleton IS a genuine Safe proxy;
///   6. VERSION() (answered through the delegatecall) is "1.3.0" or "1.4.1".
/// Steps 4+5 together close the spoofing hole: a fake contract cannot fake
/// the codehash without BEING the canonical proxy, and the canonical proxy
/// cannot lie about getThreshold/getOwners because it delegatecalls the
/// real singleton. What the check still does NOT prove: that this Safe is
/// THE TEAM'S Safe (the right owners). That is a human identity question —
/// the operator MUST confirm the address + owners out-of-band and in the
/// Safe web app before deploying (see docs/DEPLOYMENT_PLAN.md §5 and
/// agenthub-final-pretestnet/SAFE_VALIDATION_REVIEW.md).
/// @dev Canonical addresses + codehashes (verified two independent ways,
/// 2026-11-19): the official safe-deployments repo / safe-smart-account
/// CHANGELOG, AND live on-chain reads on BSC mainnet + testnet
/// (cast code + cast call VERSION(), identical bytecode on both chains).
/// Proxy codehashes were derived by creating one genuine proxy per
/// canonical factory on a BSC testnet fork — see
/// script/ProbeSafeProxy.s.sol (kept in the repo as the derivation
/// evidence). v1.4.1 and v1.3.0 proxies differ ONLY in the metadata-hash
/// suffix of their bytecode; the executable code is identical.
/// @dev Local chain (31337): canonical Safe contracts are not deployed
/// there, so the production path cannot run. The explicit-singleton
/// overload validates the same MECHANISM against operator-supplied
/// expected values (singleton + proxy codehash). It reverts on any chain
/// other than 31337, so production can never accidentally use it.
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

    /// @notice Canonical Safe v1.4.1 singleton (CREATE2, same on all chains).
    /// Source: safe-global/safe-deployments v1.4.1/safe.json + on-chain
    /// verification on BSC 56/97 (codehash 0x1fe2df85..., VERSION "1.4.1").
    address internal constant SAFE_SINGLETON_V141 = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    /// @notice Canonical Safe v1.3.0 singleton (GnosisSafe, CREATE2).
    /// Source: safe-global/safe-deployments v1.3.0/gnosis_safe.json +
    /// on-chain verification on BSC 56/97 (codehash 0xbba688fb...,
    /// VERSION "1.3.0").
    address internal constant SAFE_SINGLETON_V130 = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;

    /// @notice Runtime codehash of a genuine Safe v1.4.1 proxy (created by
    /// SafeProxyFactory 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67).
    /// Derived on a BSC testnet fork — see script/ProbeSafeProxy.s.sol.
    bytes32 internal constant SAFE_PROXY_CODEHASH_V141 =
        0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c;
    /// @notice Runtime codehash of a genuine Safe v1.3.0 proxy (created by
    /// GnosisSafeProxyFactory 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2).
    /// Derived on a BSC testnet fork — see script/ProbeSafeProxy.s.sol.
    bytes32 internal constant SAFE_PROXY_CODEHASH_V130 =
        0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000;

    /// @dev The candidate is not a usable Safe. `reason` is short and
    /// human-readable ("no code", "getThreshold failed", "getOwners failed",
    /// "masterCopy failed", "VERSION failed").
    error NotASafe(address candidate, string reason);
    /// @dev The Safe's threshold is below the minimum, or exceeds its
    /// owner count (a Safe that can never reach quorum).
    error UnsafeThreshold(address safe, uint256 threshold, uint256 ownerCount);
    /// @dev The chain is not one this validation path supports.
    error UnsupportedChain(uint256 chainId);
    /// @dev The proxy's singleton is not a trusted Safe singleton.
    error UnknownSingleton(address candidate, address singleton);
    /// @dev The proxy's runtime code is not canonical Safe proxy bytecode.
    /// This is the check that defeats masterCopy() spoofing: a fake
    /// contract can return any address from masterCopy(), but it cannot
    /// fake the codehash without being the canonical proxy.
    error UnknownProxyCodehash(address candidate, bytes32 codehash);
    /// @dev VERSION() (via the proxy's delegatecall) is not "1.3.0"/"1.4.1".
    error VersionMismatch(address candidate, string version);

    /// @notice Validate `candidate` as the admin Safe on a production chain
    /// (56 / 97) against the canonical singleton + proxy codehash sets.
    function validate(address candidate) internal view {
        if (block.chainid != 56 && block.chainid != 97) revert UnsupportedChain(block.chainid);
        _validateCommon(candidate);
        address singleton = _getMasterCopy(candidate);
        if (singleton != SAFE_SINGLETON_V141 && singleton != SAFE_SINGLETON_V130) {
            revert UnknownSingleton(candidate, singleton);
        }
        bytes32 codehash = candidate.codehash;
        if (codehash != SAFE_PROXY_CODEHASH_V141 && codehash != SAFE_PROXY_CODEHASH_V130) {
            revert UnknownProxyCodehash(candidate, codehash);
        }
        _checkVersion(candidate);
    }

    /// @notice Validate `candidate` as the admin Safe on the LOCAL chain
    /// (31337 only) against operator-supplied expected values. The
    /// mechanism is identical to the production path; only the trusted
    /// values are caller-supplied, because canonical Safe contracts are
    /// not deployed on a local chain. Reverts on any other chain, so a
    /// production deploy can never take this path.
    function validate(address candidate, address expectedSingleton, bytes32 expectedProxyCodehash) internal view {
        if (block.chainid != 31337) revert UnsupportedChain(block.chainid);
        _validateCommon(candidate);
        address singleton = _getMasterCopy(candidate);
        if (singleton != expectedSingleton) revert UnknownSingleton(candidate, singleton);
        bytes32 codehash = candidate.codehash;
        if (codehash != expectedProxyCodehash) revert UnknownProxyCodehash(candidate, codehash);
        _checkVersion(candidate);
    }

    /// @notice Shared checks: code exists, threshold in [MIN, ownerCount],
    /// owner count >= MIN. Runs before the singleton/codehash checks so a
    /// misconfigured Safe fails with the most specific reason first.
    function _validateCommon(address candidate) private view {
        // An EOA answers a staticcall with empty returndata and success —
        // so the code check MUST come first.
        if (candidate.code.length == 0) revert NotASafe(candidate, "no code");
        uint256 threshold = _getThreshold(candidate);
        address[] memory owners = _getOwners(candidate);
        if (threshold < MIN_SAFE_THRESHOLD || threshold > owners.length || owners.length < MIN_SAFE_THRESHOLD) {
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

    function _getMasterCopy(address candidate) private view returns (address singleton) {
        (bool success, bytes memory data) = candidate.staticcall(abi.encodeWithSelector(ISafe.masterCopy.selector));
        if (!success || data.length != 32) revert NotASafe(candidate, "masterCopy failed");
        assembly {
            singleton := mload(add(data, 32))
        }
    }

    /// @dev VERSION() is answered through the proxy's delegatecall, so it
    /// is the SINGLETON's version — a consistency check that the proxy
    /// actually delegates to a Safe singleton. Either supported version
    /// is accepted regardless of which canonical singleton is configured
    /// (a v1.3.0 proxy may point at a v1.4.1 singleton and vice versa —
    /// proxies are version-agnostic by design).
    function _checkVersion(address candidate) private view {
        (bool success, bytes memory data) = candidate.staticcall(abi.encodeWithSelector(ISafe.VERSION.selector));
        if (!success || data.length < 64) revert NotASafe(candidate, "VERSION failed");
        string memory version = abi.decode(data, (string));
        bytes32 versionHash = keccak256(bytes(version));
        if (versionHash != keccak256("1.4.1") && versionHash != keccak256("1.3.0")) {
            revert VersionMismatch(candidate, version);
        }
    }
}
