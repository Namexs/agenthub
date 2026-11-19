// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentGate} from "./interfaces/IAgentGate.sol";

/// @dev Minimal interface for the trusted Agent ID contract (ERC-721).
interface IERC721Balance {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentGate
/// @notice Single source of truth for "does this address hold a Binance Agent ID".
/// @dev Trusts exactly ONE immutable Agent ID contract address and ONE expected
/// chainId, both fixed at deploy time. Fails closed: any doubt (wrong chain,
/// zero account, external-call failure) means "not a holder".
contract AgentGate is IAgentGate {
    /// @notice The only Agent ID contract this gate trusts. Immutable.
    address public immutable agentIdContract;

    /// @notice The chain this gate was deployed for. Immutable.
    uint256 public immutable expectedChainId;

    constructor(address agentId_, uint256 expectedChainId_) {
        if (agentId_ == address(0)) revert ZeroAddress();
        if (agentId_.code.length == 0) revert NoCodeAtAgentId(agentId_);
        if (expectedChainId_ == 0) revert InvalidChainId(expectedChainId_);
        if (expectedChainId_ != block.chainid) {
            revert WrongChain(expectedChainId_, block.chainid);
        }
        agentIdContract = agentId_;
        expectedChainId = expectedChainId_;
    }

    /// @inheritdoc IAgentGate
    /// @dev Fails closed: returns false (never reverts) on a wrong chain, a
    /// zero account, or any failure of the external balanceOf call, so a
    /// misbehaving trusted contract cannot DoS integrators with a revert.
    /// @dev Uses a low-level STATICCALL with a manual length check instead
    /// of try/catch: Solidity try/catch does NOT catch ABI-decoding errors
    /// of malformed returndata (a too-short return would revert the whole
    /// call — found by test_GarbageReturnFailsClosed, see SEC-001). The
    /// staticcall additionally guarantees the trusted contract cannot change
    /// state through this call, even when invoked on-chain.
    function isAgentHolder(address account) public view returns (bool) {
        if (account == address(0)) return false;
        if (block.chainid != expectedChainId) return false;
        (bool success, bytes memory data) = agentIdContract.staticcall(
            abi.encodeWithSelector(IERC721Balance.balanceOf.selector, account)
        );
        if (!success || data.length < 32) return false;
        uint256 holderBalance;
        assembly {
            holderBalance := mload(add(data, 32))
        }
        return holderBalance > 0;
    }

    /// @inheritdoc IAgentGate
    function requireAgentHolder(address account) external view {
        _requireAgentHolder(account);
    }

    /// @inheritdoc IAgentGate
    function verify() external {
        _requireAgentHolder(msg.sender);
        emit AgentHolderVerified(msg.sender);
    }

    function _requireAgentHolder(address account) internal view {
        if (block.chainid != expectedChainId) {
            revert WrongChain(expectedChainId, block.chainid);
        }
        if (!isAgentHolder(account)) revert NotAgentHolder(account);
    }
}
