// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IMarginEngine } from "./interfaces/IMarginEngine.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { IOracleAdapter } from "./interfaces/IOracleAdapter.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { IBorrowFeeEngine } from "./interfaces/IBorrowFeeEngine.sol";
import { IFundingRateEngine } from "./interfaces/IFundingRateEngine.sol";
import { RiskCurves } from "./libraries/RiskCurves.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title MarginEngine
/// @notice IM, MM, and real-time equity calculation. Creates the pincer effect:
///         rising MM from below + borrow erosion from above.
/// @dev Equity = Collateral + PnL(PI) - Accrued_Borrow_Fees + Accrued_Funding
///      Funding is int256 (+ = received, - = paid).
contract MarginEngine is IMarginEngine, AccessControl, Pausable {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;

    /// @notice Base maintenance margin rate: 2.5% of notional
    uint256 public constant BASE_MM_RATE = 25e15; // 0.025

    /// @notice Base initial margin rate: 5.0% of notional
    /// @dev IM uses a rate-based approach (not notional/leverage) to avoid circularity
    ///      when notional = collateral x leverage. Always >= 2x MM base.
    uint256 public constant BASE_IM_RATE = 5e16; // 0.05

    /// @notice Liquidation buffer: 0.5% (50 bps) of notional
    uint256 public constant LIQUIDATION_BUFFER = 5e15; // 0.005

    /// @notice Withdrawal buffer: 2.0% of notional (MR must stay above MM/notional + this)
    uint256 public constant WITHDRAWAL_BUFFER = 2e16; // 0.02

    /// @notice IM volatility adjustment coefficient (α_IM)
    uint256 public constant ALPHA_IM = 5e17; // 0.5

    /// @notice IM utilization adjustment coefficient (β)
    uint256 public constant BETA_IM = WAD; // 1.0

    /// @notice Market utilization threshold for IM adjustment
    uint256 public constant UTIL_THRESHOLD = 5e17; // 0.50

    /// @notice Danger zone multiplier: within 2× of liquidation threshold
    uint256 public constant DANGER_ZONE_MULT = 2e18; // 2.0

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    // ──────────────────────────────────────────────
    // Immutable Dependencies
    // ──────────────────────────────────────────────

    IPositionManager public immutable positionManager;
    IOracleAdapter public immutable oracle;
    IMarketRegistry public immutable marketRegistry;
    IBorrowFeeEngine public immutable borrowFeeEngine;
    IFundingRateEngine public immutable fundingRateEngine;

    // ──────────────────────────────────────────────
    // Storage: per-market risk parameters
    // ──────────────────────────────────────────────

    /// @notice Baseline volatility per market (WAD)
    mapping(bytes32 => uint256) public sigmaBaseline;

    /// @notice Current volatility per market (WAD) — updated by oracle/keeper
    mapping(bytes32 => uint256) public sigmaCurrent;

    /// @notice External depth per market (WAD)
    mapping(bytes32 => uint256) public externalDepth;

    /// @notice Depth threshold per market (WAD)
    mapping(bytes32 => uint256) public depthThreshold;

    /// @notice Market OI per market (WAD) — for concentration factor
    mapping(bytes32 => uint256) public marketOI;

    /// @notice Global OI (WAD) — for concentration factor
    uint256 public globalOI;

    /// @notice Market utilization per market (WAD) — ratio of market OI to market cap
    mapping(bytes32 => uint256) public marketUtilization;

    // ──────────────────────────────────────────────
    // Custom Errors (beyond interface)
    // ──────────────────────────────────────────────

    error MarginEngine__ZeroAddress();
    error MarginEngine__InvalidMarket(bytes32 marketId);

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    constructor(
        address admin_,
        address positionManager_,
        address oracle_,
        address marketRegistry_,
        address borrowFeeEngine_,
        address fundingRateEngine_
    ) {
        if (admin_ == address(0)) revert MarginEngine__ZeroAddress();
        if (positionManager_ == address(0)) revert MarginEngine__ZeroAddress();
        if (oracle_ == address(0)) revert MarginEngine__ZeroAddress();
        if (marketRegistry_ == address(0)) revert MarginEngine__ZeroAddress();
        if (borrowFeeEngine_ == address(0)) revert MarginEngine__ZeroAddress();
        if (fundingRateEngine_ == address(0)) revert MarginEngine__ZeroAddress();

        _grantRole(ADMIN_ROLE, admin_);

        positionManager = IPositionManager(positionManager_);
        oracle = IOracleAdapter(oracle_);
        marketRegistry = IMarketRegistry(marketRegistry_);
        borrowFeeEngine = IBorrowFeeEngine(borrowFeeEngine_);
        fundingRateEngine = IFundingRateEngine(fundingRateEngine_);
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @inheritdoc IMarginEngine
    function computeEquity(uint256 positionId)
        external
        view
        override
        returns (EquityResult memory result)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) revert MarginEngine__PositionNotFound(positionId);

        result = _computeEquity(pos);
    }

    /// @inheritdoc IMarginEngine
    function computeMarginRequirements(
        bytes32 marketId,
        uint256 notional,
        uint256 leverage
    )
        external
        view
        override
        returns (MarginRequirements memory reqs)
    {
        uint256 rAdj = _getRAdj(marketId);

        reqs.mmMultiplier = RiskCurves.mmMultiplier(rAdj);
        reqs.imMultiplier = RiskCurves.imMultiplier(rAdj);

        // MM = BASE_MM_RATE × notional × MM_Multiplier
        reqs.maintenanceMargin = notional.wadMul(BASE_MM_RATE).wadMul(reqs.mmMultiplier);

        // IM = (notional / leverage) × IM_Multiplier × (1 + vol_adj + util_adj)
        reqs.initialMargin = _computeIM(marketId, notional, leverage, reqs.imMultiplier);
    }

    /// @inheritdoc IMarginEngine
    function getMaintenanceMargin(uint256 positionId)
        external
        view
        override
        returns (uint256 mm)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) revert MarginEngine__PositionNotFound(positionId);

        uint256 rAdj = _getRAdj(pos.marketId);
        uint256 mmMult = RiskCurves.mmMultiplier(rAdj);
        mm = pos.positionSize.wadMul(BASE_MM_RATE).wadMul(mmMult);
    }

    /// @inheritdoc IMarginEngine
    function getInitialMargin(
        bytes32 marketId,
        uint256 notional,
        uint256 leverage
    )
        external
        view
        override
        returns (uint256 im)
    {
        uint256 rAdj = _getRAdj(marketId);
        uint256 imMult = RiskCurves.imMultiplier(rAdj);
        im = _computeIM(marketId, notional, leverage, imMult);
    }

    /// @inheritdoc IMarginEngine
    function isLiquidatable(uint256 positionId)
        external
        view
        override
        returns (bool)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) return false;

        EquityResult memory eq = _computeEquity(pos);

        uint256 rAdj = _getRAdj(pos.marketId);
        uint256 mmMult = RiskCurves.mmMultiplier(rAdj);
        uint256 mm = pos.positionSize.wadMul(BASE_MM_RATE).wadMul(mmMult);
        uint256 buffer = pos.positionSize.wadMul(LIQUIDATION_BUFFER);
        uint256 threshold = mm + buffer;

        // Liquidatable when equity < MM + δ × notional
        return eq.equity < int256(threshold);
    }

    /// @inheritdoc IMarginEngine
    function isInDangerZone(uint256 positionId)
        external
        view
        override
        returns (bool)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) return false;

        EquityResult memory eq = _computeEquity(pos);

        uint256 rAdj = _getRAdj(pos.marketId);
        uint256 mmMult = RiskCurves.mmMultiplier(rAdj);
        uint256 mm = pos.positionSize.wadMul(BASE_MM_RATE).wadMul(mmMult);
        uint256 buffer = pos.positionSize.wadMul(LIQUIDATION_BUFFER);
        uint256 threshold = mm + buffer;

        // Danger zone: equity < 2× the liquidation threshold
        uint256 dangerThreshold = threshold.wadMul(DANGER_ZONE_MULT);
        return eq.equity < int256(dangerThreshold);
    }

    /// @inheritdoc IMarginEngine
    function validateMarginChecks(
        bytes32 marketId,
        address, /* user */
        bool, /* isLong */
        uint256 collateral,
        uint256 leverage
    )
        external
        view
        override
        returns (bool valid, uint8 failedCheck)
    {
        // Check 1: Collateral > 0
        if (collateral == 0) return (false, 1);

        // Check 2: Leverage >= 1×
        if (leverage < WAD) return (false, 2);

        // Compute notional = collateral × leverage
        uint256 notional = collateral.wadMul(leverage);

        // Check 3: Notional > 0
        if (notional == 0) return (false, 3);

        uint256 rAdj = _getRAdj(marketId);

        // Check 4: Collateral >= IM
        uint256 imMult = RiskCurves.imMultiplier(rAdj);
        uint256 im = _computeIM(marketId, notional, leverage, imMult);
        if (collateral < im) return (false, 4);

        // Check 5: Collateral >= MM (should be satisfied if IM is, but explicit)
        uint256 mmMult = RiskCurves.mmMultiplier(rAdj);
        uint256 mm = notional.wadMul(BASE_MM_RATE).wadMul(mmMult);
        if (collateral < mm) return (false, 5);

        return (true, 0);
    }

    /// @inheritdoc IMarginEngine
    function canRemoveCollateral(uint256 positionId, uint256 amount)
        external
        view
        override
        returns (bool allowed)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) return false;
        if (amount > pos.collateral) return false;

        // Compute current equity then adjust for removal
        EquityResult memory eq = _computeEquity(pos);

        // Adjust equity by the removed amount
        int256 newEquity = eq.equity - int256(amount);

        if (newEquity <= 0) return false;

        // Compute required MR floor = (MM / notional) + withdrawal_buffer
        uint256 rAdj = _getRAdj(pos.marketId);
        uint256 mmMult = RiskCurves.mmMultiplier(rAdj);
        uint256 mm = pos.positionSize.wadMul(BASE_MM_RATE).wadMul(mmMult);
        uint256 mmRatio = mm.wadDiv(pos.positionSize);
        uint256 requiredMR = mmRatio + WITHDRAWAL_BUFFER;

        // Post-removal MR
        uint256 postMR = uint256(newEquity).wadDiv(pos.positionSize);

        allowed = postMR >= requiredMR;
    }

    // ──────────────────────────────────────────────
    // External — Admin (state changing)
    // ──────────────────────────────────────────────

    /// @notice Update market risk parameters used for R_adjusted calculation
    /// @dev Called by keeper/admin to keep risk params current
    function updateMarketRiskParams(
        bytes32 marketId,
        uint256 sigmaCurrent_,
        uint256 sigmaBaseline_,
        uint256 externalDepth_,
        uint256 depthThreshold_,
        uint256 marketOI_,
        uint256 globalOI_,
        uint256 marketUtilization_
    ) external onlyRole(ADMIN_ROLE) {
        sigmaCurrent[marketId] = sigmaCurrent_;
        sigmaBaseline[marketId] = sigmaBaseline_;
        externalDepth[marketId] = externalDepth_;
        depthThreshold[marketId] = depthThreshold_;
        marketOI[marketId] = marketOI_;
        globalOI = globalOI_;
        marketUtilization[marketId] = marketUtilization_;
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

    /// @dev Compute equity breakdown for a position
    function _computeEquity(IPositionManager.Position memory pos)
        internal
        view
        returns (EquityResult memory result)
    {
        // PnL = direction × (PI_current - PI_entry) × position_size
        uint256 currentPI = oracle.getPI(pos.marketId);
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        // LEVER-BUG-1: Use execution price at entry (consistent with realized PnL in ExecutionEngine)
        int256 piDelta = int256(currentPI) - int256(pos.entryPrice);
        result.pnl = direction * piDelta * int256(pos.positionSize) / int256(WAD);

        // Accrued borrow fees (always positive, reduces equity)
        result.accruedBorrowFees = borrowFeeEngine.getAccruedFees(pos.id);

        // Accrued funding (signed: + = received, - = paid)
        result.accruedFunding = fundingRateEngine.getAccruedFunding(pos.id);

        // Equity = Collateral + PnL - BorrowFees + Funding
        result.equity = int256(pos.collateral)
            + result.pnl
            - int256(result.accruedBorrowFees)
            + result.accruedFunding;

        // Margin ratio = equity / notional (0 if equity <= 0)
        if (result.equity > 0) {
            result.marginRatio = uint256(result.equity).wadDiv(pos.positionSize);
        }
        // marginRatio defaults to 0 if equity <= 0
    }

    /// @dev Compute R_adjusted for a market from stored risk parameters
    function _getRAdj(bytes32 marketId) internal view returns (uint256) {
        // Get τ and isLive from MarketRegistry
        uint256 tauHours = marketRegistry.getTau(marketId);
        bool isLive_ = marketRegistry.isLive(marketId);

        // Compute τ_effective
        uint256 tauEff = RiskCurves.computeTauEffective(tauHours, isLive_);

        // Compute R(τ)
        uint256 r = RiskCurves.computeR(tauEff);

        // FIX LEVER-007: Skip market adjustment if depthThreshold not configured (defaults to no adjustment)
        uint256 mMarket;
        if (depthThreshold[marketId] == 0) {
            mMarket = WAD; // No market adjustment when unconfigured
        } else {
            mMarket = RiskCurves.computeMarketAdjustment(
                sigmaCurrent[marketId],
                sigmaBaseline[marketId],
                externalDepth[marketId],
                depthThreshold[marketId],
                marketOI[marketId],
                globalOI
            );
        }

        // R_adjusted = R(τ) × M_market
        return RiskCurves.computeRAdjusted(r, mMarket);
    }

    /// @dev Compute initial margin with adjustments
    /// IM = BASE_IM_RATE x notional x IM_Multiplier x (1 + vol_adj + util_adj)
    function _computeIM(
        bytes32 marketId,
        uint256 notional,
        uint256, /* leverage — reserved for future use */
        uint256 imMult
    ) internal view returns (uint256) {
        // IM_base = BASE_IM_RATE x notional (rate-based, not notional/leverage)
        uint256 imBase = notional.wadMul(BASE_IM_RATE);

        // IM after multiplier
        uint256 imScaled = imBase.wadMul(imMult);

        // vol_adj = α_IM × max(0, σ_current - σ_baseline)
        uint256 volAdj = 0;
        uint256 sc = sigmaCurrent[marketId];
        uint256 sb = sigmaBaseline[marketId];
        if (sc > sb) {
            volAdj = ALPHA_IM.wadMul(sc - sb);
        }

        // util_adj = β × max(0, market_utilization - 0.50)
        uint256 utilAdj = 0;
        uint256 util = marketUtilization[marketId];
        if (util > UTIL_THRESHOLD) {
            utilAdj = BETA_IM.wadMul(util - UTIL_THRESHOLD);
        }

        // IM_adjusted = IM_scaled × (1 + vol_adj + util_adj)
        uint256 adjFactor = WAD + volAdj + utilAdj;
        return imScaled.wadMul(adjFactor);
    }

    // ──────────────────────────────────────────────
    // View — Aggregate Unrealized PnL
    // ──────────────────────────────────────────────

    /// @notice Compute aggregate unrealized PnL across all open positions in all markets.
    /// @dev Iterates open positions per market (efficient: skips closed positions).
    ///      Gas-intensive view; intended for keeper off-chain reads (eth_call), not on-chain calls.
    /// @return netPnL Sum of unrealized PnL (positive = traders profitable = vault liability)
    function computeNetUnrealizedPnL() external view returns (int256 netPnL) {
        bytes32[] memory markets = marketRegistry.getActiveMarkets();
        for (uint256 m = 0; m < markets.length; m++) {
            uint256[] memory posIds = positionManager.getMarketPositions(markets[m]);
            for (uint256 p = 0; p < posIds.length; p++) {
                IPositionManager.Position memory pos = positionManager.getPosition(posIds[p]);
                EquityResult memory eq = _computeEquity(pos);
                netPnL += eq.pnl;
            }
        }
    }
}
