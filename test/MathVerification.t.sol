// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { RiskCurves } from "../contracts/libraries/RiskCurves.sol";

/// @notice Harness to expose internal library functions for testing.
contract RiskCurvesVerificationHarness {
    function computeTauEffective(uint256 tau, bool isLive) external pure returns (uint256) {
        return RiskCurves.computeTauEffective(tau, isLive);
    }

    function computeR(uint256 tauEffective) external pure returns (uint256) {
        return RiskCurves.computeR(tauEffective);
    }

    function computeRBorrow(uint256 tauEffective) external pure returns (uint256) {
        return RiskCurves.computeRBorrow(tauEffective);
    }

    function computeRAdjusted(uint256 r, uint256 mMarket) external pure returns (uint256) {
        return RiskCurves.computeRAdjusted(r, mMarket);
    }
}

/// @title MathVerification
/// @notice Hand-calculated expected outputs verified against RiskCurves library.
contract MathVerificationTest is Test {
    RiskCurvesVerificationHarness harness;

    uint256 constant WAD = 1e18;
    uint256 constant TOLERANCE = 1e15; // 0.001 in WAD

    function setUp() public {
        harness = new RiskCurvesVerificationHarness();
    }

    /// @notice τ_effective = 4h × (1 - 0.70) = 1.2h
    function test_computeTauEffective_4h_live() public view {
        uint256 tau = 4e18; // 4 hours WAD
        uint256 result = harness.computeTauEffective(tau, true);
        uint256 expected = 1.2e18; // 1.2 hours WAD

        assertEq(result, expected, "tau_effective should be exactly 1.2h WAD");
    }

    /// @notice R(1.2h) = 1 - exp(-2.0 * 1.2 / 24) = 0.09516...
    function test_computeR_1_2h() public {
        uint256 tauEffective = 1.2e18; // 1.2 hours WAD
        uint256 result = harness.computeR(tauEffective);
        uint256 expected = 0.09516e18; // 0.09516 WAD

        assertApproxEqAbs(result, expected, TOLERANCE, "R(1.2h) should be ~0.09516");
        emit log_named_uint("R(1.2h) actual  ", result);
        emit log_named_uint("R(1.2h) expected", expected);
    }

    /// @notice R_borrow(1.2h) = 1 - exp(-2.0 * 1.2 / 168) = 0.01423...
    function test_computeRBorrow_1_2h() public {
        uint256 tauEffective = 1.2e18; // 1.2 hours WAD
        uint256 result = harness.computeRBorrow(tauEffective);
        uint256 expected = 0.01423e18; // 0.01423 WAD

        assertApproxEqAbs(result, expected, TOLERANCE, "R_borrow(1.2h) should be ~0.01423");
        emit log_named_uint("R_borrow(1.2h) actual  ", result);
        emit log_named_uint("R_borrow(1.2h) expected", expected);
    }

    /// @notice R_adjusted = R × M_market = 0.09516 × 0.8 = 0.07613
    function test_computeRAdjusted() public {
        uint256 r = 0.09516e18;     // R from above
        uint256 mMarket = 0.8e18;   // M_market = 0.8
        uint256 result = harness.computeRAdjusted(r, mMarket);
        uint256 expected = 0.07613e18; // 0.07613 WAD

        assertApproxEqAbs(result, expected, TOLERANCE, "R_adjusted should be ~0.07613");
        emit log_named_uint("R_adjusted actual  ", result);
        emit log_named_uint("R_adjusted expected", expected);
    }
}
