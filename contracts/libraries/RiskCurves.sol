// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FixedPointMath } from "./FixedPointMath.sol";

/// @title RiskCurves
/// @notice Computes R(τ), R_borrow(τ), τ_effective, and all parameter mappings.
/// @dev Pure math library. No state. Consumed by LeverageModel, OILimits, MarginEngine,
///      BorrowFeeEngine, FundingRateEngine, ExecutionEngine.
library RiskCurves {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;

    // ──────────────────────────────────────────────
    // Custom Errors
    // ──────────────────────────────────────────────

    error RiskCurves__ZeroDepthThreshold();

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;
    uint256 internal constant LAMBDA = 2e18;                    // Steepness factor
    uint256 internal constant TAU_REF = 24;                     // hours — mechanical curve
    uint256 internal constant TAU_REF_BORROW = 168;             // hours — borrow curve (1 week)
    uint256 internal constant LIVE_COMPRESSION = 7e17;          // 0.70
    uint256 internal constant CONCENTRATION_THRESHOLD = 15e16;  // 0.15 (15%)
    uint256 internal constant CONCENTRATION_FLOOR = 5e17;       // 0.50

    // WAD-encoded tau references for division
    uint256 internal constant TAU_REF_WAD = 24e18;
    uint256 internal constant TAU_REF_BORROW_WAD = 168e18;

    // ──────────────────────────────────────────────
    // Core Risk Functions
    // ──────────────────────────────────────────────

    /// @notice Compute τ_effective = τ × (1 - live_compression × is_live)
    /// @param tau Time-to-resolution in hours (WAD)
    /// @param isLive Whether the underlying event is in progress
    /// @return tauEffective Effective τ in hours (WAD)
    function computeTauEffective(uint256 tau, bool isLive) internal pure returns (uint256 tauEffective) {
        if (!isLive) return tau;
        // τ_effective = τ × (1 - 0.70) = τ × 0.30
        tauEffective = tau.wadMul(WAD - LIVE_COMPRESSION);
    }

    /// @notice Compute R(τ) = 1 - e^(-λ × τ_effective / τ_ref)
    /// @param tauEffective Effective τ in hours (WAD)
    /// @return r Risk factor [0, WAD)
    function computeR(uint256 tauEffective) internal pure returns (uint256 r) {
        if (tauEffective == 0) return 0;

        // exponent = -λ × τ_effective / τ_ref
        // = -(2.0 × tauEffective / 24.0)
        uint256 ratio = tauEffective.wadDiv(TAU_REF_WAD);
        uint256 lambdaTimesRatio = LAMBDA.wadMul(ratio);

        // e^(-x) where x = lambdaTimesRatio
        uint256 expNeg = FixedPointMath.wadExp(-int256(lambdaTimesRatio));

        // R = 1 - e^(-x)
        if (expNeg >= WAD) return 0;
        r = WAD - expNeg;
    }

    /// @notice Compute R_borrow(τ) = 1 - e^(-λ × τ_effective / τ_ref_borrow)
    /// @param tauEffective Effective τ in hours (WAD)
    /// @return rBorrow Borrow risk factor [0, WAD)
    function computeRBorrow(uint256 tauEffective) internal pure returns (uint256 rBorrow) {
        if (tauEffective == 0) return 0;

        // exponent = -λ × τ_effective / τ_ref_borrow
        // = -(2.0 × tauEffective / 168.0)
        uint256 ratio = tauEffective.wadDiv(TAU_REF_BORROW_WAD);
        uint256 lambdaTimesRatio = LAMBDA.wadMul(ratio);

        uint256 expNeg = FixedPointMath.wadExp(-int256(lambdaTimesRatio));

        if (expNeg >= WAD) return 0;
        rBorrow = WAD - expNeg;
    }

    /// @notice Compute Vol_Factor = 1 / (1 + max(0, σ_current - σ_baseline))
    /// @param sigmaCurrent Current volatility (WAD)
    /// @param sigmaBaseline Baseline volatility (WAD)
    /// @return volFactor Vol factor in [0, WAD]
    function computeVolFactor(
        uint256 sigmaCurrent,
        uint256 sigmaBaseline
    ) internal pure returns (uint256 volFactor) {
        if (sigmaCurrent <= sigmaBaseline) return WAD;

        uint256 excess = sigmaCurrent - sigmaBaseline;
        // 1 / (1 + excess) in WAD
        volFactor = WAD.wadDiv(WAD + excess);
    }

    /// @notice Compute Depth_Factor = min(1.0, external_depth / depth_threshold)
    /// @param externalDepth External market depth (WAD)
    /// @param depthThreshold Depth threshold (WAD)
    /// @return depthFactor Depth factor in [0, WAD]
    function computeDepthFactor(
        uint256 externalDepth,
        uint256 depthThreshold
    ) internal pure returns (uint256 depthFactor) {
        if (depthThreshold == 0) revert RiskCurves__ZeroDepthThreshold();
        if (externalDepth >= depthThreshold) return WAD;

        depthFactor = externalDepth.wadDiv(depthThreshold);
    }

    /// @notice Compute Concentration_Factor = max(0.5, 1 - 2 × max(0, C - 0.15))
    ///         where C = market_OI / global_OI
    /// @param marketOI Market open interest (WAD)
    /// @param globalOI Global open interest (WAD)
    /// @return concFactor Concentration factor in [CONCENTRATION_FLOOR, WAD]
    function computeConcentrationFactor(
        uint256 marketOI,
        uint256 globalOI
    ) internal pure returns (uint256 concFactor) {
        if (globalOI == 0 || marketOI == 0) return WAD;

        uint256 c = marketOI.wadDiv(globalOI);

        if (c <= CONCENTRATION_THRESHOLD) return WAD;

        // penalty = 2 × (C - 0.15)
        uint256 excess = c - CONCENTRATION_THRESHOLD;
        uint256 penalty = 2 * excess; // 2× in WAD is just multiply by 2

        if (penalty >= WAD - CONCENTRATION_FLOOR) {
            return CONCENTRATION_FLOOR;
        }

        concFactor = WAD - penalty;
        if (concFactor < CONCENTRATION_FLOOR) {
            concFactor = CONCENTRATION_FLOOR;
        }
    }

    /// @notice Compute M_market = min(1.0, Vol_Factor × Depth_Factor × Concentration_Factor)
    /// @param sigmaCurrent Current volatility (WAD)
    /// @param sigmaBaseline Baseline volatility (WAD)
    /// @param externalDepth External market depth (WAD)
    /// @param depthThreshold Depth threshold (WAD)
    /// @param marketOI Market open interest (WAD)
    /// @param globalOI Global open interest (WAD)
    /// @return mMarket Market adjustment factor in [0, WAD]
    function computeMarketAdjustment(
        uint256 sigmaCurrent,
        uint256 sigmaBaseline,
        uint256 externalDepth,
        uint256 depthThreshold,
        uint256 marketOI,
        uint256 globalOI
    ) internal pure returns (uint256 mMarket) {
        uint256 vf = computeVolFactor(sigmaCurrent, sigmaBaseline);
        uint256 df = computeDepthFactor(externalDepth, depthThreshold);
        uint256 cf = computeConcentrationFactor(marketOI, globalOI);

        mMarket = vf.wadMul(df).wadMul(cf);
        if (mMarket > WAD) mMarket = WAD;
    }

    /// @notice Compute R_adjusted = R(τ) × M_market
    /// @param r Risk factor from computeR (WAD)
    /// @param mMarket Market adjustment from computeMarketAdjustment (WAD)
    /// @return rAdjusted Adjusted risk factor (WAD)
    function computeRAdjusted(uint256 r, uint256 mMarket) internal pure returns (uint256 rAdjusted) {
        rAdjusted = r.wadMul(mMarket);
    }

    // ──────────────────────────────────────────────
    // Parameter Mappings
    // ──────────────────────────────────────────────

    /// @notice Leverage_Compression = R_adjusted
    /// @param rAdjusted Adjusted risk factor (WAD)
    /// @return Leverage compression factor (WAD)
    function leverageCompression(uint256 rAdjusted) internal pure returns (uint256) {
        return rAdjusted;
    }

    /// @notice OI_Cap_Multiplier = 0.20 + R_adjusted × 0.80
    /// @param rAdjusted Adjusted risk factor (WAD)
    /// @return OI cap multiplier (WAD) in [0.20, 1.00]
    function oiCapMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        // 0.20 + R_adjusted × 0.80
        return 2e17 + rAdjusted.wadMul(8e17);
    }

    /// @notice MM_Multiplier = 3.0 - R_adjusted × 2.0
    /// @dev Higher R_adjusted (far from resolution) = lower MM multiplier (more relaxed)
    ///      Lower R_adjusted (near resolution) = higher MM multiplier (more strict)
    /// @param rAdjusted Adjusted risk factor (WAD)
    /// @return MM multiplier (WAD) in [1.0, 3.0]
    function mmMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        // 3.0 - R_adjusted × 2.0
        return 3e18 - rAdjusted.wadMul(2e18);
    }

    /// @notice IM_Multiplier = 3.0 - R_adjusted × 2.0
    /// @param rAdjusted Adjusted risk factor (WAD)
    /// @return IM multiplier (WAD) in [1.0, 3.0]
    function imMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        // Same formula as MM
        return 3e18 - rAdjusted.wadMul(2e18);
    }

    /// @notice Execution_Depth_Mult = 0.30 + R_adjusted × 0.70
    /// @param rAdjusted Adjusted risk factor (WAD)
    /// @return Execution depth multiplier (WAD) in [0.30, 1.00]
    function executionDepthMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        return 3e17 + rAdjusted.wadMul(7e17);
    }

    /// @notice Borrow_M_ttR = 1.0 + (25.0 - 1.0) × (1 - R_borrow_adjusted)
    /// @dev Lower R_borrow = near resolution = higher multiplier = higher borrow rate
    /// @param rBorrowAdjusted Adjusted borrow risk factor (WAD)
    /// @return Borrow time-to-resolution multiplier (WAD) in [1.0, 25.0]
    function borrowMttR(uint256 rBorrowAdjusted) internal pure returns (uint256) {
        // 1.0 + 24.0 × (1 - R_borrow_adjusted)
        uint256 complement = WAD - rBorrowAdjusted;
        return WAD + complement.wadMul(24e18);
    }

    /// @notice Oracle_Frequency = 30 + R_adjusted × 270 (seconds, WAD-encoded)
    /// @param rAdjusted Adjusted risk factor (WAD)
    /// @return Oracle update frequency in seconds (WAD) in [30, 300]
    function oracleFrequency(uint256 rAdjusted) internal pure returns (uint256) {
        return 30e18 + rAdjusted.wadMul(270e18);
    }

    /// @notice Liquidation_SLA = 15 + R_adjusted × 75 (seconds, WAD-encoded)
    /// @param rAdjusted Adjusted risk factor (WAD)
    /// @return Liquidation SLA in seconds (WAD) in [15, 90]
    function liquidationSLA(uint256 rAdjusted) internal pure returns (uint256) {
        return 15e18 + rAdjusted.wadMul(75e18);
    }
}
