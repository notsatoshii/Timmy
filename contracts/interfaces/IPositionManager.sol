// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IPositionManager
/// @notice Stores all position state. Single source of truth for position data.
///         Pure data store — no business logic, no formula computation.
///         Multiple contracts read from this (MarginEngine, BorrowFeeEngine,
///         FundingRateEngine, LiquidationEngine, SettlementEngine).
///         Only ExecutionEngine and LiquidationEngine write to this.
interface IPositionManager {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error PositionManager__PositionNotFound(uint256 positionId);
    error PositionManager__PositionNotOpen(uint256 positionId);
    error PositionManager__UnauthorizedCaller(address caller);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event PositionCreated(
        uint256 indexed positionId,
        bytes32 indexed marketId,
        address indexed owner,
        bool isLong,
        uint256 entryPI,
        uint256 entryPrice,
        uint256 positionSize,
        uint256 collateral,
        uint256 leverage,
        uint256 timestamp
    );

    event PositionClosed(uint256 indexed positionId, uint256 timestamp);
    event PositionCollateralUpdated(uint256 indexed positionId, uint256 oldCollateral, uint256 newCollateral);

    // ──────────────────────────────────────────────
    // Structs
    // ──────────────────────────────────────────────

    struct Position {
        uint256 id;
        address owner;
        bytes32 marketId;
        bool isLong;            // true = long (YES), false = short (NO)
        uint256 entryPI;        // PI at open (WAD)
        uint256 entryPrice;     // Execution price at open (WAD)
        uint256 positionSize;   // Notional (WAD)
        uint256 collateral;     // Net collateral after TX fee (WAD)
        uint256 leverage;       // Effective leverage at open (WAD)
        uint256 borrowIndex;    // Snapshot of cumulative borrow index at open (WAD)
        int256 fundingIndex;    // Snapshot of cumulative funding index at open (WAD)
        uint256 openTimestamp;
        bool isOpen;
    }

    // ──────────────────────────────────────────────
    // External — State Changing (restricted to authorized callers)
    // ──────────────────────────────────────────────

    /// @notice Create a new position record
    /// @dev Only callable by ExecutionEngine
    /// @return positionId The unique identifier for the new position
    function createPosition(
        address owner,
        bytes32 marketId,
        bool isLong,
        uint256 entryPI,
        uint256 entryPrice,
        uint256 positionSize,
        uint256 collateral,
        uint256 leverage,
        uint256 borrowIndex,
        int256 fundingIndex
    ) external returns (uint256 positionId);

    /// @notice Mark a position as closed
    /// @dev Only callable by ExecutionEngine, LiquidationEngine, or SettlementEngine
    function closePosition(uint256 positionId) external;

    /// @notice Update collateral on an existing position
    /// @dev Only callable by ExecutionEngine (add/remove collateral)
    function updateCollateral(uint256 positionId, uint256 newCollateral) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get full position data
    function getPosition(uint256 positionId) external view returns (Position memory);

    /// @notice Check if a position exists and is open
    function isPositionOpen(uint256 positionId) external view returns (bool);

    /// @notice Get the owner of a position
    function getPositionOwner(uint256 positionId) external view returns (address);

    /// @notice Get all open position IDs for a user
    function getUserPositions(address user) external view returns (uint256[] memory);

    /// @notice Get all open position IDs for a market
    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory);

    /// @notice Get all open position IDs for a specific side of a market
    function getMarketSidePositions(bytes32 marketId, bool isLong) external view returns (uint256[] memory);

    /// @notice Get total number of open positions
    function totalOpenPositions() external view returns (uint256);

    /// @notice Get the next position ID that will be assigned
    function nextPositionId() external view returns (uint256);
}

