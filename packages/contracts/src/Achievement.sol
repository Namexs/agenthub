// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAchievement} from "./interfaces/IAchievement.sol";

/// @title Achievement
/// @notice Soulbound (non-transferable) ERC-721 achievement badges.
/// @dev Security properties:
/// - Issuance only via ISSUER_ROLE (the QuestManager contract).
/// - One badge per (account, badgeId); duplicates revert.
/// - Transfers revert (_update) AND approvals revert (approve,
///   setApprovalForAll) — soulbound by construction, not by convention.
/// - Uses _mint, NOT _safeMint: no onERC721Received callback, so there is no
///   reentrancy surface at mint time. Acceptable because badges are soulbound
///   and ownership is verifiable via ownerOf regardless of receiver code.
/// - issue() is additionally nonReentrant (defense in depth).
contract Achievement is IAchievement, ERC721, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant BADGE_MANAGER_ROLE = keccak256("BADGE_MANAGER_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    struct Badge {
        string name;
        string tokenURI;
        bool defined;
        /// @dev PHASE 8 (PH7-M02): high-value classification — the badge
        /// unlocks real-world value (event access, discounts, a future
        /// airdrop). QuestManager enforces threshold ≥ 2 for Attested
        /// quests carrying a high-value badge. Set via
        /// setBadgeHighValue, not defineBadge (see IAchievement).
        bool highValue;
    }

    mapping(uint256 => Badge) private _badges;
    mapping(uint256 => uint256) private _tokenBadge;
    mapping(address => mapping(uint256 => bool)) private _hasBadge;
    uint256 private _nextTokenId = 1;

    constructor(address admin_) ERC721("AGENTHUB Achievement", "AGH-ACH") {
        if (admin_ == address(0)) revert ZeroAddress();
        // Least privilege: the constructor grants ONLY DEFAULT_ADMIN_ROLE.
        // BADGE_MANAGER_ROLE MUST be granted explicitly during setup —
        // see QuestManager for the retained-privilege rationale (SEC-002).
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @inheritdoc IAchievement
    function defineBadge(uint256 badgeId, string calldata name_, string calldata uri)
        external
        onlyRole(BADGE_MANAGER_ROLE)
    {
        if (badgeId == 0) revert InvalidBadgeId();
        if (_badges[badgeId].defined) revert BadgeAlreadyDefined(badgeId);
        if (bytes(name_).length == 0) revert InvalidBadgeMetadata();
        _badges[badgeId] = Badge({name: name_, tokenURI: uri, defined: true, highValue: false});
        emit BadgeDefined(badgeId, name_, uri);
    }

    /// @inheritdoc IAchievement
    function setBadgeHighValue(uint256 badgeId, bool highValue) external onlyRole(BADGE_MANAGER_ROLE) {
        if (!_badges[badgeId].defined) revert BadgeNotDefined(badgeId);
        _badges[badgeId].highValue = highValue;
        emit BadgeHighValueSet(badgeId, highValue);
    }

    /// @inheritdoc IAchievement
    function isBadgeHighValue(uint256 badgeId) external view returns (bool) {
        // No revert for badgeId 0 / undefined: QuestManager calls this
        // after its own isBadgeDefined check, and a missing badge is
        // simply not high-value.
        return _badges[badgeId].highValue;
    }

    /// @inheritdoc IAchievement
    function isBadgeDefined(uint256 badgeId) external view returns (bool defined) {
        return _badges[badgeId].defined;
    }

    /// @inheritdoc IAchievement
    function issue(address account, uint256 badgeId)
        external
        nonReentrant
        whenNotPaused
        onlyRole(ISSUER_ROLE)
        returns (uint256 tokenId)
    {
        if (account == address(0)) revert ZeroAddress();
        if (!_badges[badgeId].defined) revert BadgeNotDefined(badgeId);
        if (_hasBadge[account][badgeId]) revert AlreadyHasBadge(account, badgeId);
        tokenId = _nextTokenId++;
        _hasBadge[account][badgeId] = true;
        _tokenBadge[tokenId] = badgeId;
        // _mint (not _safeMint): no external callback — see contract docs.
        _mint(account, tokenId);
        emit BadgeIssued(account, badgeId, tokenId);
    }

    /// @inheritdoc IAchievement
    function hasBadge(address account, uint256 badgeId) external view returns (bool) {
        return _hasBadge[account][badgeId];
    }

    /// @inheritdoc IAchievement
    function badgeOf(uint256 tokenId) external view returns (uint256 badgeId) {
        _requireOwned(tokenId);
        return _tokenBadge[tokenId];
    }

    /// @notice Per-badge token URI (set at definition time).
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _badges[_tokenBadge[tokenId]].tokenURI;
    }

    /// @notice Resolve the ERC721/AccessControl supportsInterface diamond.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Soulbound: only mint (from == 0) and burn (to == 0) allowed.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    /// @notice Approvals are meaningless for soulbound tokens — revert explicitly.
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    /// @notice Emergency pause (admin only). Unpause is also admin-only.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
