// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IBorrowFeeEngine
/// @notice Continuous fee on all leveraged positions. Five-multiplier formula.
///         The "ticking clock" that gives every leveraged position a finite lifespan.
///         1× positions are exempt.
interface IBorrowFeeEngine {
    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event BorrowIndexUpdated(bytes32 indexed marketId, bool isLong, uint256 newIndex, uint256 rate, uint256 timestamp);
    event BorrowFeesAccrued(uint256 indexed positionId, uint256 amount, uint256 timestamp);

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Update the cumulative borrow index for a market side
    /// @dev Should be called on every PI update. Index-based accrual (like Aave).
    /// @param marketId The market
    /// @param isLong Which side to update
    function accrueIndex(bytes32 marketId, bool isLong) external;

    /// @notice Force-accrue borrow index for all active markets
    /// @dev Called by keeper. Ensures indices stay current.
    function accrueAll() external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Compute the current borrow rate for a market side
    /// @dev borrow_rate = base_rate × M_ttR(R_borrow) × (1 + imbalance_surcharge)
    /// @param marketId The market
    /// @param isLong Which side (heavy side pays surcharge)
    /// @return ratePerHour Borrow rate per hour (WAD)
    function getCurrentBorrowRate(bytes32 marketId, bool isLong)
        external view returns (uint256 ratePerHour);

    /// @notice Get the time-to-resolution multiplier M_ttR for a market
    /// @dev M_ttR = 1.0 + (25.0 - 1.0) × (1 - R_borrow_adjusted)
    function getMttR(bytes32 marketId) external view returns (uint256 mttR);

    /// @notice Get the imbalance surcharge for a market side
    /// @dev surcharge = max(0, imbalance_ratio) × surcharge_factor (heavy side only)
    function getImbalanceSurcharge(bytes32 marketId, bool isLong) external view returns (uint256 surcharge);

    /// @notice Compute accrued borrow fees for a position since it opened
    /// @param positionId Position to check
    /// @return fees Total borrow fees accrued (WAD)
    function getAccruedFees(uint256 positionId) external view returns (uint256 fees);

    /// @notice Get the current cumulative borrow index for a market side
    function getBorrowIndex(bytes32 marketId, bool isLong) external view returns (uint256 index);

    /// @notice Get the annualized borrow rate for display purposes
    function getAnnualizedRate(bytes32 marketId, bool isLong) external view returns (uint256 annualized);

    /// @notice Compute borrow index as of a specific timestamp (for settlement fee freeze)
    /// @dev Used by SettlementEngine to compute fees frozen at external resolution timestamp.
    ///      Returns what the index WOULD HAVE BEEN at that timestamp.
    /// @param marketId The market
    /// @param isLong Which side
    /// @param asOfTimestamp The external resolution timestamp
    /// @return index The borrow index at that timestamp (WAD)
    function computeIndexAt(bytes32 marketId, bool isLong, uint256 asOfTimestamp)
        external view returns (uint256 index);
}

