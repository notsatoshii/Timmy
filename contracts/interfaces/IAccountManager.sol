// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IAccountManager
/// @notice User accounts, collateral deposits/withdrawals, position ownership tracking.
interface IAccountManager {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error AccountManager__InsufficientBalance(address user, uint256 requested, uint256 available);
    error AccountManager__ZeroAmount();
    error AccountManager__PositionNotOwned(address user, uint256 positionId);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event PositionAssigned(address indexed user, uint256 indexed positionId);
    event PositionRemoved(address indexed user, uint256 indexed positionId);

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Deposit USDT collateral into trading account
    /// @param amount USDT amount (WAD)
    function deposit(uint256 amount) external;

    /// @notice Withdraw free collateral (not locked in positions)
    /// @param amount USDT amount (WAD)
    function withdraw(uint256 amount) external;

    /// @notice Lock collateral for a new position (called by ExecutionEngine)
    /// @param user Position owner
    /// @param amount Collateral to lock (WAD)
    function lockCollateral(address user, uint256 amount) external;

    /// @notice Release collateral when position closes (called by ExecutionEngine/LiquidationEngine)
    /// @param user Position owner
    /// @param amount Collateral to release (WAD)
    function releaseCollateral(address user, uint256 amount) external;

    /// @notice Credit PnL to user (called on position close)
    /// @param user Recipient
    /// @param amount Amount to credit (WAD)
    function creditPnL(address user, uint256 amount) external;

    /// @notice Debit PnL from user (called on position close with loss)
    /// @dev Caps at balance — remainder returned as bad debt for InsuranceFund
    /// @param user Position owner
    /// @param amount Amount to debit (WAD)
    /// @return badDebt Amount that could not be debited (WAD)
    function debitPnL(address user, uint256 amount) external returns (uint256 badDebt);

    /// @notice Assign a position to a user (called by ExecutionEngine on position open)
    /// @param user Position owner
    /// @param positionId Position identifier
    function assignPosition(address user, uint256 positionId) external;

    /// @notice Remove a position from a user (called on position close)
    /// @param user Position owner
    /// @param positionId Position identifier
    function removePosition(address user, uint256 positionId) external;

    /// @notice Transfer USDT out to another contract (e.g. LeverVault on trader loss)
    /// @dev Called by ExecutionEngine when a trader closes with a net loss.
    ///      The loss amount is sent back to the LP pool.
    /// @param to Destination address (LeverVault)
    /// @param amount USDT amount to transfer (WAD)
    function transferOut(address to, uint256 amount) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get total deposited balance for a user
    function getBalance(address user) external view returns (uint256);

    /// @notice Get free (unlocked) collateral available for new positions or withdrawal
    function getFreeCollateral(address user) external view returns (uint256);

    /// @notice Get total locked collateral across all positions
    function getLockedCollateral(address user) external view returns (uint256);

    /// @notice Get all position IDs owned by a user
    function getUserPositions(address user) external view returns (uint256[] memory);
}

