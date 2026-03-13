// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IFeeRouter
/// @notice Deterministic fee split. Routes all protocol fees through 50/30/20
///         (LP/Protocol/Insurance). Tier 2 when IFR ≥ 20%: 50/50/0.
///         Funding payments are NOT routed here — they go directly to counterparties.
interface IFeeRouter {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error FeeRouter__ZeroAmount();
    error FeeRouter__UnauthorizedCaller(address caller);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event FeesRouted(
        uint8 indexed feeType,      // 0=borrow, 1=tx, 2=liquidation, 3=settlement
        uint256 totalAmount,
        uint256 lpShare,
        uint256 protocolShare,
        uint256 insuranceShare,
        uint8 tier                   // 1 or 2
    );

    event TierChanged(uint8 oldTier, uint8 newTier, uint256 currentIFR);

    // ──────────────────────────────────────────────
    // Enums
    // ──────────────────────────────────────────────

    enum FeeType { BORROW, TRANSACTION, LIQUIDATION, SETTLEMENT }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Route a fee payment through the split
    /// @dev Called by BorrowFeeEngine, ExecutionEngine, LiquidationEngine, SettlementEngine.
    /// @param feeType Type of fee being routed
    /// @param amount Total fee amount (WAD, USDT)
    function routeFees(FeeType feeType, uint256 amount) external;

    /// @notice Collect a transaction fee on position open/close
    /// @dev TX_FEE = 0.10% (10 bps) of notional
    /// @param notional Position notional (WAD)
    /// @return fee The fee collected (WAD)
    function collectTransactionFee(uint256 notional) external returns (uint256 fee);

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get current fee tier (1 or 2)
    /// @dev Tier 1: IFR < 20% → 50/30/20. Tier 2: IFR ≥ 20% → 50/50/0.
    function getCurrentTier() external view returns (uint8 tier);

    /// @notice Get the current split percentages
    /// @return lpPct LP share (WAD)
    /// @return protocolPct Protocol share (WAD)
    /// @return insurancePct Insurance share (WAD)
    function getCurrentSplit() external view returns (uint256 lpPct, uint256 protocolPct, uint256 insurancePct);

    /// @notice Preview how a fee amount would be split under current conditions
    function previewSplit(uint256 amount)
        external view returns (uint256 lpShare, uint256 protocolShare, uint256 insuranceShare);

    /// @notice Get total fees routed lifetime by type
    function getTotalFeesRouted(FeeType feeType) external view returns (uint256);

    /// @notice Get protocol treasury address
    function protocolTreasury() external view returns (address);
}

