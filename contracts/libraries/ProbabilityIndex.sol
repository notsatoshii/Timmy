// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ProbabilityIndex
/// @notice Helper library for PI validation, bounds checking, and convergence utilities.
/// @dev Pure math. PI is always in [0, WAD] representing probability [0, 1].
library ProbabilityIndex {
    uint256 internal constant PI_MIN = 0;
    uint256 internal constant PI_MAX = 1e18; // WAD = 1.0

    /// @notice Validate that a PI value is within bounds [0, 1]
    /// @param pi The probability index value (WAD)
    /// @return valid True if 0 <= pi <= WAD
    function isValid(uint256 pi) internal pure returns (bool valid);

    /// @notice Clamp a PI value to [0, WAD]
    /// @param pi Raw PI value
    /// @return clamped PI clamped to valid range
    function clamp(uint256 pi) internal pure returns (uint256 clamped);

    /// @notice Compute PnL for a position given PI movement
    /// @param piEntry PI at position open (WAD)
    /// @param piCurrent Current PI (WAD)
    /// @param positionSize Notional size (WAD)
    /// @param isLong True for long, false for short
    /// @return pnl Signed PnL (positive = profit, negative = loss)
    function computePnL(
        uint256 piEntry,
        uint256 piCurrent,
        uint256 positionSize,
        bool isLong
    ) internal pure returns (int256 pnl);

    /// @notice Check if PI is near an extreme (close to 0 or 1)
    /// @param pi Current PI (WAD)
    /// @param threshold Distance from boundary to consider "extreme" (WAD)
    /// @return isExtreme True if pi < threshold or pi > (1 - threshold)
    function isNearBoundary(uint256 pi, uint256 threshold) internal pure returns (bool isExtreme);
}

