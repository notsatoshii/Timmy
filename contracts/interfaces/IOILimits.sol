// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IOILimits
/// @notice Four-tier OI cap system: global, per-market (dynamic), per-side, per-user.
///         Every cap is dynamic — scales with TVL, compresses with R(τ).
interface IOILimits {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error OILimits__GlobalCapExceeded(uint256 currentOI, uint256 cap);
    error OILimits__MarketCapExceeded(bytes32 marketId, uint256 currentOI, uint256 cap);
    error OILimits__SideCapExceeded(bytes32 marketId, bool isLong, uint256 currentOI, uint256 cap);
    error OILimits__UserCapExceeded(bytes32 marketId, address user, uint256 currentOI, uint256 cap);
    error OILimits__MarketHasOpenPositions(bytes32 marketId, uint256 count);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event OIIncreased(bytes32 indexed marketId, bool isLong, uint256 amount, uint256 newTotal);
    event OIDecreased(bytes32 indexed marketId, bool isLong, uint256 amount, uint256 newTotal);
    event OIReset(bytes32 indexed marketId, uint256 clearedAmount, uint256 userCount);

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Record OI increase when a position opens
    /// @dev Called by ExecutionEngine. Reverts if any of the four caps would be exceeded.
    /// @param marketId Market identifier
    /// @param user Position owner
    /// @param isLong True for long, false for short
    /// @param notional Position notional to add (WAD)
    function increaseOI(bytes32 marketId, address user, bool isLong, uint256 notional) external;

    /// @notice Record OI decrease when a position closes, is liquidated, or settles
    /// @param marketId Market identifier
    /// @param user Position owner
    /// @param isLong True for long, false for short
    /// @param notional Position notional to remove (WAD)
    function decreaseOI(bytes32 marketId, address user, bool isLong, uint256 notional) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Tier 1: Global OI cap = TVL × 0.60
    function getGlobalOICap() external view returns (uint256);

    /// @notice Current total global OI across all markets
    function getGlobalOI() external view returns (uint256);

    /// @notice Tier 2: Per-market OI cap (dynamic, compresses with R(τ))
    function getMarketOICap(bytes32 marketId) external view returns (uint256);

    /// @notice Current total OI for a specific market (both sides)
    function getMarketOI(bytes32 marketId) external view returns (uint256);

    /// @notice Tier 3: Per-side OI cap = Market_OI_Cap × 0.70
    function getSideOICap(bytes32 marketId) external view returns (uint256);

    /// @notice Current OI for a specific side of a market
    function getSideOI(bytes32 marketId, bool isLong) external view returns (uint256);

    /// @notice Tier 4: Per-user OI cap = Market_OI_Cap × 0.20
    function getUserOICap(bytes32 marketId) external view returns (uint256);

    /// @notice Current OI for a specific user in a market
    function getUserOI(bytes32 marketId, address user) external view returns (uint256);

    /// @notice Check if a new position would pass all four tier checks
    function canIncreaseOI(bytes32 marketId, address user, bool isLong, uint256 notional)
        external view returns (bool);

    /// @notice Get the imbalance ratio for a market: (longOI - shortOI) / (longOI + shortOI)
    /// @return ratio Signed imbalance ratio (WAD). Positive = long-heavy.
    function getImbalanceRatio(bytes32 marketId) external view returns (int256 ratio);

    /// @notice Get market utilization: market_OI / market_OI_cap
    function getMarketUtilization(bytes32 marketId) external view returns (uint256);

    /// @notice Get global utilization: global_OI / global_OI_cap
    function getGlobalUtilization() external view returns (uint256);

    /// @notice Clear ghost OI for a market with on-chain safety check and per-user OI clearing
    /// @param marketId The market to reset
    /// @param affectedUsers Users whose per-user OI to clear
    function adminResetMarketOIFull(bytes32 marketId, address[] calldata affectedUsers) external;
}

