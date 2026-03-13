// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title RiskCurves
/// @notice Computes R(τ), R_borrow(τ), τ_effective, and all parameter mappings.
/// @dev Pure math library. No state. Consumed by LeverageModel, OILimits, MarginEngine,
///      BorrowFeeEngine, FundingRateEngine, ExecutionEngine.
library RiskCurves {
    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant LAMBDA = 2e18;                    // Steepness factor
    uint256 internal constant TAU_REF = 24;                     // hours — mechanical curve
    uint256 internal constant TAU_REF_BORROW = 168;             // hours — borrow curve (1 week)
    uint256 internal constant LIVE_COMPRESSION = 7e17;          // 0.70
    uint256 internal constant CONCENTRATION_THRESHOLD = 15e16;  // 0.15 (15%)
    uint256 internal constant CONCENTRATION_FLOOR = 5e17;       // 0.50

    // ──────────────────────────────────────────────
    // Core Risk Functions
    // ──────────────────────────────────────────────

    /// @notice Compute effective time-to-resolution accounting for live compression
    /// @param tau Raw hours to resolution (WAD)
    /// @param isLive Whether the underlying event is currently in progress
    /// @return tauEffective Compressed time in hours (WAD)
    function computeTauEffective(uint256 tau, bool isLive) internal pure returns (uint256 tauEffective);

    /// @notice Compute the mechanical risk factor R(τ)
    /// @dev R(τ) = 1 - e^(-λ × τ_effective / τ_ref)
    /// @param tauEffective Effective hours to resolution (WAD)
    /// @return r Risk factor [0, 1] in WAD. 1 = full flexibility, 0 = max tightening.
    function computeR(uint256 tauEffective) internal pure returns (uint256 r);

    /// @notice Compute the borrow risk factor R_borrow(τ)
    /// @dev R_borrow(τ) = 1 - e^(-λ × τ_effective / τ_ref_borrow)
    /// @param tauEffective Effective hours to resolution (WAD)
    /// @return rBorrow Borrow risk factor [0, 1] in WAD
    function computeRBorrow(uint256 tauEffective) internal pure returns (uint256 rBorrow);

    // ──────────────────────────────────────────────
    // Market-Specific Adjustments
    // ──────────────────────────────────────────────

    /// @notice Compute volatility factor for a market
    /// @dev Vol_Factor = 1 / (1 + max(0, σ_current - σ_baseline))
    /// @param sigmaCurrent Current PI volatility (WAD)
    /// @param sigmaBaseline Baseline PI volatility (WAD)
    /// @return volFactor [0, 1] in WAD
    function computeVolFactor(uint256 sigmaCurrent, uint256 sigmaBaseline)
        internal pure returns (uint256 volFactor);

    /// @notice Compute depth factor for a market
    /// @dev Depth_Factor = min(1.0, external_depth / depth_threshold)
    /// @param externalDepth Current external market depth (WAD)
    /// @param depthThreshold Required minimum depth (WAD)
    /// @return depthFactor [0, 1] in WAD
    function computeDepthFactor(uint256 externalDepth, uint256 depthThreshold)
        internal pure returns (uint256 depthFactor);

    /// @notice Compute concentration factor for a market
    /// @dev Concentration_Factor = max(0.5, 1 - 2 × max(0, C - 0.15))
    /// @param marketOI Market's open interest (WAD)
    /// @param globalOI Platform's total open interest (WAD)
    /// @return concFactor [0.5, 1.0] in WAD
    function computeConcentrationFactor(uint256 marketOI, uint256 globalOI)
        internal pure returns (uint256 concFactor);

    /// @notice Compute combined market adjustment M_market
    /// @dev M_market = min(1.0, volFactor × depthFactor × concentrationFactor)
    /// @return mMarket [0, 1] in WAD. Can only reduce risk capacity.
    function computeMarketAdjustment(
        uint256 sigmaCurrent,
        uint256 sigmaBaseline,
        uint256 externalDepth,
        uint256 depthThreshold,
        uint256 marketOI,
        uint256 globalOI
    ) internal pure returns (uint256 mMarket);

    /// @notice Compute adjusted risk factor: R_adjusted = R(τ) × M_market
    function computeRAdjusted(uint256 r, uint256 mMarket) internal pure returns (uint256 rAdjusted);

    // ──────────────────────────────────────────────
    // Parameter Mappings
    // ──────────────────────────────────────────────

    /// @notice Leverage_Compression = R_adjusted
    function leverageCompression(uint256 rAdjusted) internal pure returns (uint256);

    /// @notice OI_Cap_Multiplier = 0.20 + R_adjusted × 0.80
    function oiCapMultiplier(uint256 rAdjusted) internal pure returns (uint256);

    /// @notice MM_Multiplier = 3.0 - R_adjusted × 2.0
    function mmMultiplier(uint256 rAdjusted) internal pure returns (uint256);

    /// @notice IM_Multiplier = 3.0 - R_adjusted × 2.0
    function imMultiplier(uint256 rAdjusted) internal pure returns (uint256);

    /// @notice Execution_Depth_Mult = 0.30 + R_adjusted × 0.70
    function executionDepthMultiplier(uint256 rAdjusted) internal pure returns (uint256);

    /// @notice Borrow_M_ttR = 1.0 + (25.0 - 1.0) × (1 - R_borrow_adjusted)
    function borrowMttR(uint256 rBorrowAdjusted) internal pure returns (uint256);

    /// @notice Oracle_Frequency = 30 + R_adjusted × 270 (seconds)
    function oracleFrequency(uint256 rAdjusted) internal pure returns (uint256);

    /// @notice Liquidation_SLA = 15 + R_adjusted × 75 (seconds)
    function liquidationSLA(uint256 rAdjusted) internal pure returns (uint256);
}

