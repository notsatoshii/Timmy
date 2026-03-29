// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IMarginEngine
/// @notice Defines IM (initial margin), MM (maintenance margin), and real-time equity.
///         Creates the pincer effect: rising MM from below + borrow erosion from above.
interface IMarginEngine {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error MarginEngine__InsufficientCollateral(uint256 provided, uint256 required);
    error MarginEngine__BelowMaintenanceMargin(uint256 equity, uint256 mm);
    error MarginEngine__WithdrawalWouldBreachBuffer(uint256 postMR, uint256 required);
    error MarginEngine__PositionNotFound(uint256 positionId);

    // ──────────────────────────────────────────────
    // Structs
    // ──────────────────────────────────────────────

    struct EquityResult {
        int256 pnl;                 // Unrealized PnL from PI movement (WAD, signed)
        uint256 accruedBorrowFees;  // Total borrow fees accrued (WAD)
        int256 accruedFunding;      // Net funding paid/received (WAD, signed)
        int256 equity;              // Final equity = collateral + pnl - borrow + funding (WAD, signed. Funding: + = received)
        uint256 marginRatio;        // MR = equity / notional (WAD). 0 if equity <= 0.
    }

    struct MarginRequirements {
        uint256 initialMargin;      // IM required to open (WAD)
        uint256 maintenanceMargin;  // MM required to stay open (WAD)
        uint256 mmMultiplier;       // Current MM multiplier from R(τ) (WAD)
        uint256 imMultiplier;       // Current IM multiplier from R(τ) (WAD)
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Compute real-time equity for a position
    /// @dev Equity = Collateral + PnL(PI) - Accrued_Borrow_Fees + Accrued_Funding (funding: int256, + = received)
    /// @param positionId The position to evaluate
    /// @return result Full equity breakdown
    function computeEquity(uint256 positionId) external view returns (EquityResult memory result);

    /// @notice Compute margin requirements for a hypothetical new position
    /// @param marketId Target market
    /// @param notional Position notional (WAD)
    /// @param leverage Requested leverage (WAD)
    /// @return reqs IM and MM requirements
    function computeMarginRequirements(bytes32 marketId, uint256 notional, uint256 leverage)
        external view returns (MarginRequirements memory reqs);

    /// @notice Get current maintenance margin for an existing position
    /// @dev MM = base_mm × notional × MM_Multiplier(R_adjusted)
    function getMaintenanceMargin(uint256 positionId) external view returns (uint256 mm);

    /// @notice Get current initial margin requirements for a market
    /// @dev Includes volatility, risk factor, and utilization adjustments
    function getInitialMargin(bytes32 marketId, uint256 notional, uint256 leverage)
        external view returns (uint256 im);

    /// @notice Check if a position is eligible for liquidation
    /// @dev True when equity < MM + liquidation_buffer × notional
    function isLiquidatable(uint256 positionId) external view returns (bool);

    /// @notice Check if a position is in the warning zone (within 2× of liquidation)
    function isInDangerZone(uint256 positionId) external view returns (bool);

    /// @notice Validate a full margin check sequence for a new position
    /// @dev Runs all 10 checks from the whitepaper Section 11.6
    /// @return valid True if all checks pass
    /// @return failedCheck Index of failed check (0 if all pass)
    function validateMarginChecks(
        bytes32 marketId,
        address user,
        bool isLong,
        uint256 collateral,
        uint256 leverage
    ) external view returns (bool valid, uint8 failedCheck);

    /// @notice Check if collateral can be removed from a position
    /// @param positionId Position to modify
    /// @param amount Collateral to remove (WAD)
    /// @return allowed True if post-removal MR is above buffer
    function canRemoveCollateral(uint256 positionId, uint256 amount) external view returns (bool allowed);

    /// @notice Check if a market has configured risk parameters (depthThreshold > 0)
    function depthThreshold(bytes32 marketId) external view returns (uint256);
}

