// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IReputation} from "./interfaces/IReputation.sol";

/// @title Reputation
/// @notice Points ledger for validated quest completions.
/// @dev SECURITY INVARIANT: there is deliberately NO function for arbitrary
/// administrative score increases. Points increase ONLY via SCORE_SOURCE_ROLE
/// (the QuestManager contract), capped per event, and every change emits a
/// PointsAdded event with the causing quest id so the full history is
/// transparent and auditable on-chain.
contract Reputation is IReputation, AccessControl, Pausable {
    bytes32 public constant SCORE_SOURCE_ROLE = keccak256("SCORE_SOURCE_ROLE");

    /// @notice Maximum points a single validated event may add.
    uint256 public constant MAX_POINTS_PER_EVENT = 10_000;

    /// @notice Minimum points for levels 1..5 (level 1 = 0 points).
    /// @dev Kept as a pure function: Solidity does not allow constant arrays.
    function _levelThreshold(uint8 level_) internal pure returns (uint256) {
        if (level_ == 1) return 0;
        if (level_ == 2) return 100;
        if (level_ == 3) return 300;
        if (level_ == 4) return 700;
        return 1500; // level 5
    }

    uint8 public constant MAX_LEVEL = 5;

    mapping(address => uint256) private _points;
    mapping(address => uint256) private _events;

    constructor(address admin_) {
        if (admin_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @inheritdoc IReputation
    function points(address account) external view returns (uint256 total) {
        return _points[account];
    }

    /// @inheritdoc IReputation
    function level(address account) external view returns (uint8 level_) {
        uint256 total = _points[account];
        // Thresholds are ascending and bounded (5 entries) — no unbounded loop.
        for (uint8 i = MAX_LEVEL; i > 0; i--) {
            if (total >= _levelThreshold(i)) return i;
        }
        return 1; // Unreachable: level 1 threshold is 0.
    }

    /// @inheritdoc IReputation
    function levelThreshold(uint8 level_) external pure returns (uint256 threshold) {
        if (level_ == 0 || level_ > MAX_LEVEL) revert InvalidLevel(level_);
        return _levelThreshold(level_);
    }

    /// @inheritdoc IReputation
    /// @dev Only QuestManager (SCORE_SOURCE_ROLE). Pausing stops new points;
    /// reads keep working.
    function addPoints(address account, uint256 pointsAmount, uint256 questId)
        external
        whenNotPaused
        onlyRole(SCORE_SOURCE_ROLE)
    {
        if (account == address(0)) revert ZeroAddress();
        if (pointsAmount == 0 || pointsAmount > MAX_POINTS_PER_EVENT) revert InvalidPoints();
        _points[account] += pointsAmount;
        _events[account] += 1;
        emit PointsAdded(account, questId, pointsAmount, _points[account]);
    }

    /// @inheritdoc IReputation
    function totalEvents(address account) external view returns (uint256 count) {
        return _events[account];
    }

    /// @notice Emergency pause (admin only). Unpause is also admin-only.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
