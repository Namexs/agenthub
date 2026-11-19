// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAchievement — Step 4 of the AGENTHUB contract build order.
/// @notice Soulbound (non-transferable) achievement badges, ERC-721.
/// Badges are issued only by authorized sources (QuestManager) after a
/// validated completion. Anyone can verify a badge on-chain via hasBadge /
/// ownerOf — no off-chain trust required.
interface IAchievement {
    error BadgeNotDefined(uint256 badgeId);
    error AlreadyHasBadge(address account, uint256 badgeId);
    error UnauthorizedIssuer(address caller);
    /// @dev Thrown by any transfer/approval attempt — badges are soulbound.
    error Soulbound();

    event BadgeDefined(uint256 indexed badgeId, string name, string tokenURI);
    event BadgeIssued(address indexed account, uint256 indexed badgeId, uint256 indexed tokenId);

    /// @notice Define a badge type (admin). Badge ids are namespaced per deployment.
    function defineBadge(uint256 badgeId, string calldata name, string calldata tokenURI) external;

    /// @notice Issue a badge to `account`. Only authorized issuer. Returns tokenId.
    function issue(address account, uint256 badgeId) external returns (uint256 tokenId);

    /// @return True when `account` holds the badge.
    function hasBadge(address account, uint256 badgeId) external view returns (bool);

    /// @return badgeId The badgeId a tokenId represents.
    function badgeOf(uint256 tokenId) external view returns (uint256 badgeId);
}
