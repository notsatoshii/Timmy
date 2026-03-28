// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ILeverVault
/// @notice ERC-4626 vault with tranche ledger for yield-carrying LP shares.
///         Deposits USDT → mints lvUSDT. NAV includes unrealized trader PnL.
///         Withdrawal via two-step queue (request → 48h → execute at current NAV).
///         Transfers use proportional tranche splitting (not FIFO/LIFO).
interface ILeverVault is IERC4626 {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error LeverVault__WithdrawalNotReady(uint256 receiptId, uint256 readyAt);
    error LeverVault__UtilizationTooHigh(uint256 postUtilization, uint256 maxUtilization);
    error LeverVault__NoWithdrawalRequest(uint256 receiptId);
    error LeverVault__NotReceiptOwner(uint256 receiptId, address caller);
    error LeverVault__CooldownActive(address user, uint256 cooldownEnds);
    error LeverVault__SharesInQueue(uint256 amount);
    error LeverVault__ZeroShares();

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event WithdrawalRequested(uint256 indexed receiptId, address indexed owner, uint256 shares, uint256 timestamp);
    event WithdrawalExecuted(uint256 indexed receiptId, address indexed owner, uint256 shares, uint256 assets, uint256 timestamp);
    event WithdrawalCancelled(uint256 indexed receiptId, address indexed owner, uint256 shares, uint256 timestamp);
    event TrancheConsolidated(address indexed holder, uint256 oldCount, uint256 newCount);

    // ──────────────────────────────────────────────
    // Structs
    // ──────────────────────────────────────────────

    struct Tranche {
        uint128 shares;             // Share count in this batch
        uint128 rewardSnapshot;     // Cumulative reward index at acquisition
    }

    struct WithdrawalReceipt {
        uint256 id;
        address owner;
        uint256 shares;
        uint256 requestTimestamp;
        bool executed;
        bool cancelled;
    }

    // ──────────────────────────────────────────────
    // External — State Changing (Withdrawal Queue)
    // ──────────────────────────────────────────────

    /// @notice Request withdrawal of shares (Step 1)
    /// @dev Shares locked (non-transferable) but still earn yield and bear NAV risk.
    function requestWithdrawal(uint256 shares) external returns (uint256 receiptId);

    /// @notice Execute a pending withdrawal after 48h cooldown (Step 2)
    /// @dev NAV computed at execution time. Reverts if utilization > 80%.
    function executeWithdrawal(uint256 receiptId) external returns (uint256 assets);

    /// @notice Cancel a pending withdrawal request
    /// @dev Triggers 24h cooldown before new request can be made.
    function cancelWithdrawal(uint256 receiptId) external;

    // ──────────────────────────────────────────────
    // External — State Changing (Yield)
    // ──────────────────────────────────────────────

    /// @notice Claim all accumulated yield across all tranches
    /// @return amount USDT yield claimed
    function claim() external returns (uint256 amount);

    /// @notice Claim + re-deposit in one transaction (auto-compound)
    /// @return newShares Additional lvUSDT shares minted from compounded yield
    function compound() external returns (uint256 newShares);

    // ──────────────────────────────────────────────
    // External — View (Tranche System)
    // ──────────────────────────────────────────────

    /// @notice Get all tranches for an address
    function getTranches(address holder) external view returns (Tranche[] memory);

    /// @notice Get total pending yield across all tranches for an address
    function pendingYield(address holder) external view returns (uint256 yield_);

    /// @notice Get the weighted average age of a holder's position (seconds)
    function weightedAge(address holder) external view returns (uint256 ageSeconds);

    /// @notice Get the total economic value: shares × NAV_per_share + pending_yield
    function totalValue(address holder) external view returns (uint256 value);

    /// @notice Get max tranches per address
    function maxTranches() external view returns (uint8);

    // ──────────────────────────────────────────────
    // External — View (Vault Health)
    // ──────────────────────────────────────────────

    /// @notice Get real-time NAV including unrealized trader PnL
    function getNAV() external view returns (uint256 nav);

    /// @notice Get current net unrealized trader PnL (positive = traders are profitable)
    /// @dev Used by ExecutionEngine to compute incremental updates to unrealized PnL
    function getNetUnrealizedPnL() external view returns (int256);

    /// @notice Update the net unrealized trader PnL for NAV calculation
    /// @dev Only callable by EXECUTION_ENGINE_ROLE. Sets the absolute value (not a delta).
    /// @param newPnL New net unrealized PnL (positive = traders profitable)
    function updateUnrealizedPnL(int256 newPnL) external;

    /// @notice Transfer USDT from vault to AccountManager to fund trader PnL profit
    /// @dev Called by ExecutionEngine when a trader closes a profitable position.
    ///      The unified LP pool backs all trades — this is how winners get paid.
    /// @param recipient AccountManager address to receive the USDT
    /// @param amount USDT amount to transfer (WAD)
    function fundTraderPnL(address recipient, uint256 amount) external;

    /// @notice Absorb a bad debt loss into the LP pool NAV
    /// @dev Called by LiquidationEngine when insurance is insufficient.
    ///      Directly reduces NAV. All LPs share the loss pro-rata via share price decrease.
    /// @param amount USDT amount of bad debt to socialize (WAD)
    function socializeLoss(uint256 amount) external;

    /// @notice Get current utilization: Global_OI / TVL
    function getUtilization() external view returns (uint256 utilization);

    /// @notice Check if withdrawals are currently possible (utilization < 80%)
    function withdrawalsEnabled() external view returns (bool);

    /// @notice Get total shares currently in the withdrawal queue
    function totalQueuedShares() external view returns (uint256);

    /// @notice Get withdrawal receipt details
    function getReceipt(uint256 receiptId) external view returns (WithdrawalReceipt memory);

    /// @notice Get all pending withdrawal receipts for a user
    function getUserReceipts(address user) external view returns (WithdrawalReceipt[] memory);

    /// @notice Check if a user is in cancel cooldown
    function isInCooldown(address user) external view returns (bool);
}

