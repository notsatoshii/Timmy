// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ILiquidationEngine
/// @notice Force-closes positions when equity < MM. Handles partial liquidation,
///         ordering, and bad debt waterfall. Continues during PENDING_RESOLUTION (2× MM).
interface ILiquidationEngine {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error LiquidationEngine__PositionNotLiquidatable(uint256 positionId, int256 equity, uint256 mm);
    error LiquidationEngine__PositionNotFound(uint256 positionId);
    error LiquidationEngine__MarketResolved(bytes32 marketId);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event PositionLiquidated(
        uint256 indexed positionId,
        bytes32 indexed marketId,
        address indexed owner,
        address liquidator,
        int256 equity,
        uint256 maintenanceMargin,
        uint256 liquidationFee,
        uint256 badDebt,
        uint256 timestamp
    );

    event PartialLiquidation(
        uint256 indexed positionId,
        uint256 sizeReduced,
        uint256 remainingSize,
        uint256 timestamp
    );

    event BadDebtRecorded(
        bytes32 indexed marketId,
        uint256 indexed positionId,
        uint256 amount,
        uint256 insurancePaid,
        uint256 adlAmount,
        uint256 timestamp
    );

    // ──────────────────────────────────────────────
    // Structs
    // ──────────────────────────────────────────────

    struct LiquidationResult {
        uint256 positionId;
        uint256 liquidationFee;     // Fee extracted from remaining equity
        int256 remainingEquity;     // Equity after fees (negative = bad debt)
        uint256 badDebt;            // Amount of bad debt (0 if equity ≥ 0)
        uint256 insurancePaid;      // Amount covered by insurance
        uint256 adlAmount;          // Amount to be covered by ADL
        bool isPartial;             // Whether partial liquidation was used
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Liquidate a single position that is below maintenance margin
    /// @dev Anyone can call (permissionless liquidation). Keeper incentivized by liquidation fee.
    /// @param positionId Position to liquidate
    /// @return result Full liquidation breakdown
    function liquidate(uint256 positionId) external returns (LiquidationResult memory result);

    /// @notice Batch liquidate multiple positions
    /// @dev Gas-efficient for keepers processing multiple liquidations.
    /// @param positionIds Array of positions to attempt liquidation
    /// @return results Array of results (failed liquidations have positionId = 0)
    function batchLiquidate(uint256[] calldata positionIds)
        external returns (LiquidationResult[] memory results);

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Check if a position is liquidatable
    /// @dev equity < MM + liquidation_buffer × notional
    function isLiquidatable(uint256 positionId) external view returns (bool);

    /// @notice Get all liquidatable positions for a market
    /// @dev Used by keepers to find work. Gas-heavy — use off-chain when possible.
    function getLiquidatablePositions(bytes32 marketId) external view returns (uint256[] memory);

    /// @notice Preview liquidation result without executing
    function previewLiquidation(uint256 positionId)
        external view returns (LiquidationResult memory result);

    /// @notice Get the liquidation fee rate: 1.0% (100 bps) of notional (WP 13.5)
    function getLiquidationFeeRate() external view returns (uint256);

    /// @notice Get the external liquidator bounty share: 10% of liquidation fee
    function getLiquidatorBountyShare() external view returns (uint256);

    /// @notice Get total bad debt generated lifetime
    function totalBadDebt() external view returns (uint256);

    /// @notice Get total liquidation fees collected lifetime
    function totalLiquidationFees() external view returns (uint256);
}

