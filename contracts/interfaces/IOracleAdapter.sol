// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IOracleAdapter
/// @notice Full price pipeline: ingests P_raw from external prediction markets,
///         validates sources, applies smoothing (volatility dampening, time-weighted
///         smoothing, anti-manipulation filters, convergence enforcement), outputs PI.
///         This is a single contract — smoothing is internal, not a separate contract.
interface IOracleAdapter {
    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error OracleAdapter__SourceNotRegistered(address source);
    error OracleAdapter__StaleData(bytes32 marketId, uint256 lastUpdate, uint256 threshold);
    error OracleAdapter__InvalidProbability(uint256 pRaw);
    error OracleAdapter__InconsistentPrices(uint256 pYes, uint256 pNo);
    error OracleAdapter__SourceDegraded(address source);
    error OracleAdapter__AllSourcesUnavailable(bytes32 marketId);
    error OracleAdapter__MarketNotActive(bytes32 marketId);
    error OracleAdapter__UpdateRejected(bytes32 marketId, string reason);

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event PIUpdated(bytes32 indexed marketId, uint256 pi, uint256 pRaw, uint256 smoothingWeight, uint256 timestamp);
    event UpdateRejected(bytes32 indexed marketId, string reason, uint256 pRaw, uint256 timestamp);
    event SourceRegistered(address indexed source, uint256 weight);
    event SourceDegraded(address indexed source, uint256 newWeight);
    event SourceRemoved(address indexed source);
    event MarketFrozen(bytes32 indexed marketId, string reason);
    event MarketUnfrozen(bytes32 indexed marketId);
    event SmoothingParamsUpdated(bytes32 indexed marketId);

    // ──────────────────────────────────────────────
    // Structs
    // ──────────────────────────────────────────────

    struct PriceData {
        uint256 pRaw;           // Last validated raw probability [0, WAD]
        uint256 pi;             // Current smoothed PI [0, WAD]
        uint256 spread;         // Current bid/ask spread (WAD)
        uint256 depth;          // Current order book depth (WAD, USDT-denominated)
        uint256 volume;         // Recent trading volume (WAD)
        uint256 confidence;     // Composite quality score [0, WAD]
        uint256 timestamp;      // Data timestamp
    }

    struct SourceConfig {
        address source;
        uint256 weight;         // Reliability weight [0, WAD]
        bool isActive;
        uint256 lastUpdate;
    }

    struct SmoothingParams {
        uint256 alpha;          // Base smoothing coefficient (WAD, 0.1-0.5)
        uint256 deltaMax;       // Max tick movement filter (WAD, 0.02-0.10)
        uint256 epsilon;        // Max P_smooth change per tick (WAD, 0.005-0.02)
        uint256 spreadLimit;    // Max spread for acceptance (WAD)
        uint256 depthMin;       // Min depth for acceptance (WAD)
    }

    struct SmoothingState {
        uint256 pSmooth;        // Current smoothed probability = PI (WAD)
        uint256 lastPRaw;       // Last accepted raw probability (WAD)
        uint256 sigma;          // Rolling volatility of P_raw (WAD)
        uint256 lastUpdateTime;
        bool initialized;
    }

    // ──────────────────────────────────────────────
    // External — State Changing (Oracle)
    // ──────────────────────────────────────────────

    /// @notice Push a new price update. Validates, smooths, and updates PI in one call.
    /// @param marketId The market identifier
    /// @param pYes Implied probability of YES outcome [0, WAD]
    /// @param pNo Implied probability of NO outcome [0, WAD]
    /// @param spread Current bid/ask spread (WAD)
    /// @param depth Current order book depth (WAD)
    /// @param volume Recent volume (WAD)
    function pushPrice(
        bytes32 marketId,
        uint256 pYes,
        uint256 pNo,
        uint256 spread,
        uint256 depth,
        uint256 volume
    ) external;

    /// @notice Force PI to final outcome value at settlement
    /// @dev Only callable by SettlementEngine. The ONLY discontinuous PI movement.
    /// @param marketId The resolved market
    /// @param outcome 0 (NO) or WAD (YES)
    function snapToOutcome(bytes32 marketId, uint256 outcome) external;

    // ──────────────────────────────────────────────
    // External — State Changing (Source Management)
    // ──────────────────────────────────────────────

    function registerSource(address source, uint256 weight) external;
    function removeSource(address source) external;
    function updateSourceWeight(address source, uint256 newWeight) external;

    // ──────────────────────────────────────────────
    // External — State Changing (Market Controls)
    // ──────────────────────────────────────────────

    function freezeMarket(bytes32 marketId) external;
    function unfreezeMarket(bytes32 marketId) external;
    function updateSmoothingParams(bytes32 marketId, SmoothingParams calldata params) external;

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @notice Get current PI for a market (the value everything else uses)
    function getPI(bytes32 marketId) external view returns (uint256 pi);

    /// @notice Get full price data for a market
    function getLatestPrice(bytes32 marketId) external view returns (PriceData memory);

    /// @notice Get smoothing state for a market
    function getSmoothingState(bytes32 marketId) external view returns (SmoothingState memory);

    /// @notice Get smoothing parameters for a market
    function getSmoothingParams(bytes32 marketId) external view returns (SmoothingParams memory);

    /// @notice Get current rolling volatility for a market
    function getVolatility(bytes32 marketId) external view returns (uint256 sigma);

    /// @notice Check if a market's price data is stale
    function isStale(bytes32 marketId) external view returns (bool);

    /// @notice Check if a market is frozen
    function isFrozen(bytes32 marketId) external view returns (bool);

    /// @notice Get staleness threshold for current market conditions
    function getStalenessThreshold(bytes32 marketId) external view returns (uint256 seconds_);

    /// @notice Get all active sources
    function getActiveSources() external view returns (SourceConfig[] memory);
}

