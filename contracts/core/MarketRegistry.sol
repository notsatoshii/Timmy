// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IMarketRegistry } from "../interfaces/IMarketRegistry.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

/// @title MarketRegistry
/// @notice Creates and manages markets. Stores metadata: resolution time, is_live,
///         category, allocation weight. Source of τ and is_live for all other contracts.
/// @dev Admin-managed. No protocol dependencies. First contract in the build order.
contract MarketRegistry is IMarketRegistry, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;

    // ──────────────────────────────────────────────
    // Constants & Roles
    // ──────────────────────────────────────────────

    bytes32 public constant MARKET_MANAGER = keccak256("MARKET_MANAGER");
    bytes32 public constant KEEPER = keccak256("KEEPER");

    uint256 private constant WAD = 1e18;
    uint256 private constant SECONDS_PER_HOUR = 3600;

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    /// @dev marketId => Market
    mapping(bytes32 => Market) private _markets;

    /// @dev Array of all market IDs ever created
    bytes32[] private _allMarketIds;

    /// @dev Active market IDs (ACTIVE state)
    bytes32[] private _activeMarketIds;

    /// @dev Index tracking for _activeMarketIds removal — marketId => index+1 (0 means not in array)
    mapping(bytes32 => uint256) private _activeMarketIndex;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin Address granted DEFAULT_ADMIN_ROLE
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MARKET_MANAGER, admin);
        _grantRole(KEEPER, admin);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc IMarketRegistry
    function createMarket(
        bytes32 marketId,
        string calldata name,
        string calldata externalMarketId,
        uint256 resolutionTime,
        MarketCategory category,
        uint256 allocationWeight
    ) external onlyRole(MARKET_MANAGER) whenNotPaused {
        if (_markets[marketId].listingTime != 0) {
            revert MarketRegistry__MarketAlreadyExists(marketId);
        }
        if (resolutionTime <= block.timestamp) {
            revert MarketRegistry__InvalidResolutionTime(resolutionTime);
        }
        if (allocationWeight == 0 || allocationWeight > WAD) {
            revert MarketRegistry__InvalidAllocationWeight(allocationWeight);
        }

        _markets[marketId] = Market({
            id: marketId,
            name: name,
            externalMarketId: externalMarketId,
            state: MarketState.LISTED,
            category: category,
            resolutionTime: resolutionTime,
            listingTime: block.timestamp,
            allocationWeight: allocationWeight,
            isLive: false,
            liveStartTime: 0,
            outcome: 2, // unset — 2 means VOID/unresolved
            externalResolutionTime: 0
        });

        _allMarketIds.push(marketId);

        emit MarketCreated(marketId, name, resolutionTime, uint8(category));
    }

    /// @inheritdoc IMarketRegistry
    function activateMarket(bytes32 marketId) external onlyRole(KEEPER) whenNotPaused {
        Market storage m = _getMarketStorage(marketId);
        if (m.state != MarketState.LISTED) {
            revert MarketRegistry__InvalidStateTransition(marketId, uint8(m.state), uint8(MarketState.ACTIVE));
        }

        m.state = MarketState.ACTIVE;
        _addToActive(marketId);

        emit MarketLive(marketId, block.timestamp);
    }

    /// @inheritdoc IMarketRegistry
    function setLive(bytes32 marketId) external onlyRole(KEEPER) whenNotPaused {
        Market storage m = _getMarketStorage(marketId);
        if (m.state != MarketState.ACTIVE) {
            revert MarketRegistry__MarketNotActive(marketId);
        }

        m.isLive = true;
        m.liveStartTime = block.timestamp;

        emit MarketLive(marketId, block.timestamp);
    }

    /// @inheritdoc IMarketRegistry
    function setPendingResolution(bytes32 marketId) external onlyRole(KEEPER) whenNotPaused {
        Market storage m = _getMarketStorage(marketId);
        if (m.state != MarketState.ACTIVE) {
            revert MarketRegistry__InvalidStateTransition(
                marketId, uint8(m.state), uint8(MarketState.PENDING_RESOLUTION)
            );
        }

        m.state = MarketState.PENDING_RESOLUTION;
        _removeFromActive(marketId);

        emit MarketPendingResolution(marketId, block.timestamp);
    }

    /// @inheritdoc IMarketRegistry
    function resolveMarket(
        bytes32 marketId,
        uint8 outcome,
        uint256 externalTimestamp
    ) external onlyRole(MARKET_MANAGER) whenNotPaused {
        Market storage m = _getMarketStorage(marketId);
        if (m.state != MarketState.PENDING_RESOLUTION) {
            revert MarketRegistry__InvalidStateTransition(marketId, uint8(m.state), uint8(MarketState.RESOLVED));
        }

        m.state = MarketState.RESOLVED;
        m.outcome = outcome;
        m.externalResolutionTime = externalTimestamp;

        emit MarketResolved(marketId, outcome, externalTimestamp);
    }

    /// @inheritdoc IMarketRegistry
    function voidMarket(bytes32 marketId) external onlyRole(MARKET_MANAGER) whenNotPaused {
        Market storage m = _getMarketStorage(marketId);
        // Can void from LISTED, ACTIVE, or PENDING_RESOLUTION
        if (m.state == MarketState.RESOLVED || m.state == MarketState.VOIDED) {
            revert MarketRegistry__InvalidStateTransition(marketId, uint8(m.state), uint8(MarketState.VOIDED));
        }

        // Remove from active if it was active
        if (m.state == MarketState.ACTIVE) {
            _removeFromActive(marketId);
        }

        m.state = MarketState.VOIDED;
        m.outcome = 2; // VOID

        emit MarketVoided(marketId, block.timestamp);
    }

    /// @inheritdoc IMarketRegistry
    function updateAllocationWeight(
        bytes32 marketId,
        uint256 newWeight
    ) external onlyRole(MARKET_MANAGER) whenNotPaused {
        if (newWeight == 0 || newWeight > WAD) {
            revert MarketRegistry__InvalidAllocationWeight(newWeight);
        }

        Market storage m = _getMarketStorage(marketId);
        uint256 oldWeight = m.allocationWeight;
        m.allocationWeight = newWeight;

        emit AllocationWeightUpdated(marketId, oldWeight, newWeight);
    }

    /// @notice Pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @inheritdoc IMarketRegistry
    function getMarket(bytes32 marketId) external view returns (Market memory) {
        _requireMarketExists(marketId);
        return _markets[marketId];
    }

    /// @inheritdoc IMarketRegistry
    function getMarketState(bytes32 marketId) external view returns (MarketState) {
        _requireMarketExists(marketId);
        return _markets[marketId].state;
    }

    /// @inheritdoc IMarketRegistry
    function getTau(bytes32 marketId) external view returns (uint256 tauHours) {
        _requireMarketExists(marketId);
        Market storage m = _markets[marketId];

        if (block.timestamp >= m.resolutionTime) {
            return 0;
        }

        // τ = (resolutionTime - now) in hours, WAD-encoded
        uint256 secondsRemaining = m.resolutionTime - block.timestamp;
        tauHours = (secondsRemaining * WAD) / SECONDS_PER_HOUR;
    }

    /// @inheritdoc IMarketRegistry
    function getTauMax(bytes32 marketId) external view returns (uint256 tauMaxHours) {
        _requireMarketExists(marketId);
        Market storage m = _markets[marketId];

        // τ_max = total duration from listing to resolution
        uint256 totalSeconds = m.resolutionTime - m.listingTime;
        tauMaxHours = (totalSeconds * WAD) / SECONDS_PER_HOUR;
    }

    /// @inheritdoc IMarketRegistry
    function isLive(bytes32 marketId) external view returns (bool) {
        _requireMarketExists(marketId);
        return _markets[marketId].isLive;
    }

    /// @inheritdoc IMarketRegistry
    function getActiveMarkets() external view returns (bytes32[] memory) {
        return _activeMarketIds;
    }

    /// @inheritdoc IMarketRegistry
    function activeMarketCount() external view returns (uint256) {
        return _activeMarketIds.length;
    }

    /// @inheritdoc IMarketRegistry
    function getAllocationWeight(bytes32 marketId) external view returns (uint256) {
        _requireMarketExists(marketId);
        return _markets[marketId].allocationWeight;
    }

    // ──────────────────────────────────────────────
    // Internal Functions
    // ──────────────────────────────────────────────

    /// @dev Get mutable storage reference, reverts if market doesn't exist
    function _getMarketStorage(bytes32 marketId) internal view returns (Market storage) {
        _requireMarketExists(marketId);
        return _markets[marketId];
    }

    /// @dev Revert if market does not exist
    function _requireMarketExists(bytes32 marketId) internal view {
        if (_markets[marketId].listingTime == 0) {
            revert MarketRegistry__MarketNotFound(marketId);
        }
    }

    /// @dev Add market to active array with index tracking
    function _addToActive(bytes32 marketId) internal {
        _activeMarketIds.push(marketId);
        _activeMarketIndex[marketId] = _activeMarketIds.length; // 1-indexed
    }

    /// @dev Remove market from active array using swap-and-pop
    function _removeFromActive(bytes32 marketId) internal {
        uint256 indexPlusOne = _activeMarketIndex[marketId];
        if (indexPlusOne == 0) return; // not in array

        uint256 lastIndex = _activeMarketIds.length - 1;
        uint256 removeIndex = indexPlusOne - 1;

        if (removeIndex != lastIndex) {
            bytes32 lastMarketId = _activeMarketIds[lastIndex];
            _activeMarketIds[removeIndex] = lastMarketId;
            _activeMarketIndex[lastMarketId] = indexPlusOne;
        }

        _activeMarketIds.pop();
        delete _activeMarketIndex[marketId];
    }
}
