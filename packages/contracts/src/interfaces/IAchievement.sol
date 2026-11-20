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
    error ZeroAddress();
    error InvalidBadgeId();
    error InvalidBadgeMetadata();
    error BadgeAlreadyDefined(uint256 badgeId);

    event BadgeDefined(uint256 indexed badgeId, string name, string tokenURI);
    event BadgeIssued(address indexed account, uint256 indexed badgeId, uint256 indexed tokenId);
    /// @notice PHASE 8 (PH7-M02): the high-value classification of a
    /// badge changed. QuestManager reads this flag at quest creation
    /// to enforce the threshold-2 policy for high-value badges.
    event BadgeHighValueSet(uint256 indexed badgeId, bool highValue);

    /// @notice Define a badge type (admin). Badge ids are namespaced per deployment.
    function defineBadge(uint256 badgeId, string calldata name, string calldata tokenURI) external;

    /// @notice PHASE 8 (PH7-M02): classify a badge as high-value (or
    /// clear the classification). BADGE_MANAGER_ROLE only; the badge
    /// must already be defined (BadgeNotDefined otherwise).
    /// @dev Deliberately a separate mutable setter, NOT a defineBadge
    /// parameter: a badge's real-world value is a policy classification
    /// that can change over its lifetime (a badge may gain real-world
    /// utility — event access, a future airdrop — long after it was
    /// defined), and badges defined before this feature existed must
    /// be classifiable without redefining them. The flag is read only
    /// at quest creation: flipping it never changes a live quest's
    /// threshold (thresholds are immutable), so a badge flagged
    /// high-value later does not retroactively brick existing
    /// threshold-1 quests — the admin deactivates + recreates those
    /// if the policy demands it.
    function setBadgeHighValue(uint256 badgeId, bool highValue) external;

    /// @notice PHASE 8 (PH7-M02): whether `badgeId` is classified
    /// high-value. Returns false for badgeId 0 and for undefined
    /// badges — never reverts — so QuestManager can call it after its
    /// own isBadgeDefined check without a second failure mode.
    function isBadgeHighValue(uint256 badgeId) external view returns (bool highValue);

    /// @notice Issue a badge to `account`. Only authorized issuer. Returns tokenId.
    function issue(address account, uint256 badgeId) external returns (uint256 tokenId);

    /// @return defined True when `badgeId` was defined via defineBadge.
    /// (Review R5: QuestManager validates badge existence at creation time.)
    function isBadgeDefined(uint256 badgeId) external view returns (bool defined);

    /// @return True when `account` holds the badge.
    function hasBadge(address account, uint256 badgeId) external view returns (bool);

    /// @return badgeId The badgeId a tokenId represents.
    function badgeOf(uint256 tokenId) external view returns (uint256 badgeId);
}
