// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IMarketRegistry
/// @notice Creates and manages markets. Stores metadata: resolution time, is_live,
///         category, allocation weight. Source of τ and is_live for all other contracts.
interface IMarketRegistry {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error MarketRegistry__MarketNotFound(bytes32 marketId);
    error MarketRegistry__MarketAlreadyExists(bytes32 marketId);
    error MarketRegistry__InvalidResolutionTime(uint256 resolutionTime);
    error MarketRegistry__InvalidAllocationWeight(uint256 weight);
    error MarketRegistry__MarketNotActive(bytes32 marketId);
    error MarketRegistry__InvalidStateTransition(bytes32 marketId, uint8 from, uint8 to);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event MarketCreated(bytes32 indexed marketId, string name, uint256 resolutionTime, uint8 category);
    event MarketLive(bytes32 indexed marketId, uint256 timestamp);
    event MarketPendingResolution(bytes32 indexed marketId, uint256 timestamp);
    event MarketResolved(bytes32 indexed marketId, uint8 outcome, uint256 externalTimestamp);
    event MarketVoided(bytes32 indexed marketId, uint256 timestamp);
    event AllocationWeightUpdated(bytes32 indexed marketId, uint256 oldWeight, uint256 newWeight);

    // ──────────────────────────────────────────────
    // Enums & Structs
    // ──────────────────────────────────────────────

    enum MarketState { LISTED, ACTIVE, PENDING_RESOLUTION, RESOLVED, VOIDED }
    enum MarketCategory { HIGH_LIQUIDITY, MEDIUM_LIQUIDITY, LOW_LIQUIDITY, NEW_UNPROVEN }

    struct Market {
        bytes32 id;
        string name;                    // Human-readable name
        string externalMarketId;        // ID on source platform (Polymarket)
        MarketState state;
        MarketCategory category;
        uint256 resolutionTime;         // Expected resolution timestamp
        uint256 listingTime;            // When market was created
        uint256 allocationWeight;       // OI allocation as fraction of global cap (WAD)
        bool isLive;                    // Whether underlying event is in progress
        uint256 liveStartTime;          // When is_live flipped to true
        uint8 outcome;                  // 0 = NO, 1 = YES, 2 = VOID (only set after resolution)
        uint256 externalResolutionTime; // Timestamp from source platform (fee accrual anchor)
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @notice Create a new market
    function createMarket(
        bytes32 marketId,
        string calldata name,
        string calldata externalMarketId,
        uint256 resolutionTime,
        MarketCategory category,
        uint256 allocationWeight
    ) external;

    /// @notice Transition market to ACTIVE state (after first valid PI)
    function activateMarket(bytes32 marketId) external;

    /// @notice Mark the underlying event as live (triggers live compression)
    function setLive(bytes32 marketId) external;

    /// @notice Transition to PENDING_RESOLUTION
    function setPendingResolution(bytes32 marketId) external;

    /// @notice Record the final outcome
    /// @param outcome 0 = NO, 1 = YES
    /// @param externalTimestamp Resolution timestamp from source platform
    function resolveMarket(bytes32 marketId, uint8 outcome, uint256 externalTimestamp) external;

    /// @notice Void a market (cancelled event)
    function voidMarket(bytes32 marketId) external;

    /// @notice Update allocation weight for a market
    function updateAllocationWeight(bytes32 marketId, uint256 newWeight) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get full market data
    function getMarket(bytes32 marketId) external view returns (Market memory);

    /// @notice Get current state of a market
    function getMarketState(bytes32 marketId) external view returns (MarketState);

    /// @notice Get time-to-resolution in hours (WAD)
    /// @dev Returns 0 if past resolution time
    function getTau(bytes32 marketId) external view returns (uint256 tauHours);

    /// @notice Get τ_max (total duration from listing to resolution) in hours (WAD)
    function getTauMax(bytes32 marketId) external view returns (uint256 tauMaxHours);

    /// @notice Check if the underlying event is live
    function isLive(bytes32 marketId) external view returns (bool);

    /// @notice Get all active market IDs
    function getActiveMarkets() external view returns (bytes32[] memory);

    /// @notice Get the total number of active markets
    function activeMarketCount() external view returns (uint256);

    /// @notice Get allocation weight for a market
    function getAllocationWeight(bytes32 marketId) external view returns (uint256);
}

