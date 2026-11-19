// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Gnosis Safe stand-in for tests: configurable owners +
/// threshold, exposing exactly the two view functions SafeValidation
/// checks (getThreshold / getOwners). It is NOT a real Safe — it cannot
/// execute transactions — but that is irrelevant here: the deploy script
/// only reads its threshold and owners.
contract MockSafe {
    address[] internal _owners;
    uint256 internal _threshold;

    constructor(address[] memory owners_, uint256 threshold_) {
        _owners = owners_;
        _threshold = threshold_;
    }

    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }
}
