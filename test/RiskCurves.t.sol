// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { RiskCurves } from "../contracts/libraries/RiskCurves.sol";
import { FixedPointMath } from "../contracts/libraries/FixedPointMath.sol";

/// @dev Wrapper to expose library internals for testing
contract RiskCurvesHarness {
    function computeTauEffective(uint256 tau, bool isLive) external pure returns (uint256) {
        return RiskCurves.computeTauEffective(tau, isLive);
    }

    function computeR(uint256 tauEffective) external pure returns (uint256) {
        return RiskCurves.computeR(tauEffective);
    }

    function computeRBorrow(uint256 tauEffective) external pure returns (uint256) {
        return RiskCurves.computeRBorrow(tauEffective);
    }

    function computeVolFactor(uint256 sigmaCurrent, uint256 sigmaBaseline) external pure returns (uint256) {
        return RiskCurves.computeVolFactor(sigmaCurrent, sigmaBaseline);
    }

    function computeDepthFactor(uint256 externalDepth, uint256 depthThreshold) external pure returns (uint256) {
        return RiskCurves.computeDepthFactor(externalDepth, depthThreshold);
    }

    function computeConcentrationFactor(uint256 marketOI, uint256 globalOI) external pure returns (uint256) {
        return RiskCurves.computeConcentrationFactor(marketOI, globalOI);
    }

    function computeMarketAdjustment(
        uint256 sigmaCurrent,
        uint256 sigmaBaseline,
        uint256 externalDepth,
        uint256 depthThreshold,
        uint256 marketOI,
        uint256 globalOI
    ) external pure returns (uint256) {
        return RiskCurves.computeMarketAdjustment(
            sigmaCurrent, sigmaBaseline, externalDepth, depthThreshold, marketOI, globalOI
        );
    }

    function computeRAdjusted(uint256 r, uint256 mMarket) external pure returns (uint256) {
        return RiskCurves.computeRAdjusted(r, mMarket);
    }

    function leverageCompression(uint256 rAdjusted) external pure returns (uint256) {
        return RiskCurves.leverageCompression(rAdjusted);
    }

    function oiCapMultiplier(uint256 rAdjusted) external pure returns (uint256) {
        return RiskCurves.oiCapMultiplier(rAdjusted);
    }

    function mmMultiplier(uint256 rAdjusted) external pure returns (uint256) {
        return RiskCurves.mmMultiplier(rAdjusted);
    }

    function imMultiplier(uint256 rAdjusted) external pure returns (uint256) {
        return RiskCurves.imMultiplier(rAdjusted);
    }

    function executionDepthMultiplier(uint256 rAdjusted) external pure returns (uint256) {
        return RiskCurves.executionDepthMultiplier(rAdjusted);
    }

    function borrowMttR(uint256 rBorrowAdjusted) external pure returns (uint256) {
        return RiskCurves.borrowMttR(rBorrowAdjusted);
    }

    function oracleFrequency(uint256 rAdjusted) external pure returns (uint256) {
        return RiskCurves.oracleFrequency(rAdjusted);
    }

    function liquidationSLA(uint256 rAdjusted) external pure returns (uint256) {
        return RiskCurves.liquidationSLA(rAdjusted);
    }
}

