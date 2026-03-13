// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { ProbabilityIndex } from "../contracts/libraries/ProbabilityIndex.sol";

/// @dev Wrapper to expose library internals for testing
contract ProbabilityIndexHarness {
    function isValid(uint256 pi) external pure returns (bool) {
        return ProbabilityIndex.isValid(pi);
    }

    function clamp(uint256 pi) external pure returns (uint256) {
        return ProbabilityIndex.clamp(pi);
    }

    function computePnL(
        uint256 piEntry,
        uint256 piCurrent,
        uint256 positionSize,
        bool isLong
    ) external pure returns (int256) {
        return ProbabilityIndex.computePnL(piEntry, piCurrent, positionSize, isLong);
    }

    function isNearBoundary(uint256 pi, uint256 threshold) external pure returns (bool) {
        return ProbabilityIndex.isNearBoundary(pi, threshold);
    }
}

contract ProbabilityIndexTest is Test {
    uint256 constant WAD = 1e18;
    ProbabilityIndexHarness harness;

    function setUp() public {
        harness = new ProbabilityIndexHarness();
    }

    // ──────────────────────────────────────────────
    // isValid
    // ──────────────────────────────────────────────

    function test_isValid_zero() public view {
        assertTrue(harness.isValid(0));
    }

    function test_isValid_one() public view {
        assertTrue(harness.isValid(WAD));
    }

    function test_isValid_mid() public view {
        assertTrue(harness.isValid(5e17));
    }

    function test_isValid_overOne() public view {
        assertFalse(harness.isValid(WAD + 1));
    }

    function test_isValid_wayOverOne() public view {
        assertFalse(harness.isValid(2e18));
    }

    // ──────────────────────────────────────────────
    // clamp
    // ──────────────────────────────────────────────

    function test_clamp_withinRange() public view {
        assertEq(harness.clamp(5e17), 5e17);
    }

    function test_clamp_atMax() public view {
        assertEq(harness.clamp(WAD), WAD);
    }

    function test_clamp_aboveMax() public view {
        assertEq(harness.clamp(2e18), WAD, "Should clamp to 1.0");
    }

    function test_clamp_zero() public view {
        assertEq(harness.clamp(0), 0);
    }

    // ──────────────────────────────────────────────
    // computePnL
    // ──────────────────────────────────────────────

    function test_pnl_longProfit() public view {
        // Long: entry=0.50, current=0.60, size=1000 => PnL = +100
        int256 pnl = harness.computePnL(5e17, 6e17, 1000e18, true);
        assertEq(pnl, 100e18, "Long profit: (0.60-0.50)*1000 = 100");
    }

    function test_pnl_longLoss() public view {
        // Long: entry=0.50, current=0.40, size=1000 => PnL = -100
        int256 pnl = harness.computePnL(5e17, 4e17, 1000e18, true);
        assertEq(pnl, -100e18, "Long loss: (0.40-0.50)*1000 = -100");
    }

    function test_pnl_shortProfit() public view {
        // Short: entry=0.50, current=0.40, size=1000 => PnL = +100
        int256 pnl = harness.computePnL(5e17, 4e17, 1000e18, false);
        assertEq(pnl, 100e18, "Short profit: -(0.40-0.50)*1000 = +100");
    }

    function test_pnl_shortLoss() public view {
        // Short: entry=0.50, current=0.60, size=1000 => PnL = -100
        int256 pnl = harness.computePnL(5e17, 6e17, 1000e18, false);
        assertEq(pnl, -100e18, "Short loss: -(0.60-0.50)*1000 = -100");
    }

    function test_pnl_noChange() public view {
        int256 pnl = harness.computePnL(5e17, 5e17, 1000e18, true);
        assertEq(pnl, 0, "No PI change = zero PnL");
    }

    function test_pnl_settlement_long_wins() public view {
        // Long at PI=0.30, settles at 1.0, size=1000
        // PnL = (1.0 - 0.30) * 1000 = 700
        int256 pnl = harness.computePnL(3e17, WAD, 1000e18, true);
        assertEq(pnl, 700e18);
    }

    function test_pnl_settlement_long_loses() public view {
        // Long at PI=0.70, settles at 0, size=1000
        // PnL = (0 - 0.70) * 1000 = -700
        int256 pnl = harness.computePnL(7e17, 0, 1000e18, true);
        assertEq(pnl, -700e18);
    }

    function test_pnl_zeroSize() public view {
        int256 pnl = harness.computePnL(5e17, 6e17, 0, true);
        assertEq(pnl, 0, "Zero size = zero PnL");
    }

    // ──────────────────────────────────────────────
    // isNearBoundary
    // ──────────────────────────────────────────────

    function test_nearBoundary_atZero() public view {
        assertTrue(harness.isNearBoundary(0, 5e16), "0 is near boundary");
    }

    function test_nearBoundary_atOne() public view {
        assertTrue(harness.isNearBoundary(WAD, 5e16), "1.0 is near boundary");
    }

    function test_nearBoundary_nearZero() public view {
        assertTrue(harness.isNearBoundary(3e16, 5e16), "0.03 within 0.05 threshold");
    }

    function test_nearBoundary_nearOne() public view {
        assertTrue(harness.isNearBoundary(97e16, 5e16), "0.97 within 0.05 of 1.0");
    }

    function test_nearBoundary_middle() public view {
        assertFalse(harness.isNearBoundary(5e17, 5e16), "0.50 is not near boundary");
    }

    // ──────────────────────────────────────────────
    // Fuzz
    // ──────────────────────────────────────────────

    function testFuzz_pnl_longShortSymmetric(
        uint256 piEntry,
        uint256 piCurrent,
        uint256 size
    ) public view {
        piEntry = bound(piEntry, 0, WAD);
        piCurrent = bound(piCurrent, 0, WAD);
        size = bound(size, 0, 1e30);

        int256 longPnl = harness.computePnL(piEntry, piCurrent, size, true);
        int256 shortPnl = harness.computePnL(piEntry, piCurrent, size, false);

        // Long + Short PnL should sum to zero (zero-sum)
        assertEq(longPnl + shortPnl, 0, "Long + Short PnL must be zero-sum");
    }

    function testFuzz_clamp_bounded(uint256 pi) public view {
        uint256 result = harness.clamp(pi);
        assertLe(result, WAD);
    }

    function testFuzz_isValid_matches_clamp(uint256 pi) public view {
        bool valid = harness.isValid(pi);
        uint256 clamped = harness.clamp(pi);
        if (valid) {
            assertEq(clamped, pi, "Valid PI should not be modified by clamp");
        } else {
            assertEq(clamped, WAD, "Invalid PI should be clamped to WAD");
        }
    }
}
