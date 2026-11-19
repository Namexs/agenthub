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
/// @dev TEMUAN 2 (remediation): on BSC mainnet (chainId 56) the constructor
/// enforces the OFFICIAL Agent ID address on-chain — a misconfigured mainnet
/// deploy can no longer silently trust a fake NFT contract. Testnet (97) and
/// local (31337) accept any contract (MockAgentId). Other chains are rejected.
contract AgentGate is IAgentGate {
    /// @notice The official Binance Agent ID contract on BSC mainnet (EIP-55
    /// checksummed; verified with `cast --to-checksum-address`).
    address public constant OFFICIAL_AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    /// @notice BSC mainnet — only OFFICIAL_AGENT_ID is trusted here.
    uint256 public constant BSC_MAINNET_CHAIN_ID = 56;
    /// @notice BSC testnet — MockAgentId is allowed here.
    uint256 public constant BSC_TESTNET_CHAIN_ID = 97;
    /// @notice Local Anvil — any mock is allowed here.
    uint256 public constant LOCAL_CHAIN_ID = 31337;

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
        // Chain allowlist (mirrors the frontend env allowlist, M5): only
        // BSC mainnet, BSC testnet, and local Anvil are supported.
        if (
            expectedChainId_ != BSC_MAINNET_CHAIN_ID && expectedChainId_ != BSC_TESTNET_CHAIN_ID
                && expectedChainId_ != LOCAL_CHAIN_ID
        ) {
            revert UnsupportedChain(expectedChainId_);
        }
        // Mainnet lock: the official Agent ID is the ONLY trusted identity
        // on chain 56. A fake ERC-721 — even one that behaves correctly —
        // is rejected at deploy time, before it can ever gate access.
        if (expectedChainId_ == BSC_MAINNET_CHAIN_ID && agentId_ != OFFICIAL_AGENT_ID) {
            revert UnofficialAgentId(agentId_, expectedChainId_);
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
        (bool success, bytes memory data) =
            agentIdContract.staticcall(abi.encodeWithSelector(IERC721Balance.balanceOf.selector, account));
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
