// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ILeverageModel
/// @notice Three-step pipeline: Platform Ceiling → R(τ) compression → market-specific adjustment.
///         Produces Effective_Max_Leverage for any market at any time.
///
/// @dev CRITICAL: M_market is applied TWICE for leverage (WP Section 9.9):
///   - Once inside R_adjusted = R(τ) × M_market (via RiskCurves, affects ALL parameters)
///   - Once again as Step 3 Market_Adjustment (affects ONLY leverage)
///   This intentional compounding means market stress has DOUBLE impact on leverage,
///   because leverage is the single most dangerous parameter in the system.
interface ILeverageModel {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error LeverageModel__LeverageExceedsMax(uint256 requested, uint256 maxAllowed);
    error LeverageModel__LeverageBelowMinimum(uint256 requested);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event PlatformCeilingUpdated(uint256 newCeiling, uint256 tvlMult, uint256 ifrMult, uint256 utilMult);

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Step 1: Compute the platform leverage ceiling
    /// @dev Platform_Ceiling = Base_Max × TVL_Mult × IFR_Mult × Util_Mult
    /// @return ceiling Platform ceiling (WAD, e.g., 15e18 = 15×)
    function getPlatformCeiling() external view returns (uint256 ceiling);

    /// @notice TVL multiplier: min(1.0, max(0.10, (TVL/TVL_maturity)^0.5))
    function getTVLMultiplier() external view returns (uint256);

    /// @notice IFR multiplier: min(1.0, max(0.40, 0.40 + 0.60 × (IFR/IFR_target)))
    function getIFRMultiplier() external view returns (uint256);

    /// @notice Utilization multiplier (WP 9.5):
    ///   max(0.30, 1.0 - 0.70 × max(0, (U_global - 0.30) / 0.70))
    function getUtilizationMultiplier() external view returns (uint256);

    /// @notice Step 2: Compressed leverage = Platform_Ceiling × R_adjusted
    /// @param marketId The market (to get R_adjusted)
    /// @return compressed Leverage after time/liveness compression (WAD)
    function getCompressedLeverage(bytes32 marketId) external view returns (uint256 compressed);

    /// @notice Step 3: Market-specific adjustment (SECOND application of M_market)
    /// @dev Market_Adjustment = min(1.0, Vol_Factor × Depth_Factor × Concentration_Factor)
    ///      This is the SAME formula as M_market in RiskCurves, applied AGAIN.
    /// @param marketId The market
    /// @return adjustment Market adjustment factor [0, 1] in WAD
    function getMarketAdjustment(bytes32 marketId) external view returns (uint256 adjustment);

    /// @notice Full pipeline: Effective_Max_Leverage = max(1.0, Compressed × Market_Adjustment)
    /// @param marketId The market
    /// @return maxLeverage Effective max leverage (WAD). Never below 1e18 (1×).
    function getEffectiveMaxLeverage(bytes32 marketId) external view returns (uint256 maxLeverage);

    /// @notice Validate that a requested leverage is within limits for a market
    /// @param marketId The market
    /// @param leverage Requested leverage (WAD)
    /// @return valid True if leverage <= effective max
    function validateLeverage(bytes32 marketId, uint256 leverage) external view returns (bool valid);
}

