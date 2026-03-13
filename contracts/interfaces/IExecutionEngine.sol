// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IExecutionEngine
/// @notice Orchestrates position opens/closes. Computes entry/exit prices via
///         PI + imbalance-adjusted linear impact using imbalance_delta.
///         NOT a vAMM. Impact is PI-independent (no boundary blowup).
///         Delegates position storage to PositionManager.
///
/// @dev Impact model (WP Section 10.2):
///   base_impact = trade_size / (market_depth × 2)
///   imbalance_delta = |imbalance_after| - |imbalance_before|
///   impact = min(base_impact × (1 + imbalance_delta × IMBALANCE_MULTIPLIER), MAX_IMPACT)
///   entry_price = PI × (1 ± impact)
interface IExecutionEngine {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error ExecutionEngine__MarketNotActive(bytes32 marketId);
    error ExecutionEngine__LeverageExceedsMax(uint256 requested, uint256 max);
    error ExecutionEngine__InsufficientCollateral(uint256 provided, uint256 required);
    error ExecutionEngine__OILimitBreached(string tier);
    error ExecutionEngine__MarketFrozen(bytes32 marketId);
    error ExecutionEngine__PositionNotFound(uint256 positionId);
    error ExecutionEngine__NotPositionOwner(uint256 positionId, address caller);
    error ExecutionEngine__ZeroSize();
    error ExecutionEngine__MarginCheckFailed(uint8 checkIndex);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event PositionOpened(
        uint256 indexed positionId,
        bytes32 indexed marketId,
        address indexed owner,
        bool isLong,
        uint256 collateral,
        uint256 leverage,
        uint256 entryPI,
        uint256 entryPrice,
        uint256 positionSize,
        uint256 impact,
        uint256 timestamp
    );

    event PositionClosed(
        uint256 indexed positionId,
        bytes32 indexed marketId,
        address indexed owner,
        uint256 exitPrice,
        int256 realizedPnL,
        uint256 borrowFeesPaid,
        int256 fundingPaid,
        uint256 timestamp
    );

    event CollateralAdded(uint256 indexed positionId, uint256 amount, uint256 newCollateral);
    event CollateralRemoved(uint256 indexed positionId, uint256 amount, uint256 newCollateral);

    // ──────────────────────────────────────────────
    // Structs
    // ──────────────────────────────────────────────

    struct OpenParams {
        bytes32 marketId;
        bool isLong;
        uint256 collateral;     // USDT amount (WAD)
        uint256 leverage;       // Requested leverage (WAD, e.g., 5e18 = 5×)
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Open a new leveraged position
    /// @dev Runs the full 10-step margin check sequence (WP Section 11.6):
    ///   1. Validate leverage ≤ Effective_Max_Leverage
    ///   2. Compute notional = collateral × leverage
    ///   3. Check all four OI tiers
    ///   4. Compute execution price via impact model
    ///   5. Compute IM_final with all adjustments
    ///   6. Verify collateral ≥ IM_final
    ///   7. Deduct TX fee, verify collateral_net ≥ IM_final
    ///   8. Verify collateral_net > MM
    ///   9. Verify MR > liquidation threshold + buffer
    ///   10. Execute: store position, update OI, begin fee accrual
    /// @param params Position parameters
    /// @return positionId Unique position identifier (from PositionManager)
    function openPosition(OpenParams calldata params) external returns (uint256 positionId);

    /// @notice Close an existing position voluntarily
    /// @param positionId Position to close
    function closePosition(uint256 positionId) external;

    /// @notice Add collateral to an existing position (reduces liquidation risk)
    /// @param positionId Position to modify
    /// @param amount Additional collateral in USDT (WAD)
    function addCollateral(uint256 positionId, uint256 amount) external;

    /// @notice Remove excess collateral from a position
    /// @dev Subject to withdrawal buffer constraint (MR must stay above buffer after removal)
    /// @param positionId Position to modify
    /// @param amount Collateral to remove in USDT (WAD)
    function removeCollateral(uint256 positionId, uint256 amount) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Compute execution price for a hypothetical trade (preview only)
    /// @dev Uses imbalance_delta model: |imbalance_after| - |imbalance_before|
    /// @param marketId The market
    /// @param isLong Direction
    /// @param notional Trade size (WAD)
    /// @param isOpen True = opening position, false = closing position
    /// @return price Execution price (WAD)
    /// @return impact Effective impact applied (WAD), after cap
    function previewExecution(bytes32 marketId, bool isLong, uint256 notional, bool isOpen)
        external view returns (uint256 price, uint256 impact);

    /// @notice Compute base impact for a trade size (before imbalance adjustment)
    /// @dev base_impact = trade_size / (market_depth × 2)
    function computeBaseImpact(bytes32 marketId, uint256 tradeSize)
        external view returns (uint256 impact);

    /// @notice Compute imbalance_delta for a hypothetical trade
    /// @dev imbalance_delta = |imbalance_after| - |imbalance_before|
    function computeImbalanceDelta(bytes32 marketId, bool isLong, uint256 notional)
        external view returns (int256 delta);

    /// @notice Get the current market depth for execution purposes
    /// @dev market_depth = Market_OI_Cap × Execution_Depth_Mult(R_adjusted)
    function getMarketDepth(bytes32 marketId) external view returns (uint256 depth);
}

