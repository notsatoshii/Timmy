// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IFundingRateEngine } from "./interfaces/IFundingRateEngine.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { IOILimits } from "./interfaces/IOILimits.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { IAccountManager } from "./interfaces/IAccountManager.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { RiskCurves } from "./libraries/RiskCurves.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// 2. Custom Errors
error FundingRateEngine__ZeroAddress();
error FundingRateEngine__MarketNotInitialized(bytes32 marketId);
error FundingRateEngine__NoUnmatchedFunding(bytes32 marketId);

/// @title FundingRateEngine
/// @notice Trader-to-trader periodic payments. Heavy side pays light side.
///         Matched OI is zero-sum between traders. Unmatched OI goes to LP pool.
///         Uses a single cumulative funding index per market with direction-aware accrual.
/// @dev funding_rate = min(base × |imbalance| × multiplier, max_rate).
///      Index increases when longs pay (long-heavy), decreases when shorts pay.
contract FundingRateEngine is IFundingRateEngine, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;

    /// @notice Base funding rate: 0.01% per hour (1 bp/hr) in WAD
    uint256 public constant BASE_FUNDING_RATE = 1e14;

    /// @notice Maximum funding rate: 0.05% per hour (5 bps/hr) in WAD
    uint256 public constant MAX_FUNDING_RATE = 5e14;

    /// @notice Maximum funding escalation multiplier
    uint256 public constant FUNDING_ESCALATION_MAX = 4e18;

    /// @notice Seconds per hour for rate conversion
    uint256 internal constant SECONDS_PER_HOUR = 3600;

    // 3. Events (inherited from interface)

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ──────────────────────────────────────────────
    // Immutable Dependencies
    // ──────────────────────────────────────────────

    IMarketRegistry public immutable marketRegistry;
    IOILimits public immutable oiLimits;
    IPositionManager public immutable positionManager;
    // FIX LEVER-011: Add dependencies for routing unmatched funding
    IAccountManager public immutable accountManager;
    IRewardsDistributor public immutable rewardsDistributor;

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    /// @notice Single cumulative funding index per market (signed, WAD)
    /// @dev Positive rate (longs pay) → index increases. Negative rate → index decreases.
    mapping(bytes32 => int256) private _fundingIndex;

    /// @notice Last accrual timestamp per market
    mapping(bytes32 => uint256) private _lastAccrualTime;

    /// @notice Whether a market index has been initialized
    mapping(bytes32 => bool) private _initialized;

    /// @notice Pending unmatched funding not yet routed to LP (WAD)
    mapping(bytes32 => uint256) private _pendingUnmatchedFunding;

    /// @notice Per-market risk parameters for M_market / R_adjusted computation
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
        address positionManager_,
        address accountManager_,
        address rewardsDistributor_
    ) {
        if (admin_ == address(0)) revert FundingRateEngine__ZeroAddress();
        if (marketRegistry_ == address(0)) revert FundingRateEngine__ZeroAddress();
        if (oiLimits_ == address(0)) revert FundingRateEngine__ZeroAddress();
        if (positionManager_ == address(0)) revert FundingRateEngine__ZeroAddress();
        if (accountManager_ == address(0)) revert FundingRateEngine__ZeroAddress();
        if (rewardsDistributor_ == address(0)) revert FundingRateEngine__ZeroAddress();

        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(KEEPER_ROLE, admin_);

        marketRegistry = IMarketRegistry(marketRegistry_);
        oiLimits = IOILimits(oiLimits_);
        positionManager = IPositionManager(positionManager_);
        accountManager = IAccountManager(accountManager_);
        rewardsDistributor = IRewardsDistributor(rewardsDistributor_);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc IFundingRateEngine
    function accrueFunding(bytes32 marketId) external whenNotPaused nonReentrant {
        _accrueFunding(marketId);
    }

    /// @inheritdoc IFundingRateEngine
    // FIX LEVER-011: Actually transfer USDT to RewardsDistributor
    function routeUnmatchedFunding(bytes32 marketId) external whenNotPaused nonReentrant {
        uint256 pending = _pendingUnmatchedFunding[marketId];
        if (pending == 0) revert FundingRateEngine__NoUnmatchedFunding(marketId);

        _pendingUnmatchedFunding[marketId] = 0;

        // Transfer USDT from AccountManager to RewardsDistributor
        accountManager.transferOut(address(rewardsDistributor), pending);
        rewardsDistributor.depositRewards(pending);

        emit UnmatchedFundingRouted(marketId, pending, block.timestamp);
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @inheritdoc IFundingRateEngine
    function getCurrentFundingRate(bytes32 marketId) external view override returns (int256 rate) {
        rate = _computeSignedFundingRate(marketId);
    }

    /// @inheritdoc IFundingRateEngine
    function getFundingMultiplier(bytes32 marketId) external view override returns (uint256 multiplier) {
        uint256 rAdj = _getRAdjusted(marketId);
        multiplier = _computeFundingMultiplier(rAdj);
    }

    /// @inheritdoc IFundingRateEngine
    function getAccruedFunding(uint256 positionId) external view override returns (int256 funding) {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) return 0;

        int256 currentIndex = _fundingIndex[pos.marketId];
        int256 indexDelta = currentIndex - pos.fundingIndex;

        // accrued = -direction * posSize * indexDelta / WAD
        // direction: +1 long, -1 short
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        funding = -direction * int256(pos.positionSize) * indexDelta / int256(WAD);
    }

    /// @inheritdoc IFundingRateEngine
    function getFundingIndex(bytes32 marketId) external view override returns (int256 index) {
        index = _fundingIndex[marketId];
    }

    /// @inheritdoc IFundingRateEngine
    function getOISplit(bytes32 marketId) external view override returns (uint256 matchedOI, uint256 unmatchedOI) {
        uint256 longOI = oiLimits.getSideOI(marketId, true);
        uint256 shortOI = oiLimits.getSideOI(marketId, false);

        matchedOI = longOI < shortOI ? longOI : shortOI;
        unmatchedOI = longOI > shortOI ? longOI - shortOI : shortOI - longOI;
    }

    /// @inheritdoc IFundingRateEngine
    function getPendingUnmatchedFunding(bytes32 marketId) external view override returns (uint256) {
        return _pendingUnmatchedFunding[marketId];
    }

    /// @inheritdoc IFundingRateEngine
    function computeIndexAt(bytes32 marketId, uint256 asOfTimestamp)
        external
        view
        override
        returns (int256 index)
    {
        uint256 lastAccrual = _lastAccrualTime[marketId];
        index = _fundingIndex[marketId];

        // If asOfTimestamp is at or before the last accrual, return stored index
        if (asOfTimestamp <= lastAccrual) return index;

        // Project the index forward
        uint256 deltaT = asOfTimestamp - lastAccrual;
        int256 rate = _computeSignedFundingRate(marketId);
        // Convert hourly rate to per-second, then multiply by deltaT
        int256 indexDelta = rate * int256(deltaT) / int256(SECONDS_PER_HOUR);

        index += indexDelta;
    }

    // ──────────────────────────────────────────────
    // External — Admin
    // ──────────────────────────────────────────────

    /// @notice Initialize the funding index for a market
    /// @dev Sets index to 0 and records the initial accrual time. Must be called when market is created.
    function initializeMarketIndex(bytes32 marketId) external onlyRole(ADMIN_ROLE) {
        if (!_initialized[marketId]) {
            _fundingIndex[marketId] = 0;
            _lastAccrualTime[marketId] = block.timestamp;
            _initialized[marketId] = true;
        }
    }

    /// @notice Update market risk parameters for R_adjusted computation
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

    /// @dev Accrue the single funding index for a market
    function _accrueFunding(bytes32 marketId) internal {
        uint256 lastAccrual = _lastAccrualTime[marketId];
        if (lastAccrual == 0) return; // Not initialized

        uint256 deltaT = block.timestamp - lastAccrual;
        if (deltaT == 0) return;

        int256 rate = _computeSignedFundingRate(marketId);
        // indexDelta = rate * deltaT / SECONDS_PER_HOUR
        int256 indexDelta = rate * int256(deltaT) / int256(SECONDS_PER_HOUR);

        _fundingIndex[marketId] += indexDelta;
        _lastAccrualTime[marketId] = block.timestamp;

        // Accumulate unmatched funding for LP routing
        _accrueUnmatchedFunding(marketId, deltaT);

        emit FundingIndexUpdated(marketId, _fundingIndex[marketId], _fundingIndex[marketId], rate, block.timestamp);
    }

    /// @dev Accumulate unmatched funding that goes to LP
    function _accrueUnmatchedFunding(bytes32 marketId, uint256 deltaT) internal {
        uint256 longOI = oiLimits.getSideOI(marketId, true);
        uint256 shortOI = oiLimits.getSideOI(marketId, false);
        uint256 unmatchedOI = longOI > shortOI ? longOI - shortOI : shortOI - longOI;

        if (unmatchedOI == 0) return;

        // Unsigned rate for unmatched funding calculation
        int256 signedRate = _computeSignedFundingRate(marketId);
        uint256 absRate = FixedPointMath.abs(signedRate);

        // unmatched_funding_accrual = absRate * unmatchedOI * deltaT / SECONDS_PER_HOUR / WAD
        uint256 accrual = absRate * deltaT / SECONDS_PER_HOUR;
        accrual = unmatchedOI.wadMul(accrual);

        _pendingUnmatchedFunding[marketId] += accrual;
    }

    /// @dev Compute the signed funding rate for a market (per hour, WAD)
    /// @return rate Positive = longs pay (long-heavy). Negative = shorts pay (short-heavy).
    function _computeSignedFundingRate(bytes32 marketId) internal view returns (int256 rate) {
        int256 imbalanceRatio = oiLimits.getImbalanceRatio(marketId);

        // funding_rate_calc = base × |imbalance| × multiplier
        uint256 absImbalance = FixedPointMath.abs(imbalanceRatio);

        uint256 rAdj = _getRAdjusted(marketId);
        uint256 multiplier = _computeFundingMultiplier(rAdj);

        uint256 rateCalc = BASE_FUNDING_RATE.wadMul(absImbalance).wadMul(multiplier);
        uint256 cappedRate = rateCalc > MAX_FUNDING_RATE ? MAX_FUNDING_RATE : rateCalc;

        // Sign: positive when longs pay (imbalanceRatio > 0 means long-heavy)
        rate = imbalanceRatio >= 0 ? int256(cappedRate) : -int256(cappedRate);
    }

    /// @dev Compute funding multiplier: 1.0 + (escalation_max - 1.0) × (1 - R_adjusted)
    function _computeFundingMultiplier(uint256 rAdjusted) internal pure returns (uint256 multiplier) {
        // funding_multiplier = 1.0 + (4.0 - 1.0) × (1 - R_adjusted)
        // = 1.0 + 3.0 × (1 - R_adjusted)
        uint256 complement = WAD - rAdjusted;
        multiplier = WAD + complement.wadMul(FUNDING_ESCALATION_MAX - WAD);
    }

    /// @dev Get R_adjusted (mechanical curve) for a market
    function _getRAdjusted(bytes32 marketId) internal view returns (uint256) {
        uint256 tauHours = marketRegistry.getTau(marketId);
        bool isLive_ = marketRegistry.isLive(marketId);

        uint256 tauEff = RiskCurves.computeTauEffective(tauHours, isLive_);
        uint256 r = RiskCurves.computeR(tauEff);

        uint256 mMarket = RiskCurves.computeMarketAdjustment(
            sigmaCurrent[marketId],
            sigmaBaseline[marketId],
            externalDepth[marketId],
            depthThreshold[marketId],
            marketOI[marketId],
            globalOI
        );

        return RiskCurves.computeRAdjusted(r, mMarket);
    }
}
