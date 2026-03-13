// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FixedPointMath
/// @notice 18-decimal fixed-point arithmetic library. All protocol math uses WAD (1e18).
/// @dev No state. Pure math. Used by every contract in the protocol.
library FixedPointMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 5e17;
    uint256 internal constant WAD_SQUARED = 1e36;

    // ─── Custom Errors ───────────────────────────────────────────────

    error FixedPointMath__MulOverflow();
    error FixedPointMath__DivByZero();
    error FixedPointMath__ExpOverflow();
    error FixedPointMath__LnUndefined();
    error FixedPointMath__NegativeCast();
    error FixedPointMath__Uint256Overflow();
    error FixedPointMath__AbsMinInt();

    // ─── Core Arithmetic ─────────────────────────────────────────────

    /// @notice Multiply two WAD values with nearest rounding: (a * b + HALF_WAD) / WAD
    /// @param a First operand (WAD)
    /// @param b Second operand (WAD)
    /// @return result Product in WAD
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (a == 0 || b == 0) return 0;
        // Check overflow: a * b must not overflow uint256
        if (a > type(uint256).max / b) revert FixedPointMath__MulOverflow();
        result = (a * b + HALF_WAD) / WAD;
    }

    /// @notice Divide two WAD values with nearest rounding: (a * WAD + b / 2) / b
    /// @param a Numerator (WAD)
    /// @param b Denominator (WAD)
    /// @return result Quotient in WAD
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (b == 0) revert FixedPointMath__DivByZero();
        if (a == 0) return 0;
        // Check overflow: a * WAD must not overflow uint256
        if (a > (type(uint256).max - b / 2) / WAD) revert FixedPointMath__MulOverflow();
        result = (a * WAD + b / 2) / b;
    }

    // ─── Transcendental Functions ────────────────────────────────────

    /// @notice Exponentiation: e^x where x is WAD-encoded signed integer
    /// @dev Adapted from solmate's SignedWadMath. Returns uint256 since e^x > 0.
    /// @param x Exponent in WAD (signed)
    /// @return result e^x in WAD (unsigned)
    function wadExp(int256 x) internal pure returns (uint256 result) {
        unchecked {
            // When result < 0.5 we return zero. This happens when
            // x <= floor(log(0.5e18) * 1e18) ~ -42e18
            if (x <= -42139678854452767551) return 0;

            // When result > (2**255 - 1) / 1e18 we cannot represent it.
            // x >= floor(log((2**255 - 1) / 1e18) * 1e18) ~ 135e18
            if (x >= 135305999368893231589) revert FixedPointMath__ExpOverflow();

            // x is now in the range (-42, 136) * 1e18. Convert to (-42, 136) * 2**96
            // for more intermediate precision and a binary basis.
            // Base conversion: multiply by 1e18 / 2**96 = 5**18 / 2**78.
            x = (x << 78) / 5 ** 18;

            // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
            // of two such that exp(x) = exp(x') * 2**k.
            int256 k = ((x << 96) / 54916777467707473351141471128 + 2 ** 95) >> 96;
            x = x - k * 54916777467707473351141471128;

            // Evaluate using a (6, 7)-term rational approximation.
            int256 y = x + 1346386616545796478920950773328;
            y = ((y * x) >> 96) + 57155421227552351082224309758442;
            int256 p = y + x - 94201549194550492254356042504812;
            p = ((p * y) >> 96) + 28719021644029726153956944680412240;
            p = p * x + (4385272521454847904659076985693276 << 96);

            int256 q = x - 2855989394907223263936484059900;
            q = ((q * x) >> 96) + 50020603652535783019961831881945;
            q = ((q * x) >> 96) - 533845033583426703283633433725380;
            q = ((q * x) >> 96) + 3604857256930695427073651918091429;
            q = ((q * x) >> 96) - 14423608567350463180887372962807573;
            q = ((q * x) >> 96) + 26449188498355588339934803723976023;

            /// @solidity memory-safe-assembly
            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial won't have zeros in the domain as all its roots are complex.
                x := sdiv(p, q)
            }

            // Scale: multiply by s * 2^k * (1e18 / 2^96)
            result =
                uint256(int256((uint256(x) * 3822833074963236453042738258902158003155416615667) >> uint256(195 - k)));
        }
    }

    /// @notice Natural log: ln(x) where x is WAD-encoded
    /// @dev Adapted from solmate's SignedWadMath. Input is uint256 (must be > 0).
    /// @param x Input in WAD (must be > 0)
    /// @return r ln(x) in WAD (signed)
    function wadLn(uint256 x) internal pure returns (int256 r) {
        if (x == 0) revert FixedPointMath__LnUndefined();

        int256 xInt = int256(x);

        unchecked {
            /// @solidity memory-safe-assembly
            assembly {
                r := shl(7, lt(0xffffffffffffffffffffffffffffffff, xInt))
                r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, xInt))))
                r := or(r, shl(5, lt(0xffffffff, shr(r, xInt))))
                r := or(r, shl(4, lt(0xffff, shr(r, xInt))))
                r := or(r, shl(3, lt(0xff, shr(r, xInt))))
                r := or(r, shl(2, lt(0xf, shr(r, xInt))))
                r := or(r, shl(1, lt(0x3, shr(r, xInt))))
                r := or(r, lt(0x1, shr(r, xInt)))
            }

            // Reduce range of x to (1, 2) * 2**96
            int256 k = r - 96;
            xInt <<= uint256(159 - k);
            xInt = int256(uint256(xInt) >> 159);

            // Evaluate using a (8, 8)-term rational approximation.
            int256 p = xInt + 3273285459638523848632254066296;
            p = ((p * xInt) >> 96) + 24828157081833163892658089445524;
            p = ((p * xInt) >> 96) + 43456485725739037958740375743393;
            p = ((p * xInt) >> 96) - 11111509109440967052023855526967;
            p = ((p * xInt) >> 96) - 45023709667254063763336534515857;
            p = ((p * xInt) >> 96) - 14706773417378608786704636184526;
            p = p * xInt - (795164235651350426258249787498 << 96);

            int256 q = xInt + 5573035233440673466300451813936;
            q = ((q * xInt) >> 96) + 71694874799317883764090561454958;
            q = ((q * xInt) >> 96) + 283447036172924575727196451306956;
            q = ((q * xInt) >> 96) + 401686690394027663651624208769553;
            q = ((q * xInt) >> 96) + 204048457590392012362485061816622;
            q = ((q * xInt) >> 96) + 31853899698501571402653359427138;
            q = ((q * xInt) >> 96) + 909429971244387300277376558375;

            /// @solidity memory-safe-assembly
            assembly {
                r := sdiv(p, q)
            }

            // Finalization
            r *= 1677202110996718588342820967067443963516166;
            r += 16597577552685614221487285958193947469193820559219878177908093499208371 * k;
            r += 600920179829731861736702779321621459595472258049074101567377883020018308;
            r >>= 174;
        }
    }

    /// @notice Square root of a WAD value using Babylonian method
    /// @dev wadSqrt(WAD) = WAD, wadSqrt(0) = 0
    /// @param x Input in WAD
    /// @return result sqrt(x) in WAD
    function wadSqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;

        // We need sqrt(x * WAD) to maintain WAD encoding.
        // sqrt(x_wad) in WAD = sqrt(x_wad * 1e18)
        // To avoid overflow: if x <= type(uint256).max / WAD, we can do x * WAD directly.
        // Otherwise, we use: sqrt(x) * sqrt(WAD) but that loses precision.
        uint256 scaled;
        if (x <= type(uint256).max / WAD) {
            scaled = x * WAD;
        } else {
            // For very large x, compute sqrt(x) * sqrt(WAD) = sqrt(x) * 1e9
            // This path has slightly less precision but avoids overflow
            return _sqrt(x) * 1e9;
        }

        result = _sqrt(scaled);
    }

    /// @notice Power function: x^n where both are WAD-encoded
    /// @dev Uses exp(ln(x) * n). x must be > 0.
    /// @param x Base in WAD (must be > 0)
    /// @param n Exponent in WAD
    /// @return result x^n in WAD
    function wadPow(uint256 x, uint256 n) internal pure returns (uint256 result) {
        if (n == 0) return WAD;
        if (x == 0) return 0;
        if (x == WAD) return WAD;
        if (n == WAD) return x;

        // x^n = e^(ln(x) * n)
        int256 lnX = wadLn(x);
        int256 lnXTimesN;
        unchecked {
            lnXTimesN = (lnX * int256(n)) / int256(WAD);
        }
        result = wadExp(lnXTimesN);
    }

    // ─── Clamping ────────────────────────────────────────────────────

    /// @notice Clamp a value between min and max
    /// @param value Value to clamp
    /// @param minVal Minimum bound
    /// @param maxVal Maximum bound
    /// @return result Clamped value
    function clamp(uint256 value, uint256 minVal, uint256 maxVal) internal pure returns (uint256 result) {
        if (value < minVal) return minVal;
        if (value > maxVal) return maxVal;
        return value;
    }

    /// @notice Signed version of clamp
    /// @param value Value to clamp
    /// @param minVal Minimum bound
    /// @param maxVal Maximum bound
    /// @return result Clamped value
    function clampInt(int256 value, int256 minVal, int256 maxVal) internal pure returns (int256 result) {
        if (value < minVal) return minVal;
        if (value > maxVal) return maxVal;
        return value;
    }

    // ─── Type Conversions ────────────────────────────────────────────

    /// @notice Absolute value of a signed integer
    /// @dev Reverts on type(int256).min (cannot negate)
    /// @param x Signed input
    /// @return Unsigned absolute value
    function abs(int256 x) internal pure returns (uint256) {
        if (x == type(int256).min) revert FixedPointMath__AbsMinInt();
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /// @notice Convert uint256 to int256 safely
    /// @param x Unsigned input
    /// @return Signed output
    function toInt256(uint256 x) internal pure returns (int256) {
        if (x > uint256(type(int256).max)) revert FixedPointMath__Uint256Overflow();
        return int256(x);
    }

    /// @notice Convert int256 to uint256 safely (reverts on negative)
    /// @param x Signed input
    /// @return Unsigned output
    function toUint256(int256 x) internal pure returns (uint256) {
        if (x < 0) revert FixedPointMath__NegativeCast();
        return uint256(x);
    }

    // ─── Internal Helpers ────────────────────────────────────────────

    /// @dev Integer square root via Babylonian method (from solmate FixedPointMathLib)
    function _sqrt(uint256 x) private pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Start with z = 1.
            z := 1

            // Approximate log2(x) by finding the highest bit.
            let y := x
            if iszero(lt(y, 0x100000000000000000000000000000000)) {
                y := shr(128, y)
                z := shl(64, z)
            }
            if iszero(lt(y, 0x10000000000000000)) {
                y := shr(64, y)
                z := shl(32, z)
            }
            if iszero(lt(y, 0x100000000)) {
                y := shr(32, y)
                z := shl(16, z)
            }
            if iszero(lt(y, 0x10000)) {
                y := shr(16, y)
                z := shl(8, z)
            }
            if iszero(lt(y, 0x100)) {
                y := shr(8, y)
                z := shl(4, z)
            }
            if iszero(lt(y, 0x10)) {
                y := shr(4, y)
                z := shl(2, z)
            }
            if iszero(lt(y, 0x8)) { z := shl(1, z) }

            // Babylonian method iterations
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // Round down if needed.
            if lt(div(x, z), z) { z := div(x, z) }
        }
    }
}
