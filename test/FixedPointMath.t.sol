// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/libraries/FixedPointMath.sol";

/// @dev Wrapper contract to expose library functions as external calls (needed for vm.expectRevert)
contract FixedPointMathWrapper {
    function wadMul(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPointMath.wadMul(a, b);
    }

    function wadDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPointMath.wadDiv(a, b);
    }

    function wadExp(int256 x) external pure returns (uint256) {
        return FixedPointMath.wadExp(x);
    }

    function wadLn(uint256 x) external pure returns (int256) {
        return FixedPointMath.wadLn(x);
    }

    function abs(int256 x) external pure returns (uint256) {
        return FixedPointMath.abs(x);
    }

    function toInt256(uint256 x) external pure returns (int256) {
        return FixedPointMath.toInt256(x);
    }

    function toUint256(int256 x) external pure returns (uint256) {
        return FixedPointMath.toUint256(x);
    }
}

contract FixedPointMathTest is Test {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;

    uint256 constant WAD = 1e18;
    FixedPointMathWrapper wrapper;

    function setUp() public {
        wrapper = new FixedPointMathWrapper();
    }

    // ───────────────────────── wadMul ─────────────────────────

    function test_wadMul_identity() public pure {
        assertEq(FixedPointMath.wadMul(WAD, 5e18), 5e18);
        assertEq(FixedPointMath.wadMul(5e18, WAD), 5e18);
    }

    function test_wadMul_zero() public pure {
        assertEq(FixedPointMath.wadMul(0, 5e18), 0);
        assertEq(FixedPointMath.wadMul(5e18, 0), 0);
    }

    function test_wadMul_basic() public pure {
        // 2.0 * 3.0 = 6.0
        assertEq(FixedPointMath.wadMul(2e18, 3e18), 6e18);
        // 0.5 * 4.0 = 2.0
        assertEq(FixedPointMath.wadMul(5e17, 4e18), 2e18);
    }

    function test_wadMul_rounding() public pure {
        // wadMul(3, WAD/3) should round to 1 (nearest rounding via HALF_WAD)
        // 3 * (WAD/3) = 3 * 333333333333333333 = 999999999999999999
        // (999999999999999999 + 5e17) / 1e18 = 1
        assertEq(FixedPointMath.wadMul(3, WAD / 3), 1);
    }

    function test_wadMul_overflow_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__MulOverflow.selector);
        wrapper.wadMul(type(uint256).max, 2);
    }

    // ───────────────────────── wadDiv ─────────────────────────

    function test_wadDiv_identity() public pure {
        assertEq(FixedPointMath.wadDiv(5e18, WAD), 5e18);
    }

    function test_wadDiv_zero_numerator() public pure {
        assertEq(FixedPointMath.wadDiv(0, 5e18), 0);
    }

    function test_wadDiv_basic() public pure {
        // 6.0 / 3.0 = 2.0
        assertEq(FixedPointMath.wadDiv(6e18, 3e18), 2e18);
        // 1.0 / 2.0 = 0.5
        assertEq(FixedPointMath.wadDiv(1e18, 2e18), 5e17);
    }

    function test_wadDiv_by_zero_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__DivByZero.selector);
        wrapper.wadDiv(1e18, 0);
    }

    function test_wadDiv_by_one_not_wad() public pure {
        // wadDiv(x, 1) = x * WAD — common gotcha
        assertEq(FixedPointMath.wadDiv(1, 1), WAD);
    }

    function test_wadDiv_overflow_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__MulOverflow.selector);
        wrapper.wadDiv(type(uint256).max, 1);
    }

    // ───────────────────────── wadExp ─────────────────────────

    function test_wadExp_zero() public pure {
        // e^0 = 1
        assertEq(FixedPointMath.wadExp(0), WAD);
    }

    function test_wadExp_one() public pure {
        // e^1 ≈ 2.718281828...
        uint256 result = FixedPointMath.wadExp(1e18);
        // Allow 1e10 tolerance (~1e-8 relative)
        assertApproxEqAbs(result, 2718281828459045235, 1e10);
    }

    function test_wadExp_negative_one() public pure {
        // e^(-1) ≈ 0.367879441...
        uint256 result = FixedPointMath.wadExp(-1e18);
        assertApproxEqAbs(result, 367879441171442321, 1e10);
    }

    function test_wadExp_large_negative() public pure {
        // e^(-100) should return ~0
        assertEq(FixedPointMath.wadExp(-100e18), 0);
    }

    function test_wadExp_large_positive_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__ExpOverflow.selector);
        wrapper.wadExp(136e18);
    }

    function test_wadExp_risk_curve_use_case() public pure {
        // R(τ) = 1 - e^(-λ * τ_eff / τ_ref)
        // λ=2, τ_eff=24h, τ_ref=24h → e^(-2) ≈ 0.1353...
        // So R = 1 - 0.1353 = 0.8647
        int256 exponent = -2e18; // -λ * τ_eff / τ_ref = -2
        uint256 expResult = FixedPointMath.wadExp(exponent);
        assertApproxEqAbs(expResult, 135335283236612691, 1e10);
    }

    // ───────────────────────── wadLn ──────────────────────────

    function test_wadLn_one() public pure {
        // ln(1) = 0
        assertEq(FixedPointMath.wadLn(WAD), 0);
    }

    function test_wadLn_e() public pure {
        // ln(e) = 1
        int256 result = FixedPointMath.wadLn(2718281828459045235);
        assertApproxEqAbs(result, 1e18, 1e10);
    }

    function test_wadLn_zero_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__LnUndefined.selector);
        wrapper.wadLn(0);
    }

    function test_wadLn_two() public pure {
        // ln(2) ≈ 0.693147...
        int256 result = FixedPointMath.wadLn(2e18);
        assertApproxEqAbs(result, 693147180559945309, 1e10);
    }

    function test_wadLn_half() public pure {
        // ln(0.5) ≈ -0.693147...
        int256 result = FixedPointMath.wadLn(5e17);
        assertApproxEqAbs(result, -693147180559945309, 1e10);
    }

    // ──────────────────────── wadSqrt ─────────────────────────

    function test_wadSqrt_zero() public pure {
        assertEq(FixedPointMath.wadSqrt(0), 0);
    }

    function test_wadSqrt_wad() public pure {
        // sqrt(1.0) = 1.0 in WAD
        assertEq(FixedPointMath.wadSqrt(WAD), WAD);
    }

    function test_wadSqrt_four() public pure {
        // sqrt(4.0) = 2.0
        assertEq(FixedPointMath.wadSqrt(4e18), 2e18);
    }

    function test_wadSqrt_raw_one() public pure {
        // sqrt(1) in WAD = sqrt(1e18) ≈ 1e9 (NOT 1e18!)
        // This is the common mistake from spec
        uint256 result = FixedPointMath.wadSqrt(1);
        assertEq(result, 1e9);
    }

    function test_wadSqrt_nine() public pure {
        // sqrt(9.0) = 3.0
        assertEq(FixedPointMath.wadSqrt(9e18), 3e18);
    }

    function test_wadSqrt_two() public pure {
        // sqrt(2.0) ≈ 1.41421...
        uint256 result = FixedPointMath.wadSqrt(2e18);
        assertApproxEqAbs(result, 1414213562373095048, 1e9);
    }

    // ──────────────────────── wadPow ──────────────────────────

    function test_wadPow_zero_exponent() public pure {
        // x^0 = 1
        assertEq(FixedPointMath.wadPow(5e18, 0), WAD);
    }

    function test_wadPow_zero_base() public pure {
        // 0^n = 0
        assertEq(FixedPointMath.wadPow(0, 5e18), 0);
    }

    function test_wadPow_identity() public pure {
        // x^1 = x
        assertEq(FixedPointMath.wadPow(5e18, WAD), 5e18);
    }

    function test_wadPow_wad_base() public pure {
        // 1^n = 1
        assertEq(FixedPointMath.wadPow(WAD, 5e18), WAD);
    }

    function test_wadPow_square() public pure {
        // 2^2 = 4
        uint256 result = FixedPointMath.wadPow(2e18, 2e18);
        assertApproxEqAbs(result, 4e18, 1e10);
    }

    function test_wadPow_sqrt_via_pow() public pure {
        // 4^0.5 = 2
        uint256 result = FixedPointMath.wadPow(4e18, 5e17);
        assertApproxEqAbs(result, 2e18, 1e10);
    }

    // ──────────────────────── clamp ───────────────────────────

    function test_clamp_within_range() public pure {
        assertEq(FixedPointMath.clamp(5e18, 1e18, 10e18), 5e18);
    }

    function test_clamp_below_min() public pure {
        assertEq(FixedPointMath.clamp(0, 1e18, 10e18), 1e18);
    }

    function test_clamp_above_max() public pure {
        assertEq(FixedPointMath.clamp(20e18, 1e18, 10e18), 10e18);
    }

    // ─────────────────────── clampInt ─────────────────────────

    function test_clampInt_within_range() public pure {
        assertEq(FixedPointMath.clampInt(0, -5e18, 5e18), 0);
    }

    function test_clampInt_below_min() public pure {
        assertEq(FixedPointMath.clampInt(-10e18, -5e18, 5e18), -5e18);
    }

    function test_clampInt_above_max() public pure {
        assertEq(FixedPointMath.clampInt(10e18, -5e18, 5e18), 5e18);
    }

    // ──────────────────────── abs ─────────────────────────────

    function test_abs_positive() public pure {
        assertEq(FixedPointMath.abs(5e18), 5e18);
    }

    function test_abs_negative() public pure {
        assertEq(FixedPointMath.abs(-5e18), 5e18);
    }

    function test_abs_zero() public pure {
        assertEq(FixedPointMath.abs(0), 0);
    }

    function test_abs_min_int_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__AbsMinInt.selector);
        wrapper.abs(type(int256).min);
    }

    // ─────────────────────── toInt256 ─────────────────────────

    function test_toInt256_valid() public pure {
        assertEq(FixedPointMath.toInt256(5e18), int256(5e18));
    }

    function test_toInt256_zero() public pure {
        assertEq(FixedPointMath.toInt256(0), int256(0));
    }

    function test_toInt256_max_valid() public pure {
        assertEq(FixedPointMath.toInt256(uint256(type(int256).max)), type(int256).max);
    }

    function test_toInt256_overflow_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__Uint256Overflow.selector);
        wrapper.toInt256(uint256(type(int256).max) + 1);
    }

    // ────────────────────── toUint256 ─────────────────────────

    function test_toUint256_valid() public pure {
        assertEq(FixedPointMath.toUint256(int256(5e18)), 5e18);
    }

    function test_toUint256_zero() public pure {
        assertEq(FixedPointMath.toUint256(int256(0)), 0);
    }

    function test_toUint256_negative_reverts() public {
        vm.expectRevert(FixedPointMath.FixedPointMath__NegativeCast.selector);
        wrapper.toUint256(-1);
    }

    // ────────────────────── Fuzz Tests ────────────────────────

    function testFuzz_wadMul_commutative(uint128 a, uint128 b) public pure {
        uint256 a256 = uint256(a);
        uint256 b256 = uint256(b);
        assertEq(FixedPointMath.wadMul(a256, b256), FixedPointMath.wadMul(b256, a256));
    }

    function testFuzz_wadDiv_wadMul_roundtrip(uint128 a) public pure {
        vm.assume(a > 0 && a < type(uint128).max / 2);
        uint256 a256 = uint256(a) * WAD; // Make it a proper WAD value
        uint256 b256 = 3e18; // divide by 3

        uint256 divided = FixedPointMath.wadDiv(a256, b256);
        uint256 recovered = FixedPointMath.wadMul(divided, b256);
        // Allow 1 wei rounding error
        assertApproxEqAbs(recovered, a256, 1);
    }

    function testFuzz_wadExp_wadLn_roundtrip(uint256 x) public pure {
        // x between 0.01 and 100 in WAD
        x = bound(x, 1e16, 100e18);
        int256 ln = FixedPointMath.wadLn(x);
        uint256 recovered = FixedPointMath.wadExp(ln);
        // Allow relative error of 1e-8
        assertApproxEqRel(recovered, x, 1e10);
    }

    function testFuzz_clamp_bounded(uint256 value, uint256 minVal, uint256 maxVal) public pure {
        vm.assume(minVal <= maxVal);
        uint256 result = FixedPointMath.clamp(value, minVal, maxVal);
        assertTrue(result >= minVal && result <= maxVal);
    }

    function testFuzz_abs_positive_result(int256 x) public pure {
        vm.assume(x != type(int256).min);
        uint256 result = FixedPointMath.abs(x);
        if (x >= 0) {
            assertEq(result, uint256(x));
        } else {
            assertEq(result, uint256(-x));
        }
    }
}
