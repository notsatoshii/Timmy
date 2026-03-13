// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FixedPointMath } from "./FixedPointMath.sol";

/// @title ProbabilityIndex
/// @notice Helper library for PI validation, bounds checking, and convergence utilities.
/// @dev Pure math. PI is always in [0, WAD] representing probability [0, 1].
library ProbabilityIndex {
    using FixedPointMath for uint256;

    uint256 internal constant PI_MIN = 0;
    uint256 internal constant PI_MAX = 1e18; // WAD = 1.0
    uint256 internal constant WAD = 1e18;

    /// @notice Check if a PI value is valid (within [0, 1])
    /// @param pi Probability index (WAD)
    /// @return valid True if pi is in [0, WAD]
    function isValid(uint256 pi) internal pure returns (bool valid) {
        return pi <= PI_MAX;
    }

    /// @notice Clamp PI to [0, 1]
    /// @param pi Raw probability index (WAD)
    /// @return clamped PI clamped to [PI_MIN, PI_MAX]
    function clamp(uint256 pi) internal pure returns (uint256 clamped) {
        if (pi > PI_MAX) return PI_MAX;
        return pi;
    }

    /// @notice Compute PnL for a position given entry and current PI
    /// @dev PnL = direction × (PI_current - PI_entry) × position_size / WAD
    ///      direction = +1 for long, -1 for short
    /// @param piEntry PI at position open (WAD)
    /// @param piCurrent Current PI (WAD)
    /// @param positionSize Notional size of position (WAD)
    /// @param isLong True for long (YES), false for short (NO)
    /// @return pnl Signed PnL (positive = profit, negative = loss)
    function computePnL(
        uint256 piEntry,
        uint256 piCurrent,
        uint256 positionSize,
        bool isLong
    ) internal pure returns (int256 pnl) {
        int256 piDelta = int256(piCurrent) - int256(piEntry);

        // pnl = direction × piDelta × positionSize / WAD
        int256 rawPnl = (piDelta * int256(positionSize)) / int256(WAD);

        pnl = isLong ? rawPnl : -rawPnl;
    }

    /// @notice Check if PI is near 0 or 1 (extreme probability)
    /// @param pi Probability index (WAD)
    /// @param threshold Distance from boundary to consider extreme (WAD)
    /// @return isExtreme True if PI is within threshold of 0 or 1
    function isNearBoundary(uint256 pi, uint256 threshold) internal pure returns (bool isExtreme) {
        return pi <= threshold || pi >= (PI_MAX - threshold);
    }
}
