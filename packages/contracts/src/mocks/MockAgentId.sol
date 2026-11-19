// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockAgentId
/// @notice LOCAL / TESTNET ONLY. Stand-in for the official Binance Agent ID
/// contract, which is NOT deployed on BSC testnet or local chains.
/// @dev Mirrors the official token's soulbound behaviour (transfers blocked)
/// so integration tests exercise the same assumptions as production.
/// Production MUST use 0x60b9262456de011f7d15a54cdd8c48baaa8b022f on BSC
/// mainnet (chainId 56) — never deploy this mock to mainnet.
contract MockAgentId is ERC721, Ownable {
    error Soulbound();

    uint256 private _nextTokenId = 1;

    constructor() ERC721("Mock Agent ID", "MOCKAI") Ownable(msg.sender) {}

    /// @notice Mint one mock Agent ID to `to`. Owner-only (test harness).
    function mint(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    /// @notice Soulbound: only mint (from == 0) and burn (to == 0) allowed.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }
}
