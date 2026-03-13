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
    // Core Risk Functions (TODO: implement)
    // ──────────────────────────────────────────────

    function computeTauEffective(uint256 tau, bool isLive) internal pure returns (uint256 tauEffective) {
        revert("NOT_IMPLEMENTED");
    }

    function computeR(uint256 tauEffective) internal pure returns (uint256 r) {
        revert("NOT_IMPLEMENTED");
    }

    function computeRBorrow(uint256 tauEffective) internal pure returns (uint256 rBorrow) {
        revert("NOT_IMPLEMENTED");
    }

    function computeVolFactor(uint256 sigmaCurrent, uint256 sigmaBaseline)
        internal pure returns (uint256 volFactor)
    {
        revert("NOT_IMPLEMENTED");
    }

    function computeDepthFactor(uint256 externalDepth, uint256 depthThreshold)
        internal pure returns (uint256 depthFactor)
    {
        revert("NOT_IMPLEMENTED");
    }

    function computeConcentrationFactor(uint256 marketOI, uint256 globalOI)
        internal pure returns (uint256 concFactor)
    {
        revert("NOT_IMPLEMENTED");
    }

    function computeMarketAdjustment(
        uint256 sigmaCurrent,
        uint256 sigmaBaseline,
        uint256 externalDepth,
        uint256 depthThreshold,
        uint256 marketOI,
        uint256 globalOI
    ) internal pure returns (uint256 mMarket) {
        revert("NOT_IMPLEMENTED");
    }

    function computeRAdjusted(uint256 r, uint256 mMarket) internal pure returns (uint256 rAdjusted) {
        revert("NOT_IMPLEMENTED");
    }

    // ──────────────────────────────────────────────
    // Parameter Mappings (TODO: implement)
    // ──────────────────────────────────────────────

    function leverageCompression(uint256 rAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function oiCapMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function mmMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function imMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function executionDepthMultiplier(uint256 rAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function borrowMttR(uint256 rBorrowAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function oracleFrequency(uint256 rAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function liquidationSLA(uint256 rAdjusted) internal pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }
}
