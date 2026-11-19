// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReputation — Step 3 of the AGENTHUB contract build order.
/// @notice Records validated reputation events. Points may ONLY increase
/// through authorized sources (QuestManager) — there is deliberately NO
/// function for arbitrary administrative score increases. Every change emits
/// an event so the full history is transparent and auditable on-chain.
interface IReputation {
    error UnauthorizedScoreSource(address caller);
    error InvalidPoints();

    event PointsAdded(address indexed account, uint256 indexed questId, uint256 points, uint256 newTotal);

    /// @return total Total reputation points for `account`.
    function points(address account) external view returns (uint256 total);

    /// @return level_ Level derived from points (see levelThreshold).
    function level(address account) external view returns (uint8 level_);

    /// @return threshold Minimum points required for `level_` (level 1 = 0 points).
    function levelThreshold(uint8 level_) external view returns (uint256 threshold);

    /// @notice Add points for a validated quest completion. Only QuestManager.
    function addPoints(address account, uint256 pointsAmount, uint256 questId) external;

    /// @return count Number of reputation events recorded for `account`.
    function totalEvents(address account) external view returns (uint256 count);
}