contract RiskCurvesTest is Test {
    uint256 constant WAD = 1e18;
    RiskCurvesHarness harness;

    function setUp() public {
        harness = new RiskCurvesHarness();
    }

    // ──────────────────────────────────────────────
    // computeTauEffective
    // ──────────────────────────────────────────────

    function test_tauEffective_notLive() public view {
        uint256 tau = 48e18; // 48 hours
        uint256 result = harness.computeTauEffective(tau, false);
        assertEq(result, tau, "Not live: tau_effective = tau");
    }

    function test_tauEffective_live() public view {
        uint256 tau = 48e18; // 48 hours
        uint256 result = harness.computeTauEffective(tau, true);
        // τ_effective = 48 × (1 - 0.70) = 48 × 0.30 = 14.4
        uint256 expected = 144e17; // 14.4e18
        assertApproxEqAbs(result, expected, 1, "Live: tau_effective = tau * 0.30");
    }

    function test_tauEffective_zeroTau() public view {
        assertEq(harness.computeTauEffective(0, false), 0);
        assertEq(harness.computeTauEffective(0, true), 0);
    }

    // ──────────────────────────────────────────────
    // computeR
    // ──────────────────────────────────────────────

    function test_computeR_zeroTau() public view {
        assertEq(harness.computeR(0), 0, "R(0) = 0");
    }

    function test_computeR_atTauRef() public view {
        // R(24) = 1 - e^(-2 * 24/24) = 1 - e^(-2) ≈ 0.8647
        uint256 result = harness.computeR(24e18);
        assertApproxEqAbs(result, 8647e14, 1e15, "R(tau_ref) ~ 0.8647");
    }

    function test_computeR_large_tau() public view {
        // R(120) = 1 - e^(-2 * 120/24) = 1 - e^(-10) ≈ 0.99995
        uint256 result = harness.computeR(120e18);
        assertGt(result, 999e15, "R should be near 1 for large tau");
    }

    function test_computeR_small_tau() public view {
        // R(1) = 1 - e^(-2/24) = 1 - e^(-0.0833) ≈ 0.0800
        uint256 result = harness.computeR(1e18);
        assertApproxEqAbs(result, 8e16, 2e15, "R(1h) ~ 0.08");
    }

    function test_computeR_monotonic() public view {
        uint256 r1 = harness.computeR(1e18);
        uint256 r6 = harness.computeR(6e18);
        uint256 r24 = harness.computeR(24e18);
        uint256 r48 = harness.computeR(48e18);

        assertLt(r1, r6, "R must be monotonically increasing");
        assertLt(r6, r24);
        assertLt(r24, r48);
    }

    // ──────────────────────────────────────────────
    // computeRBorrow
    // ──────────────────────────────────────────────

    function test_computeRBorrow_zeroTau() public view {
        assertEq(harness.computeRBorrow(0), 0);
    }

    function test_computeRBorrow_at168h() public view {
        // R_borrow(168) = 1 - e^(-2 * 168/168) = 1 - e^(-2) ≈ 0.8647
        uint256 result = harness.computeRBorrow(168e18);
        assertApproxEqAbs(result, 8647e14, 1e15, "R_borrow(168h) ~ 0.8647");
    }

    function test_computeRBorrow_slower_than_R() public view {
        // At 24h, R_borrow should be much less than R
        uint256 r = harness.computeR(24e18);
        uint256 rBorrow = harness.computeRBorrow(24e18);
        assertGt(r, rBorrow, "R_borrow tightens slower than R");
    }

    // ──────────────────────────────────────────────
    // computeVolFactor
    // ──────────────────────────────────────────────

    function test_volFactor_noExcess() public view {
        assertEq(harness.computeVolFactor(5e16, 1e17), WAD, "No excess vol = 1.0");
    }

    function test_volFactor_equal() public view {
        assertEq(harness.computeVolFactor(1e17, 1e17), WAD, "Equal = 1.0");
    }

    function test_volFactor_excess() public view {
        // sigma=0.20, baseline=0.10 => excess=0.10 => 1/(1+0.10) ≈ 0.909
        uint256 result = harness.computeVolFactor(2e17, 1e17);
        assertApproxEqAbs(result, 909090909090909091, 1e15, "1/(1+0.1) ~ 0.909");
    }

    function test_volFactor_highVol() public view {
        // sigma=1.0, baseline=0 => 1/(1+1) = 0.50
        uint256 result = harness.computeVolFactor(WAD, 0);
        assertApproxEqAbs(result, 5e17, 1, "1/(1+1) = 0.50");
    }

    // ──────────────────────────────────────────────
    // computeDepthFactor
    // ──────────────────────────────────────────────

    function test_depthFactor_aboveThreshold() public view {
        assertEq(harness.computeDepthFactor(2e18, WAD), WAD, "Depth >= threshold = 1.0");
    }

    function test_depthFactor_belowThreshold() public view {
        // 0.5 / 1.0 = 0.5
        uint256 result = harness.computeDepthFactor(5e17, WAD);
        assertEq(result, 5e17);
    }

    function test_depthFactor_zeroThreshold() public {
        vm.expectRevert(RiskCurves.RiskCurves__ZeroDepthThreshold.selector);
        harness.computeDepthFactor(0, 0);
    }

    function test_depthFactor_zeroDepth() public view {
        assertEq(harness.computeDepthFactor(0, WAD), 0, "Zero depth = 0");
    }

    // ──────────────────────────────────────────────
    // computeConcentrationFactor
    // ──────────────────────────────────────────────

    function test_concFactor_belowThreshold() public view {
        // 10% concentration => no penalty
        assertEq(harness.computeConcentrationFactor(1e17, WAD), WAD);
    }

    function test_concFactor_atThreshold() public view {
        // 15% concentration => no penalty (threshold is <=)
        assertEq(harness.computeConcentrationFactor(15e16, WAD), WAD);
    }

    function test_concFactor_aboveThreshold() public view {
        // 25% concentration => penalty = 2 × (0.25 - 0.15) = 0.20
        // factor = 1.0 - 0.20 = 0.80
        uint256 result = harness.computeConcentrationFactor(25e16, WAD);
        assertApproxEqAbs(result, 8e17, 1e15);
    }

    function test_concFactor_floored() public view {
        // 50% concentration => penalty = 2 × (0.50 - 0.15) = 0.70
        // factor = max(0.5, 1.0 - 0.70) = 0.50 (hits floor)
        uint256 result = harness.computeConcentrationFactor(5e17, WAD);
        assertApproxEqAbs(result, 5e17, 1e15);
    }

    function test_concFactor_veryHigh() public view {
        // 80% concentration => hits floor
        uint256 result = harness.computeConcentrationFactor(8e17, WAD);
        assertEq(result, 5e17, "Should be floored at 0.50");
    }

    function test_concFactor_zeroGlobalOI() public view {
        assertEq(harness.computeConcentrationFactor(WAD, 0), WAD);
    }

    function test_concFactor_zeroMarketOI() public view {
        assertEq(harness.computeConcentrationFactor(0, WAD), WAD);
    }

    // ──────────────────────────────────────────────
    // computeMarketAdjustment
    // ──────────────────────────────────────────────

    function test_marketAdjustment_allPerfect() public view {
        // No vol excess, depth at threshold, concentration below threshold
        uint256 result = harness.computeMarketAdjustment(1e17, 1e17, WAD, WAD, 1e17, WAD);
        assertEq(result, WAD, "All factors 1.0 => M_market = 1.0");
    }

    function test_marketAdjustment_combined() public view {
        // vol: sigma=0.20, base=0.10 => ~0.909
        // depth: 0.5/1.0 = 0.50
        // conc: 10/100 = 10% => 1.0
        // M = 0.909 * 0.50 * 1.0 ≈ 0.4545
        uint256 result = harness.computeMarketAdjustment(2e17, 1e17, 5e17, WAD, 1e17, WAD);
        assertApproxEqAbs(result, 4545e14, 1e15);
    }

    // ──────────────────────────────────────────────
    // computeRAdjusted
    // ──────────────────────────────────────────────

    function test_rAdjusted() public view {
        uint256 r = 8e17; // 0.80
        uint256 mMarket = 5e17; // 0.50
        uint256 result = harness.computeRAdjusted(r, mMarket);
        assertApproxEqAbs(result, 4e17, 1, "0.80 * 0.50 = 0.40");
    }

    // ──────────────────────────────────────────────
    // Parameter Mappings
    // ──────────────────────────────────────────────

    function test_leverageCompression() public view {
        assertEq(harness.leverageCompression(5e17), 5e17, "Identity mapping");
    }

    function test_oiCapMultiplier_zero() public view {
        assertEq(harness.oiCapMultiplier(0), 2e17, "R=0 => 0.20");
    }

    function test_oiCapMultiplier_one() public view {
        assertEq(harness.oiCapMultiplier(WAD), WAD, "R=1 => 1.00");
    }

    function test_mmMultiplier_zero() public view {
        assertEq(harness.mmMultiplier(0), 3e18, "R=0 => 3.0");
    }

    function test_mmMultiplier_one() public view {
        assertEq(harness.mmMultiplier(WAD), WAD, "R=1 => 1.0");
    }

    function test_imMultiplier_matchesMM() public view {
        // Same formula
        assertEq(harness.imMultiplier(5e17), harness.mmMultiplier(5e17));
    }

    function test_executionDepthMult_zero() public view {
        assertEq(harness.executionDepthMultiplier(0), 3e17, "R=0 => 0.30");
    }

    function test_executionDepthMult_one() public view {
        assertEq(harness.executionDepthMultiplier(WAD), WAD, "R=1 => 1.00");
    }

    function test_borrowMttR_zero() public view {
        // R_borrow=0 => M_ttR = 1 + 24*(1-0) = 25
        assertEq(harness.borrowMttR(0), 25e18, "R_borrow=0 => 25x");
    }

    function test_borrowMttR_one() public view {
        // R_borrow=1 => M_ttR = 1 + 24*(1-1) = 1
        assertEq(harness.borrowMttR(WAD), WAD, "R_borrow=1 => 1x");
    }

    function test_oracleFrequency_zero() public view {
        assertEq(harness.oracleFrequency(0), 30e18, "R=0 => 30s");
    }

    function test_oracleFrequency_one() public view {
        assertEq(harness.oracleFrequency(WAD), 300e18, "R=1 => 300s");
    }

    function test_liquidationSLA_zero() public view {
        assertEq(harness.liquidationSLA(0), 15e18, "R=0 => 15s");
    }

    function test_liquidationSLA_one() public view {
        assertEq(harness.liquidationSLA(WAD), 90e18, "R=1 => 90s");
    }

    // ──────────────────────────────────────────────
    // Fuzz Tests
    // ──────────────────────────────────────────────

    function testFuzz_computeR_bounded(uint256 tauEff) public view {
        tauEff = bound(tauEff, 0, 1000e18); // 0 to 1000 hours
        uint256 r = harness.computeR(tauEff);
        assertLe(r, WAD, "R always <= 1.0");
    }

    function testFuzz_computeRBorrow_bounded(uint256 tauEff) public view {
        tauEff = bound(tauEff, 0, 1000e18);
        uint256 r = harness.computeRBorrow(tauEff);
        assertLe(r, WAD, "R_borrow always <= 1.0");
    }

    function testFuzz_tauEffective_leq_tau(uint256 tau) public view {
        tau = bound(tau, 0, 10000e18);
        uint256 notLive = harness.computeTauEffective(tau, false);
        uint256 live = harness.computeTauEffective(tau, true);
        assertEq(notLive, tau);
        assertLe(live, tau, "Live tau always <= original tau");
    }

    function testFuzz_volFactor_bounded(uint256 sigma, uint256 baseline) public view {
        sigma = bound(sigma, 0, 10e18);
        baseline = bound(baseline, 0, 10e18);
        uint256 vf = harness.computeVolFactor(sigma, baseline);
        assertLe(vf, WAD, "Vol factor <= 1.0");
    }

    function testFuzz_concFactor_bounded(uint256 market, uint256 global) public view {
        market = bound(market, 0, 100e18);
        global = bound(global, 1, 100e18); // avoid div by zero
        uint256 cf = harness.computeConcentrationFactor(market, global);
        assertGe(cf, 5e17, "Concentration factor >= 0.50");
        assertLe(cf, WAD, "Concentration factor <= 1.0");
    }

    function testFuzz_paramMappings_bounded(uint256 rAdj) public view {
        rAdj = bound(rAdj, 0, WAD);

        assertLe(harness.oiCapMultiplier(rAdj), WAD);
        assertGe(harness.oiCapMultiplier(rAdj), 2e17);

        assertLe(harness.mmMultiplier(rAdj), 3e18);
        assertGe(harness.mmMultiplier(rAdj), WAD);

        assertLe(harness.executionDepthMultiplier(rAdj), WAD);
        assertGe(harness.executionDepthMultiplier(rAdj), 3e17);

        assertLe(harness.borrowMttR(rAdj), 25e18);
        assertGe(harness.borrowMttR(rAdj), WAD);
    }
}
