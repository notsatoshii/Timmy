// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IBorrowFeeEngine } from "./interfaces/IBorrowFeeEngine.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { IOILimits } from "./interfaces/IOILimits.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { RiskCurves } from "./libraries/RiskCurves.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title BorrowFeeEngine
/// @notice Continuous fee on all leveraged positions (1x exempt). Index-based accrual.
///         The "ticking clock" that gives every leveraged position a finite economic lifespan.
/// @dev Rate = base_borrow_rate * M_ttR * (1 + imbalance_surcharge).
///      M_ttR driven by R_borrow(tau) with tau_ref = 168h. Surcharge on heavy side only.
contract BorrowFeeEngine is IBorrowFeeEngine, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;

    /// @notice Base borrow rate: 0.02% per hour (2 bps/hr) in WAD
    uint256 public constant BASE_BORROW_RATE = 2e14;

    /// @notice Maximum time-to-resolution multiplier
    uint256 public constant M_TTR_MAX = 25e18;

    /// @notice Surcharge factor applied to imbalance ratio for heavy side
    uint256 public constant SURCHARGE_FACTOR = WAD; // 1.0

    /// @notice Seconds per hour for rate conversion
    uint256 internal constant SECONDS_PER_HOUR = 3600;

    // ──────────────────────────────────────────────
    // Custom Errors
    // ──────────────────────────────────────────────

    error BorrowFeeEngine__ZeroAddress();
    error BorrowFeeEngine__InvalidTimestamp(uint256 timestamp);

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // ──────────────────────────────────────────────
    // Immutable Dependencies
    // ──────────────────────────────────────────────

    IMarketRegistry public immutable marketRegistry;
    IOILimits public immutable oiLimits;
    IPositionManager public immutable positionManager;

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    /// @notice Cumulative borrow index per market per side (WAD, starts at WAD)
    mapping(bytes32 => uint256) private _longBorrowIndex;
    mapping(bytes32 => uint256) private _shortBorrowIndex;

    /// @notice Last accrual timestamp per market per side
    mapping(bytes32 => uint256) private _longLastAccrualTime;
    mapping(bytes32 => uint256) private _shortLastAccrualTime;

    /// @notice Per-market risk parameters (set by admin/keeper)
    mapping(bytes32 => uint256) public sigmaCurrent;
    mapping(bytes32 => uint256) public sigmaBaseline;
    mapping(bytes32 => uint256) public externalDepth;
    mapping(bytes32 => uint256) public depthThreshold;
    mapping(bytes32 => uint256) public marketOI;
    uint256 public globalOI;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    constructor(
        address admin_,
        address marketRegistry_,
        address oiLimits_,
        address positionManager_
    ) {
        if (admin_ == address(0)) revert BorrowFeeEngine__ZeroAddress();
        if (marketRegistry_ == address(0)) revert BorrowFeeEngine__ZeroAddress();
        if (oiLimits_ == address(0)) revert BorrowFeeEngine__ZeroAddress();
        if (positionManager_ == address(0)) revert BorrowFeeEngine__ZeroAddress();

        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(KEEPER_ROLE, admin_);

        marketRegistry = IMarketRegistry(marketRegistry_);
        oiLimits = IOILimits(oiLimits_);
        positionManager = IPositionManager(positionManager_);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc IBorrowFeeEngine
    function accrueIndex(bytes32 marketId, bool isLong) external whenNotPaused {
        _accrueIndex(marketId, isLong);
    }

    /// @inheritdoc IBorrowFeeEngine
    function accrueAll() external whenNotPaused {
        bytes32[] memory markets = marketRegistry.getActiveMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            _accrueIndex(markets[i], true);
            _accrueIndex(markets[i], false);
        }
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @inheritdoc IBorrowFeeEngine
    function getCurrentBorrowRate(bytes32 marketId, bool isLong)
        external
        view
        override
        returns (uint256 ratePerHour)
    {
        ratePerHour = _computeBorrowRate(marketId, isLong);
    }

    /// @inheritdoc IBorrowFeeEngine
    function getMttR(bytes32 marketId) external view override returns (uint256 mttR) {
        uint256 rBorrowAdj = _getRBorrowAdjusted(marketId);
        mttR = RiskCurves.borrowMttR(rBorrowAdj);
    }

    /// @inheritdoc IBorrowFeeEngine
    function getImbalanceSurcharge(bytes32 marketId, bool isLong)
        external
        view
        override
        returns (uint256 surcharge)
    {
        surcharge = _computeSurcharge(marketId, isLong);
    }

    /// @inheritdoc IBorrowFeeEngine
    function getAccruedFees(uint256 positionId)
        external
        view
        override
        returns (uint256 fees)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);

        // 1x positions are exempt
        if (pos.leverage == WAD) return 0;
        if (!pos.isOpen) return 0;

        uint256 currentIndex = pos.isLong
            ? _longBorrowIndex[pos.marketId]
            : _shortBorrowIndex[pos.marketId];

        if (currentIndex <= pos.borrowIndex) return 0;

        uint256 indexDelta = currentIndex - pos.borrowIndex;
        fees = pos.positionSize.wadMul(indexDelta);
    }

    /// @inheritdoc IBorrowFeeEngine
    function getBorrowIndex(bytes32 marketId, bool isLong)
        external
        view
        override
        returns (uint256 index)
    {
        index = isLong ? _longBorrowIndex[marketId] : _shortBorrowIndex[marketId];
    }

    /// @inheritdoc IBorrowFeeEngine
    function getAnnualizedRate(bytes32 marketId, bool isLong)
        external
        view
        override
        returns (uint256 annualized)
    {
        uint256 hourly = _computeBorrowRate(marketId, isLong);
        // Annualized = hourly * 8760 hours/year
        annualized = hourly * 8760;
    }

    /// @inheritdoc IBorrowFeeEngine
    function computeIndexAt(bytes32 marketId, bool isLong, uint256 asOfTimestamp)
        external
        view
        override
        returns (uint256 index)
    {
        uint256 lastAccrual = isLong
            ? _longLastAccrualTime[marketId]
            : _shortLastAccrualTime[marketId];
        index = isLong ? _longBorrowIndex[marketId] : _shortBorrowIndex[marketId];

        // If asOfTimestamp is at or before the last accrual, return the stored index
        if (asOfTimestamp <= lastAccrual) return index;

        // Compute the additional accrual from lastAccrual to asOfTimestamp
        uint256 deltaT = asOfTimestamp - lastAccrual;
        uint256 rate = _computeBorrowRate(marketId, isLong);
        uint256 ratePerSecond = rate / SECONDS_PER_HOUR;
        uint256 indexDelta = ratePerSecond * deltaT;

        index += indexDelta;
    }

    // ──────────────────────────────────────────────
    // External — Admin
    // ──────────────────────────────────────────────

    /// @notice Initialize the borrow index for a market (must be called when market is created)
    /// @dev Sets both side indices to WAD and records the initial accrual time
    function initializeMarketIndex(bytes32 marketId) external onlyRole(ADMIN_ROLE) {
        if (_longBorrowIndex[marketId] == 0) {
            _longBorrowIndex[marketId] = WAD;
            _shortBorrowIndex[marketId] = WAD;
            _longLastAccrualTime[marketId] = block.timestamp;
            _shortLastAccrualTime[marketId] = block.timestamp;
        }
    }

    /// @notice Update market risk parameters for M_market computation
    function updateMarketRiskParams(
        bytes32 marketId,
        uint256 sigmaCurrent_,
        uint256 sigmaBaseline_,
        uint256 externalDepth_,
        uint256 depthThreshold_,
        uint256 marketOI_,
        uint256 globalOI_
    ) external onlyRole(ADMIN_ROLE) {
        sigmaCurrent[marketId] = sigmaCurrent_;
        sigmaBaseline[marketId] = sigmaBaseline_;
        externalDepth[marketId] = externalDepth_;
        depthThreshold[marketId] = depthThreshold_;
        marketOI[marketId] = marketOI_;
        globalOI = globalOI_;
    }

    /// @notice Pause the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────
    // Internal Functions
    // ──────────────────────────────────────────────

    /// @dev Accrue borrow index for a single market side
    function _accrueIndex(bytes32 marketId, bool isLong) internal {
        uint256 lastAccrual = isLong
            ? _longLastAccrualTime[marketId]
            : _shortLastAccrualTime[marketId];
        if (lastAccrual == 0) return; // Market not initialized

        uint256 deltaT = block.timestamp - lastAccrual;
        if (deltaT == 0) return;

        uint256 rate = _computeBorrowRate(marketId, isLong);
        uint256 ratePerSecond = rate / SECONDS_PER_HOUR;
        uint256 indexDelta = ratePerSecond * deltaT;

        if (isLong) {
            _longBorrowIndex[marketId] += indexDelta;
            _longLastAccrualTime[marketId] = block.timestamp;
            emit BorrowIndexUpdated(marketId, true, _longBorrowIndex[marketId], rate, block.timestamp);
        } else {
            _shortBorrowIndex[marketId] += indexDelta;
            _shortLastAccrualTime[marketId] = block.timestamp;
            emit BorrowIndexUpdated(marketId, false, _shortBorrowIndex[marketId], rate, block.timestamp);
        }
    }

    /// @dev Compute the current borrow rate for a market side
    /// @return rate Per-hour borrow rate (WAD)
    function _computeBorrowRate(bytes32 marketId, bool isLong) internal view returns (uint256 rate) {
        // 1. Get R_borrow_adjusted
        uint256 rBorrowAdj = _getRBorrowAdjusted(marketId);

        // 2. M_ttR = 1.0 + (25.0 - 1.0) * (1 - R_borrow_adjusted)
        uint256 mTtR = RiskCurves.borrowMttR(rBorrowAdj);

        // 3. Imbalance surcharge (heavy side only)
        uint256 surcharge = _computeSurcharge(marketId, isLong);

        // 4. rate = BASE_BORROW_RATE * M_ttR * (1 + surcharge)
        rate = BASE_BORROW_RATE.wadMul(mTtR).wadMul(WAD + surcharge);
    }

    /// @dev Get R_borrow_adjusted for a market
    function _getRBorrowAdjusted(bytes32 marketId) internal view returns (uint256) {
        uint256 tauHours = marketRegistry.getTau(marketId);
        bool isLive_ = marketRegistry.isLive(marketId);

        uint256 tauEff = RiskCurves.computeTauEffective(tauHours, isLive_);
        uint256 rBorrow = RiskCurves.computeRBorrow(tauEff);

        uint256 mMarket = RiskCurves.computeMarketAdjustment(
            sigmaCurrent[marketId],
            sigmaBaseline[marketId],
            externalDepth[marketId],
            depthThreshold[marketId],
            marketOI[marketId],
            globalOI
        );

        return RiskCurves.computeRAdjusted(rBorrow, mMarket);
    }

    /// @dev Compute imbalance surcharge for a market side
    function _computeSurcharge(bytes32 marketId, bool isLong) internal view returns (uint256) {
        int256 imbalanceRatio = oiLimits.getImbalanceRatio(marketId);

        // Long side pays surcharge when longs are heavy (imbalanceRatio > 0)
        // Short side pays surcharge when shorts are heavy (imbalanceRatio < 0)
        if (isLong && imbalanceRatio > 0) {
            return uint256(imbalanceRatio).wadMul(SURCHARGE_FACTOR);
        } else if (!isLong && imbalanceRatio < 0) {
            return uint256(-imbalanceRatio).wadMul(SURCHARGE_FACTOR);
        }

        return 0;
    }
}
