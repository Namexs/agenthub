// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQuestValidator} from "../interfaces/IQuestValidator.sol";

/// @dev Minimal interface for the validated token (ERC-20).
interface IERC20Balance {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title TokenBalanceValidator
/// @notice Reference IQuestValidator: the completer must hold at least
/// `threshold` of ERC-20 `token` at completion time.
/// @dev Fail-closed: any failure of the balanceOf call (revert, malformed
/// returndata) is treated as "not valid". Uses a low-level staticcall with
/// a length check, mirroring AgentGate's SEC-001 fix — a try/catch would
/// NOT catch ABI-decoding errors of malformed returndata.
contract TokenBalanceValidator is IQuestValidator {
    /// @notice The token whose balance is checked. Immutable.
    address public immutable token;
    /// @notice Minimum balance (in the token's smallest unit). Immutable.
    uint256 public immutable threshold;

    error ZeroAddress();
    error NoCodeAtToken(address token);

    constructor(address token_, uint256 threshold_) {
        if (token_ == address(0)) revert ZeroAddress();
        if (token_.code.length == 0) revert NoCodeAtToken(token_);
        token = token_;
        threshold = threshold_;
    }

    /// @inheritdoc IQuestValidator
    /// @dev questId is ignored: the condition is a balance check, identical
    /// for every quest that uses this validator instance. Deploy one
    /// validator per (token, threshold) pair.
    function validate(
        address account,
        uint256 /* questId */
    )
        external
        view
        returns (bool)
    {
        if (account == address(0)) return false;
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Balance.balanceOf.selector, account));
        if (!success || data.length < 32) return false;
        uint256 holderBalance;
        assembly {
            holderBalance := mload(add(data, 32))
        }
        return holderBalance >= threshold;
    }
}
