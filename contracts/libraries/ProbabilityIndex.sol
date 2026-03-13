// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ProbabilityIndex
/// @notice Helper library for PI validation, bounds checking, and convergence utilities.
/// @dev Pure math. PI is always in [0, WAD] representing probability [0, 1].
library ProbabilityIndex {
    uint256 internal constant PI_MIN = 0;
    uint256 internal constant PI_MAX = 1e18; // WAD = 1.0

    function isValid(uint256 pi) internal pure returns (bool valid) {
        revert("NOT_IMPLEMENTED");
    }

    function clamp(uint256 pi) internal pure returns (uint256 clamped) {
        revert("NOT_IMPLEMENTED");
    }

    function computePnL(
        uint256 piEntry,
        uint256 piCurrent,
        uint256 positionSize,
        bool isLong
    ) internal pure returns (int256 pnl) {
        revert("NOT_IMPLEMENTED");
    }

    function isNearBoundary(uint256 pi, uint256 threshold) internal pure returns (bool isExtreme) {
        revert("NOT_IMPLEMENTED");
    }
}
