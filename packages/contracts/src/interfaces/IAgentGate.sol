// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentGate — Step 1 of the AGENTHUB contract build order.
/// @notice Verifies Binance Agent ID ownership against the OFFICIAL Agent ID
/// contract. Agent ID is an ERC-721 soulbound token; ownership is proven by
/// `balanceOf(account) > 0` on the official contract only.
/// @dev Production: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f (BSC mainnet, chainId 56).
/// Local/testnet: MockAgentId (src/mocks/MockAgentId.sol) — the official
/// contract is NOT deployed on testnet. The implementation MUST NOT accept an
/// arbitrary NFT contract as an Agent ID.
interface IAgentGate {
    error NotAgentHolder(address account);
    error WrongChain(uint256 expected, uint256 actual);
    error ZeroAddress();

    /// @notice Emitted when an account's Agent ID ownership is verified on-chain.
    event AgentHolderVerified(address indexed account);

    /// @return agentId The Agent ID contract address this gate trusts.
    function agentIdContract() external view returns (address agentId);

    /// @return chainId The chainId this gate expects (56 mainnet / 97 testnet / 31337 local).
    function expectedChainId() external view returns (uint256 chainId);

    /// @notice True when `account` holds at least one Agent ID on the trusted contract.
    function isAgentHolder(address account) external view returns (bool);

    /// @notice Reverts with NotAgentHolder unless `account` holds an Agent ID.
    function requireAgentHolder(address account) external view;
}
