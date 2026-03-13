// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IFundingRateEngine
/// @notice Trader↔trader periodic payments. Heavy side pays light side.
///         Matched OI is zero-sum between traders. Unmatched OI goes to LP pool.
///         Funding does NOT go through 50/30/20 split.
interface IFundingRateEngine {
    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event FundingIndexUpdated(bytes32 indexed marketId, int256 longIndex, int256 shortIndex, int256 rate, uint256 timestamp);
    event UnmatchedFundingRouted(bytes32 indexed marketId, uint256 amount, uint256 timestamp);

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Update the cumulative funding index for a market
    /// @dev Called on every PI update. Index-based accrual.
    /// @param marketId The market
    function accrueFunding(bytes32 marketId) external;

    /// @notice Route accumulated unmatched funding to the RewardsDistributor
    /// @dev Called periodically. Unmatched funding compensates LP for directional risk.
    /// @param marketId The market
    function routeUnmatchedFunding(bytes32 marketId) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get the current funding rate for a market
    /// @dev funding_rate = min(base × |imbalance| × multiplier, max_rate)
    /// @return rate Funding rate per hour (WAD, signed: positive = longs pay)
    function getCurrentFundingRate(bytes32 marketId) external view returns (int256 rate);

    /// @notice Get the funding rate escalation multiplier
    /// @dev funding_multiplier = 1.0 + (4.0 - 1.0) × (1 - R_adjusted)
    function getFundingMultiplier(bytes32 marketId) external view returns (uint256 multiplier);

    /// @notice Compute accrued funding for a position (signed)
    /// @dev Uses single-index pattern with direction negation:
    ///      accrued = -direction × posSize × (currentIndex - entryIndex)
    ///      Positive = received. Negative = paid.
    /// @return funding Positive = position received funding. Negative = position paid funding.
    function getAccruedFunding(uint256 positionId) external view returns (int256 funding);

    /// @notice Get current cumulative funding index for a market (single index, signed)
    /// @dev Positive rate (longs pay) → index increases. Negative rate → index decreases.
    function getFundingIndex(bytes32 marketId) external view returns (int256 index);

    /// @notice Get matched vs unmatched OI breakdown for a market
    /// @return matchedOI min(longOI, shortOI) (WAD)
    /// @return unmatchedOI |longOI - shortOI| (WAD)
    function getOISplit(bytes32 marketId) external view returns (uint256 matchedOI, uint256 unmatchedOI);

    /// @notice Get pending unmatched funding not yet routed to LP
    function getPendingUnmatchedFunding(bytes32 marketId) external view returns (uint256);

    /// @notice Compute funding index as of a specific timestamp (for settlement fee freeze)
    /// @dev Used by SettlementEngine to compute funding frozen at external resolution timestamp.
    ///      Single index — direction is applied in getAccruedFunding, not here.
    /// @param marketId The market
    /// @param asOfTimestamp The external resolution timestamp
    /// @return index The funding index at that timestamp (signed)
    function computeIndexAt(bytes32 marketId, uint256 asOfTimestamp)
        external view returns (int256 index);
}

