// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ISettlementEngine
/// @notice Binary event resolution. PI snaps to 0 or 1. Computes settlement payouts.
///         Handles bad debt waterfall: insurance → ADL → LP socialization.
///         Void handling: all positions refund at current equity, no settlement fee.
interface ISettlementEngine {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error SettlementEngine__MarketNotResolved(bytes32 marketId);
    error SettlementEngine__MarketNotPending(bytes32 marketId);
    error SettlementEngine__PositionAlreadySettled(uint256 positionId);
    error SettlementEngine__PositionNotInMarket(uint256 positionId, bytes32 marketId);
    error SettlementEngine__InvalidOutcome(uint8 outcome);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event MarketSettled(
        bytes32 indexed marketId,
        uint8 outcome,                  // 0 = NO, 1 = YES, 2 = VOID
        uint256 totalWinnerPayout,
        uint256 totalLoserDebt,
        uint256 totalBadDebt,
        uint256 settlementFeesCollected,
        uint256 timestamp
    );

    event PositionSettled(
        uint256 indexed positionId,
        bytes32 indexed marketId,
        address indexed owner,
        bool isWinner,
        int256 outcomePnL,
        uint256 settlementFee,
        uint256 payout,
        uint256 timestamp
    );

    event ADLApplied(
        bytes32 indexed marketId,
        uint256 totalBadDebt,
        uint256 insurancePaid,
        uint256 adlAmount,
        uint256 haircutBps,             // Basis points haircut applied to winners
        uint256 timestamp
    );

    event VoidSettlement(
        bytes32 indexed marketId,
        uint256 positionsRefunded,
        uint256 totalRefunded,
        uint256 timestamp
    );

    // ──────────────────────────────────────────────
    // Structs
    // ──────────────────────────────────────────────

    struct SettlementResult {
        uint256 positionId;
        bool isWinner;
        int256 outcomePnL;              // PnL from the binary outcome (WAD, signed)
        int256 finalEquity;             // After all fees (WAD, signed)
        uint256 settlementFee;          // 20 bps on notional, winners only (WAD)
        uint256 payout;                 // USDT to receive (WAD, 0 if loser/underwater)
        uint256 badDebt;                // If finalEquity < 0 (WAD)
    }

    struct MarketSettlementSummary {
        bytes32 marketId;
        uint8 outcome;
        uint256 totalPositions;
        uint256 winnerCount;
        uint256 loserCount;
        uint256 totalWinnerPayout;
        uint256 totalBadDebt;
        uint256 insuranceUsed;
        uint256 adlApplied;
        uint256 feesCollected;
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Initiate settlement for a resolved market
    /// @dev Called after MarketRegistry records the outcome. Processes all positions.
    ///      Triggers PI snap to 0 or 1, freezes fee accrual at external timestamp,
    ///      computes payouts, handles bad debt waterfall.
    /// @param marketId The resolved market
    function settleMarket(bytes32 marketId) external;

    /// @notice Claim settlement payout for an individual position
    /// @dev Permissionless — anyone can call for any position. Individual claim model.
    /// @param positionId The position to settle
    /// @return result Full settlement breakdown
    function claimSettlement(uint256 positionId) external returns (SettlementResult memory result);

    /// @notice Process void settlement for a cancelled market
    /// @dev All positions refund remaining equity. Accrued fees NOT reversed.
    ///      No settlement fee charged.
    /// @param marketId The voided market
    function settleVoid(bytes32 marketId) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Preview settlement result for a position (before claiming)
    function previewSettlement(uint256 positionId) external view returns (SettlementResult memory);

    /// @notice Get settlement summary for a market
    function getMarketSettlement(bytes32 marketId) external view returns (MarketSettlementSummary memory);

    /// @notice Check if a position has been settled
    function isSettled(uint256 positionId) external view returns (bool);

    /// @notice Get all unsettled position IDs for a resolved market
    function getUnsettledPositions(bytes32 marketId) external view returns (uint256[] memory);

    /// @notice Get the ADL haircut applied to a market (0 if no ADL)
    /// @return haircutWad Percentage haircut as WAD (e.g., 0.05e18 = 5% haircut)
    function getADLHaircut(bytes32 marketId) external view returns (uint256 haircutWad);

    /// @notice Check if a market has been fully settled (all positions claimed)
    function isFullySettled(bytes32 marketId) external view returns (bool);
}

