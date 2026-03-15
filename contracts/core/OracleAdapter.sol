// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IOracleAdapter } from "../interfaces/IOracleAdapter.sol";
import { IMarketRegistry } from "../interfaces/IMarketRegistry.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ProbabilityIndex } from "../libraries/ProbabilityIndex.sol";
import { RiskCurves } from "../libraries/RiskCurves.sol";

/// @title OracleAdapter
/// @notice Full price pipeline: ingests P_raw → validates → smooths → outputs PI.
///         Includes volatility dampening, time-weighted smoothing, anti-manipulation filters,
///         convergence enforcement.
/// @dev Single contract incorporating the smoothing engine internally.
contract OracleAdapter is IOracleAdapter, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;

    // ──────────────────────────────────────────────
    // Constants & Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant SETTLEMENT = keccak256("SETTLEMENT");

    uint256 private constant WAD = 1e18;

    /// @dev Consistency tolerance for pYes + pNo ≈ 1.0 (5%)
    uint256 private constant CONSISTENCY_TOLERANCE = 5e16;

    /// @dev Default staleness threshold (5 minutes)
    uint256 private constant DEFAULT_STALENESS = 300;

    /// @dev Volatility EMA smoothing factor (0.10 = 10%)
    uint256 private constant VOL_SMOOTHING = 1e17;

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    /// @notice Reference to MarketRegistry for τ and is_live
    IMarketRegistry public immutable MARKET_REGISTRY;

    /// @dev marketId => smoothing state
    mapping(bytes32 => SmoothingState) private _smoothingState;

    /// @dev marketId => smoothing parameters
    mapping(bytes32 => SmoothingParams) private _smoothingParams;

    /// @dev marketId => latest price data
    mapping(bytes32 => PriceData) private _latestPrice;

    /// @dev marketId => frozen flag
    mapping(bytes32 => bool) private _frozen;

    /// @dev source address => config
    mapping(address => SourceConfig) private _sources;

    /// @dev Array of all registered source addresses
    address[] private _sourceAddresses;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin Address granted DEFAULT_ADMIN_ROLE
    /// @param marketRegistry Address of the MarketRegistry contract
    constructor(address admin, address marketRegistry) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE, admin);
        _grantRole(KEEPER, admin);
        MARKET_REGISTRY = IMarketRegistry(marketRegistry);
    }

    // ──────────────────────────────────────────────
    // External — State Changing (Oracle)
    // ──────────────────────────────────────────────

    /// @inheritdoc IOracleAdapter
    function pushPrice(
        bytes32 marketId,
        uint256 pYes,
        uint256 pNo,
        uint256 spread,
        uint256 depth,
        uint256 volume
    ) external onlyRole(ORACLE) nonReentrant whenNotPaused {
        // 0. Source must be registered and active
        if (!_sources[msg.sender].isActive) {
            revert OracleAdapter__SourceNotActive(msg.sender);
        }

        // 1. Market must be active
        IMarketRegistry.MarketState state = MARKET_REGISTRY.getMarketState(marketId);
        if (state != IMarketRegistry.MarketState.ACTIVE) {
            revert OracleAdapter__MarketNotActive(marketId);
        }

        // 2. Market must not be frozen
        if (_frozen[marketId]) {
            revert OracleAdapter__UpdateRejected(marketId, "FROZEN");
        }

        // 3. Validate probabilities
        if (pYes > WAD) revert OracleAdapter__InvalidProbability(pYes);
        if (pNo > WAD) revert OracleAdapter__InvalidProbability(pNo);

        // 4. Consistency check: pYes + pNo ≈ 1.0 (within tolerance)
        {
            uint256 sum = pYes + pNo;
            if (sum > WAD + CONSISTENCY_TOLERANCE || sum < WAD - CONSISTENCY_TOLERANCE) {
                revert OracleAdapter__InconsistentPrices(pYes, pNo);
            }
        }

        // Delegate to internal processing
        _processUpdate(marketId, pYes, spread, depth, volume);
    }

    /// @inheritdoc IOracleAdapter
    function snapToOutcome(
        bytes32 marketId,
        uint256 outcome
    ) external onlyRole(SETTLEMENT) nonReentrant {
        // outcome must be 0 or WAD
        if (outcome != 0 && outcome != WAD) {
            revert OracleAdapter__InvalidProbability(outcome);
        }

        SmoothingState storage ss = _smoothingState[marketId];
        ss.pSmooth = outcome;
        ss.lastUpdateTime = block.timestamp;

        _latestPrice[marketId].pi = outcome;
        _latestPrice[marketId].timestamp = block.timestamp;

        emit PIUpdated(marketId, outcome, outcome, WAD, block.timestamp);
    }

    // ──────────────────────────────────────────────
    // External — State Changing (Source Management)
    // ──────────────────────────────────────────────

    /// @inheritdoc IOracleAdapter
    function registerSource(
        address source,
        uint256 weight
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _sources[source] = SourceConfig({
            source: source,
            weight: weight,
            isActive: true,
            lastUpdate: block.timestamp
        });
        _sourceAddresses.push(source);

        emit SourceRegistered(source, weight);
    }

    /// @inheritdoc IOracleAdapter
    function removeSource(address source) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_sources[source].isActive) {
            revert OracleAdapter__SourceNotRegistered(source);
        }
        _sources[source].isActive = false;

        emit SourceRemoved(source);
    }

    /// @inheritdoc IOracleAdapter
    function updateSourceWeight(
        address source,
        uint256 newWeight
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_sources[source].isActive) {
            revert OracleAdapter__SourceNotRegistered(source);
        }
        _sources[source].weight = newWeight;

        emit SourceDegraded(source, newWeight);
    }

    // ──────────────────────────────────────────────
    // External — State Changing (Market Controls)
    // ──────────────────────────────────────────────

    /// @inheritdoc IOracleAdapter
    function freezeMarket(bytes32 marketId) external onlyRole(KEEPER) {
        _frozen[marketId] = true;
        emit MarketFrozen(marketId, "MANUAL_FREEZE");
    }

    /// @inheritdoc IOracleAdapter
    function unfreezeMarket(bytes32 marketId) external onlyRole(KEEPER) {
        _frozen[marketId] = false;
        emit MarketUnfrozen(marketId);
    }

    /// @inheritdoc IOracleAdapter
    function updateSmoothingParams(
        bytes32 marketId,
        SmoothingParams calldata params
    ) external onlyRole(KEEPER) {
        _smoothingParams[marketId] = params;
        emit SmoothingParamsUpdated(marketId);
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

    /// @inheritdoc IOracleAdapter
    function getPI(bytes32 marketId) external view returns (uint256 pi) {
        return _smoothingState[marketId].pSmooth;
    }

    /// @inheritdoc IOracleAdapter
    function getLatestPrice(bytes32 marketId) external view returns (PriceData memory) {
        return _latestPrice[marketId];
    }

    /// @inheritdoc IOracleAdapter
    function getSmoothingState(bytes32 marketId) external view returns (SmoothingState memory) {
        return _smoothingState[marketId];
    }

    /// @inheritdoc IOracleAdapter
    function getSmoothingParams(bytes32 marketId) external view returns (SmoothingParams memory) {
        return _getEffectiveParams(marketId);
    }

    /// @inheritdoc IOracleAdapter
    function getVolatility(bytes32 marketId) external view returns (uint256 sigma) {
        return _smoothingState[marketId].sigma;
    }

    /// @inheritdoc IOracleAdapter
    function isStale(bytes32 marketId) external view returns (bool) {
        SmoothingState storage ss = _smoothingState[marketId];
        if (!ss.initialized) return true;

        uint256 threshold = _getStalenessThreshold(marketId);
        return block.timestamp - ss.lastUpdateTime > threshold;
    }

    /// @inheritdoc IOracleAdapter
    function isFrozen(bytes32 marketId) external view returns (bool) {
        return _frozen[marketId];
    }

    /// @inheritdoc IOracleAdapter
    function getStalenessThreshold(bytes32 marketId) external view returns (uint256 seconds_) {
        return _getStalenessThreshold(marketId);
    }

    /// @inheritdoc IOracleAdapter
    function getActiveSources() external view returns (SourceConfig[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _sourceAddresses.length; i++) {
            if (_sources[_sourceAddresses[i]].isActive) activeCount++;
        }

        SourceConfig[] memory result = new SourceConfig[](activeCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < _sourceAddresses.length; i++) {
            if (_sources[_sourceAddresses[i]].isActive) {
                result[idx++] = _sources[_sourceAddresses[i]];
            }
        }
        return result;
    }

    // ──────────────────────────────────────────────
    // Internal Functions
    // ──────────────────────────────────────────────

    /// @dev Internal processing after validation: filters, smoothing, state update
    function _processUpdate(
        bytes32 marketId,
        uint256 pRaw,
        uint256 spread,
        uint256 depth,
        uint256 volume
    ) internal {
        SmoothingParams memory params = _getEffectiveParams(marketId);
        SmoothingState storage ss = _smoothingState[marketId];

        // Initialize on first update
        if (!ss.initialized) {
            ss.pSmooth = pRaw;
            ss.lastPRaw = pRaw;
            ss.sigma = 0;
            ss.lastUpdateTime = block.timestamp;
            ss.initialized = true;

            _updatePriceData(marketId, pRaw, pRaw, WAD, spread, depth, volume);
            emit PIUpdated(marketId, pRaw, pRaw, WAD, block.timestamp);
            return;
        }

        // Anti-manipulation filters
        uint256 tickMove = _absDiff(pRaw, ss.lastPRaw);
        if (tickMove > params.deltaMax) {
            emit UpdateRejected(marketId, "TICK_TOO_LARGE", pRaw, block.timestamp);
            return;
        }
        if (spread > params.spreadLimit) {
            emit UpdateRejected(marketId, "SPREAD_TOO_WIDE", pRaw, block.timestamp);
            return;
        }
        if (depth < params.depthMin) {
            emit UpdateRejected(marketId, "DEPTH_TOO_LOW", pRaw, block.timestamp);
            return;
        }

        // Update rolling volatility (EMA)
        ss.sigma = (WAD - VOL_SMOOTHING).wadMul(ss.sigma) + VOL_SMOOTHING.wadMul(tickMove);

        // Compute smoothing weight and apply
        (uint256 newPSmooth, uint256 w) = _computeSmoothedPI(marketId, pRaw, ss, params);

        // Update state
        ss.pSmooth = newPSmooth;
        ss.lastPRaw = pRaw;
        ss.lastUpdateTime = block.timestamp;

        uint256 confidence = _computeConfidence(spread, depth, ss.sigma, params);
        _updatePriceData(marketId, pRaw, newPSmooth, confidence, spread, depth, volume);
        emit PIUpdated(marketId, newPSmooth, pRaw, w, block.timestamp);
    }

    /// @dev Compute the new smoothed PI from current state, pRaw, and params
    function _computeSmoothedPI(
        bytes32 marketId,
        uint256 pRaw,
        SmoothingState storage ss,
        SmoothingParams memory params
    ) internal view returns (uint256 newPSmooth, uint256 w) {
        // w_vol = 1 / (1 + σ)
        uint256 wVol = WAD.wadDiv(WAD + ss.sigma);

        // w_time = sqrt(τ / τ_max)
        uint256 wTime = _computeTimeWeight(marketId);

        // Combined weight: w = α × w_vol × w_time
        w = params.alpha.wadMul(wVol).wadMul(wTime);

        // Apply EMA: P_smooth(t) = P_smooth(t-1) + w × (P_raw(t) - P_smooth(t-1))
        uint256 prevSmooth = ss.pSmooth;
        int256 diff = int256(pRaw) - int256(prevSmooth);
        int256 delta = (int256(w) * diff) / int256(WAD);

        if (delta >= 0) {
            newPSmooth = prevSmooth + uint256(delta);
        } else {
            uint256 absDelta = uint256(-delta);
            newPSmooth = absDelta > prevSmooth ? 0 : prevSmooth - absDelta;
        }

        // Rate-of-change clamp
        uint256 changeFromPrev = _absDiff(newPSmooth, prevSmooth);
        if (changeFromPrev > params.epsilon) {
            if (newPSmooth > prevSmooth) {
                newPSmooth = prevSmooth + params.epsilon;
            } else {
                newPSmooth = prevSmooth > params.epsilon ? prevSmooth - params.epsilon : 0;
            }
        }

        // Bounds clamp
        newPSmooth = ProbabilityIndex.clamp(newPSmooth);
    }

    /// @dev Compute time-weight w_time = sqrt(τ / τ_max)
    function _computeTimeWeight(bytes32 marketId) internal view returns (uint256 wTime) {
        uint256 tau = MARKET_REGISTRY.getTau(marketId);
        uint256 tauMax = MARKET_REGISTRY.getTauMax(marketId);
        if (tauMax == 0) return WAD;
        uint256 ratio = tau.wadDiv(tauMax);
        wTime = FixedPointMath.wadSqrt(ratio);
    }

    /// @dev Get effective smoothing params, using defaults if not explicitly set
    function _getEffectiveParams(bytes32 marketId) internal view returns (SmoothingParams memory params) {
        params = _smoothingParams[marketId];
        // Use defaults if not set
        if (params.alpha == 0) {
            params = SmoothingParams({
                alpha: 3e17,        // 0.30 default
                deltaMax: 5e16,     // 0.05 (5%) max tick
                epsilon: 1e16,      // 0.01 (1%) max smooth change
                spreadLimit: 1e17,  // 0.10 (10%) max spread
                depthMin: 0         // no depth minimum by default
            });
        }
    }

    /// @dev Compute composite confidence score from market quality metrics
    function _computeConfidence(
        uint256 spread,
        uint256 depth,
        uint256 sigma,
        SmoothingParams memory params
    ) internal pure returns (uint256 confidence) {
        // Simple composite: lower spread + higher depth + lower vol = higher confidence
        uint256 spreadScore = WAD;
        if (params.spreadLimit > 0 && spread > 0) {
            spreadScore = spread >= params.spreadLimit ? 0 : WAD - spread.wadDiv(params.spreadLimit);
        }

        uint256 volScore = WAD.wadDiv(WAD + sigma);

        // Combine equally
        confidence = (spreadScore + volScore) / 2;

        // Factor in depth if minimum is set
        if (params.depthMin > 0 && depth > 0) {
            uint256 depthScore = depth >= params.depthMin ? WAD : depth.wadDiv(params.depthMin);
            confidence = (confidence * 2 + depthScore) / 3;
        }
    }

    /// @dev Absolute difference between two uint256 values
    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }

    /// @dev Update the latest price data struct
    function _updatePriceData(
        bytes32 marketId,
        uint256 pRaw,
        uint256 pi,
        uint256 confidence,
        uint256 spread,
        uint256 depth,
        uint256 volume
    ) internal {
        _latestPrice[marketId] = PriceData({
            pRaw: pRaw,
            pi: pi,
            spread: spread,
            depth: depth,
            volume: volume,
            confidence: confidence,
            timestamp: block.timestamp
        });
    }

    /// @dev Get staleness threshold based on risk curve oracle frequency
    function _getStalenessThreshold(bytes32 marketId) internal view returns (uint256) {
        try MARKET_REGISTRY.getTau(marketId) returns (uint256 tau) {
            bool live = MARKET_REGISTRY.isLive(marketId);
            uint256 tauEff = RiskCurves.computeTauEffective(tau, live);
            uint256 r = RiskCurves.computeR(tauEff);
            // Oracle frequency from risk curve (in seconds, WAD-encoded)
            uint256 freqWad = RiskCurves.oracleFrequency(r);
            // Use 3× oracle frequency as staleness threshold
            return (freqWad * 3) / WAD;
        } catch {
            return DEFAULT_STALENESS;
        }
    }
}
