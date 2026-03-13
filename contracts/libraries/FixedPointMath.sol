// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FixedPointMath
/// @notice 18-decimal fixed-point arithmetic library. All protocol math uses WAD (1e18).
/// @dev No state. Pure math. Used by every contract in the protocol.
library FixedPointMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 5e17;
    uint256 internal constant RAY = 1e27;

    /// @notice Multiply two WAD values: (a * b) / WAD
    /// @param a First operand (WAD)
    /// @param b Second operand (WAD)
    /// @return result Product in WAD
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256 result);

    /// @notice Divide two WAD values: (a * WAD) / b
    /// @param a Numerator (WAD)
    /// @param b Denominator (WAD)
    /// @return result Quotient in WAD
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256 result);

    /// @notice Exponentiation: e^x where x is WAD-encoded
    /// @dev Used by RiskCurves for R(τ) = 1 - e^(-λτ/τ_ref)
    /// @param x Exponent in WAD (can be negative via int256 overload)
    /// @return result e^x in WAD
    function wadExp(int256 x) internal pure returns (uint256 result);

    /// @notice Natural log: ln(x) where x is WAD-encoded
    /// @param x Input in WAD (must be > 0)
    /// @return result ln(x) in WAD (signed)
    function wadLn(uint256 x) internal pure returns (int256 result);

    /// @notice Square root of a WAD value
    /// @dev Used by LeverageModel for TVL_Multiplier = (TVL/TVL_maturity)^0.5
    /// @param x Input in WAD
    /// @return result sqrt(x) in WAD
    function wadSqrt(uint256 x) internal pure returns (uint256 result);

    /// @notice Power function: x^n where both are WAD
    /// @param x Base in WAD
    /// @param n Exponent in WAD
    /// @return result x^n in WAD
    function wadPow(uint256 x, uint256 n) internal pure returns (uint256 result);

    /// @notice Clamp a value between min and max
    /// @param value Value to clamp
    /// @param minVal Minimum bound
    /// @param maxVal Maximum bound
    /// @return result Clamped value
    function clamp(uint256 value, uint256 minVal, uint256 maxVal) internal pure returns (uint256 result);

    /// @notice Signed version of clamp
    function clampInt(int256 value, int256 minVal, int256 maxVal) internal pure returns (int256 result);

    /// @notice Absolute value of a signed integer
    function abs(int256 x) internal pure returns (uint256);

    /// @notice Convert uint to int safely
    function toInt256(uint256 x) internal pure returns (int256);

    /// @notice Convert int to uint safely (reverts on negative)
    function toUint256(int256 x) internal pure returns (uint256);
}

