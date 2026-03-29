// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { IExecutionEngine } from "./interfaces/IExecutionEngine.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { IOILimits } from "./interfaces/IOILimits.sol";
import { IMarginEngine } from "./interfaces/IMarginEngine.sol";
import { IOracleAdapter } from "./interfaces/IOracleAdapter.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { ILeverageModel } from "./interfaces/ILeverageModel.sol";
import { IFeeRouter } from "./interfaces/IFeeRouter.sol";
import { IBorrowFeeEngine } from "./interfaces/IBorrowFeeEngine.sol";
import { IFundingRateEngine } from "./interfaces/IFundingRateEngine.sol";
import { IAccountManager } from "./interfaces/IAccountManager.sol";
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { IInsuranceFund } from "./interfaces/IInsuranceFund.sol";
import { RiskCurves } from "./libraries/RiskCurves.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title ExecutionEngine
/// @notice Orchestrates position opens/closes. Computes entry/exit prices via
///         PI + imbalance-adjusted linear impact using imbalance_delta.
///         NOT a vAMM. Impact is PI-independent (no boundary blowup).
/// @dev Impact model (WP Section 10.2):
///   base_impact = trade_size / (market_depth × 2)
///   imbalance_delta = |imbalance_after| - |imbalance_before|
///   impact = min(base_impact × (1 + imbalance_delta × IMBALANCE_MULTIPLIER), MAX_IMPACT)
///   entry_price = PI × (1 ± impact)
contract ExecutionEngine is IExecutionEngine, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;

    /// @notice Transaction fee rate: 0.10% (10 bps), matches FeeRouter.TX_FEE_RATE
    uint256 public constant TX_FEE_RATE = 1e15;

    /// @notice Maximum price impact cap: 5% (0.05)
    uint256 public constant MAX_IMPACT = 5e16;

    /// @notice Imbalance multiplier applied to imbalance_delta
    uint256 public constant IMBALANCE_MULTIPLIER = 2e18;

    // ──────────────────────────────────────────────
    // Additional Errors
    // ──────────────────────────────────────────────

    error ExecutionEngine__ZeroAddress();
    error ExecutionEngine__ZeroCollateral();
    error ExecutionEngine__ZeroLeverage();

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ──────────────────────────────────────────────
    // Type declarations
    // ──────────────────────────────────────────────

    /// @dev Intermediate struct to avoid stack-too-deep during position creation
    struct OpenContext {
        uint256 pi;
        uint256 entryPrice;
        uint256 impact;
        uint256 notional;
        uint256 collateralNet;
    }

    // ──────────────────────────────────────────────
    // State variables
    // ──────────────────────────────────────────────

    IPositionManager public immutable positionManager;
    IOILimits public immutable oiLimits;
    IMarginEngine public immutable marginEngine;
    IOracleAdapter public immutable oracleAdapter;
    IMarketRegistry public immutable marketRegistry;
    ILeverageModel public immutable leverageModel;
    IFeeRouter public immutable feeRouter;
    IBorrowFeeEngine public immutable borrowFeeEngine;
    IFundingRateEngine public immutable fundingRateEngine;
    IAccountManager public immutable accountManager;
    ILeverVault public immutable leverVault;
    IInsuranceFund public immutable insuranceFund;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param _positionManager PositionManager address
    /// @param _oiLimits OILimits address
    /// @param _marginEngine MarginEngine address
    /// @param _oracleAdapter OracleAdapter address
    /// @param _marketRegistry MarketRegistry address
    /// @param _leverageModel LeverageModel address
    /// @param _feeRouter FeeRouter address
    /// @param _borrowFeeEngine BorrowFeeEngine address
    /// @param _fundingRateEngine FundingRateEngine address
    /// @param _accountManager AccountManager address
    /// @param _leverVault LeverVault address (LP pool that backs trades)
    /// @param _admin Initial admin address
    constructor(
        address _positionManager,
        address _oiLimits,
        address _marginEngine,
        address _oracleAdapter,
        address _marketRegistry,
        address _leverageModel,
        address _feeRouter,
        address _borrowFeeEngine,
        address _fundingRateEngine,
        address _accountManager,
        address _leverVault,
        address _insuranceFund,
        address _admin
    ) {
        if (
            _positionManager == address(0) || _oiLimits == address(0) || _marginEngine == address(0)
                || _oracleAdapter == address(0) || _marketRegistry == address(0) || _leverageModel == address(0)
                || _feeRouter == address(0) || _borrowFeeEngine == address(0) || _fundingRateEngine == address(0)
                || _accountManager == address(0) || _leverVault == address(0) || _insuranceFund == address(0)
                || _admin == address(0)
        ) {
            revert ExecutionEngine__ZeroAddress();
        }

        positionManager = IPositionManager(_positionManager);
        oiLimits = IOILimits(_oiLimits);
        marginEngine = IMarginEngine(_marginEngine);
        oracleAdapter = IOracleAdapter(_oracleAdapter);
        marketRegistry = IMarketRegistry(_marketRegistry);
        leverageModel = ILeverageModel(_leverageModel);
        feeRouter = IFeeRouter(_feeRouter);
        borrowFeeEngine = IBorrowFeeEngine(_borrowFeeEngine);
        fundingRateEngine = IFundingRateEngine(_fundingRateEngine);
        accountManager = IAccountManager(_accountManager);
        leverVault = ILeverVault(_leverVault);
        insuranceFund = IInsuranceFund(_insuranceFund);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ──────────────────────────────────────────────
    // External functions (state-changing)
    // ──────────────────────────────────────────────

    /// @inheritdoc IExecutionEngine
    function openPosition(OpenParams calldata params)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 positionId)
    {
        if (params.collateral == 0) revert ExecutionEngine__ZeroCollateral();
        if (params.leverage == 0) revert ExecutionEngine__ZeroLeverage();

        _validateMarket(params.marketId);

        // FIX LEVER-BUG-7: Reject positions on markets without configured risk parameters.
        // When depthThreshold=0, maintenance margin defaults to M_market=1.0 (overly lenient),
        // making liquidations impossible. Markets must be configured before trading.
        if (marginEngine.depthThreshold(params.marketId) == 0) {
            revert ExecutionEngine__MarketNotConfigured(params.marketId);
        }

        uint256 maxLev = leverageModel.getEffectiveMaxLeverage(params.marketId);
        if (params.leverage > maxLev) {
            revert ExecutionEngine__LeverageExceedsMax(params.leverage, maxLev);
        }

        uint256 notional = params.collateral.wadMul(params.leverage);
        if (notional == 0) revert ExecutionEngine__ZeroSize();

        // NOTE: OI is increased INSIDE _executeOpen, AFTER price computation.
        // This prevents the trade's own OI from double-counting in imbalance_delta.
        positionId = _executeOpen(params, notional);
    }

    /// @inheritdoc IExecutionEngine
    function closePosition(uint256 positionId) external override nonReentrant whenNotPaused {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);

        if (!pos.isOpen) revert ExecutionEngine__PositionNotFound(positionId);
        if (pos.owner != msg.sender) revert ExecutionEngine__NotPositionOwner(positionId, msg.sender);

        _executeClose(positionId, pos);
    }

    /// @inheritdoc IExecutionEngine
    function addCollateral(uint256 positionId, uint256 amount) external override nonReentrant whenNotPaused {
        if (amount == 0) revert ExecutionEngine__ZeroCollateral();

        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) revert ExecutionEngine__PositionNotFound(positionId);
        if (pos.owner != msg.sender) revert ExecutionEngine__NotPositionOwner(positionId, msg.sender);

        accountManager.lockCollateral(msg.sender, amount);

        uint256 newCollateral = pos.collateral + amount;
        positionManager.updateCollateral(positionId, newCollateral);

        emit CollateralAdded(positionId, amount, newCollateral);
    }

    /// @inheritdoc IExecutionEngine
    function removeCollateral(uint256 positionId, uint256 amount) external override nonReentrant whenNotPaused {
        if (amount == 0) revert ExecutionEngine__ZeroCollateral();

        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) revert ExecutionEngine__PositionNotFound(positionId);
        if (pos.owner != msg.sender) revert ExecutionEngine__NotPositionOwner(positionId, msg.sender);

        if (!marginEngine.canRemoveCollateral(positionId, amount)) {
            revert ExecutionEngine__InsufficientCollateral(pos.collateral - amount, pos.collateral);
        }

        accountManager.releaseCollateral(msg.sender, amount);

        uint256 newCollateral = pos.collateral - amount;
        positionManager.updateCollateral(positionId, newCollateral);

        emit CollateralRemoved(positionId, amount, newCollateral);
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
    // External functions (view)
    // ──────────────────────────────────────────────

    /// @inheritdoc IExecutionEngine
    function previewExecution(
        bytes32 marketId,
        bool isLong,
        uint256 notional,
        bool isOpen
    ) external view override returns (uint256 price, uint256 impact) {
        uint256 pi = oracleAdapter.getPI(marketId);
        (price, impact) = _computeExecutionPrice(marketId, isLong, notional, pi, isOpen);
    }

    /// @inheritdoc IExecutionEngine
    function computeBaseImpact(bytes32 marketId, uint256 tradeSize) external view override returns (uint256 impact) {
        uint256 depth = _getMarketDepth(marketId);
        if (depth == 0) return MAX_IMPACT;
        impact = tradeSize.wadDiv(depth * 2);
    }

    /// @inheritdoc IExecutionEngine
    function computeImbalanceDelta(
        bytes32 marketId,
        bool isLong,
        uint256 notional
    ) external view override returns (int256 delta) {
        delta = _computeImbalanceDelta(marketId, isLong, notional, true);
    }

    /// @inheritdoc IExecutionEngine
    function getMarketDepth(bytes32 marketId) external view override returns (uint256 depth) {
        depth = _getMarketDepth(marketId);
    }

    // ──────────────────────────────────────────────
    // Private functions
    // ──────────────────────────────────────────────

    /// @dev Validate market is active and oracle is not frozen
    function _validateMarket(bytes32 _marketId) private view {
        IMarketRegistry.MarketState state = marketRegistry.getMarketState(_marketId);
        if (state != IMarketRegistry.MarketState.ACTIVE) {
            revert ExecutionEngine__MarketNotActive(_marketId);
        }
        if (oracleAdapter.isFrozen(_marketId)) {
            revert ExecutionEngine__MarketFrozen(_marketId);
        }
    }

    /// @dev Compute price, validate margin, settle collateral, create position, emit event
    function _executeOpen(OpenParams calldata params, uint256 notional) private returns (uint256 positionId) {
        OpenContext memory ctx;
        ctx.notional = notional;
        ctx.pi = oracleAdapter.getPI(params.marketId);
        (ctx.entryPrice, ctx.impact) =
            _computeExecutionPrice(params.marketId, params.isLong, notional, ctx.pi, true);
        // FIX LEVER-P03 (Bug A): Compute fee locally instead of calling collectTransactionFee.
        // collectTransactionFee distributes from FeeRouter's own reserves before USDT is moved
        // there, causing phantom USDT to accumulate in AccountManager and FeeRouter reserves to drain.
        // Correct flow: compute fee -> debit user accounting -> transfer USDT to FeeRouter -> route.
        uint256 txFee = notional * TX_FEE_RATE / WAD;
        ctx.collateralNet = params.collateral - txFee;

        _validateMargin(params.marketId, params.isLong, ctx.collateralNet, params.leverage);

        // Lock position collateral in AccountManager
        accountManager.lockCollateral(msg.sender, ctx.collateralNet);

        // Debit TX fee from user's accounting balance and transfer USDT to FeeRouter, then route
        if (txFee > 0) {
            accountManager.debitPnL(msg.sender, txFee);
            accountManager.transferOut(address(feeRouter), txFee);
            feeRouter.routeFees(IFeeRouter.FeeType.TRANSACTION, txFee);
        }

        // Increase OI AFTER price computation to avoid double-counting in imbalance_delta.
        // If caps are exceeded, this reverts and the whole tx rolls back.
        oiLimits.increaseOI(params.marketId, msg.sender, params.isLong, ctx.notional);

        positionId = _storePosition(params, ctx);

        // Track position ownership in AccountManager
        accountManager.assignPosition(msg.sender, positionId);

        emit PositionOpened(
            positionId, params.marketId, msg.sender, params.isLong,
            ctx.collateralNet, params.leverage, ctx.pi, ctx.entryPrice,
            notional, ctx.impact, block.timestamp
        );
    }

    /// @dev Create position record in PositionManager
    function _storePosition(OpenParams calldata params, OpenContext memory ctx) private returns (uint256) {
        return positionManager.createPosition(
            msg.sender,
            params.marketId,
            params.isLong,
            ctx.pi,
            ctx.entryPrice,
            ctx.notional,
            ctx.collateralNet,
            params.leverage,
            borrowFeeEngine.getBorrowIndex(params.marketId, params.isLong),
            fundingRateEngine.getFundingIndex(params.marketId)
        );
    }

    /// @dev Validate margin checks — reverts if any check fails
    function _validateMargin(bytes32 _marketId, bool _isLong, uint256 _collateralNet, uint256 _leverage) private view {
        (bool valid, uint8 failedCheck) =
            marginEngine.validateMarginChecks(_marketId, msg.sender, _isLong, _collateralNet, _leverage);
        if (!valid) revert ExecutionEngine__MarginCheckFailed(failedCheck);
    }

    /// @dev Execute the close: compute exit price, settle PnL, update state, emit event
    function _executeClose(uint256 positionId, IPositionManager.Position memory pos) private {
        uint256 pi = oracleAdapter.getPI(pos.marketId);
        (uint256 exitPrice,) = _computeExecutionPrice(pos.marketId, pos.isLong, pos.positionSize, pi, false);

        // FIX LEVER-001: Use raw PI values for PnL (consistent with MarginEngine/SettlementEngine)
        int256 pnl = _computePnL(pos.isLong, pi, pos.entryPI, pos.positionSize);
        uint256 borrowFees = borrowFeeEngine.getAccruedFees(positionId);
        int256 accruedFunding = fundingRateEngine.getAccruedFunding(positionId);

        // FIX LEVER-P03 (Bug B) + LEVER-009: Compute closing fee locally.
        // collectTransactionFee caused double-distribution: once from FeeRouter reserves here,
        // and again when _settlePnL transferred closingFee to FeeRouter via routeFees.
        // Now closingFee is computed locally and only routed once inside _settlePnL.
        uint256 closingFee = pos.positionSize * TX_FEE_RATE / WAD;

        // Settle PnL: bookkeeping + actual USDT transfers between AccountManager, Vault, FeeRouter
        uint256 badDebt = _settlePnL(pos.owner, pos.collateral, pnl, borrowFees, accruedFunding, closingFee);

        // FIX LEVER-004: Route bad debt through InsuranceFund waterfall
        if (badDebt > 0) {
            // FIX LEVER-P04: Pass leverVault as recipient so insurance USDT goes to vault, not here
            (, uint256 remainder) = insuranceFund.absorbBadDebt(pos.marketId, badDebt, address(leverVault));
            if (remainder > 0) {
                // FIX LEVER-BUG-5: remainder is WAD (1e18), socializeLoss expects USDT (1e6)
                leverVault.socializeLoss(remainder / 1e12);
            }
            emit BadDebtRecorded(positionId, pos.owner, badDebt);
        }

        // FIX LEVER-P06: Remove this position's unrealized PnL from vault NAV tracking.
        // On open, unrealized PnL is 0 so no update needed. On close, the realized pnl was
        // previously part of the running _netUnrealizedPnL total — remove it now.
        int256 currentUnrealized = leverVault.getNetUnrealizedPnL();
        leverVault.updateUnrealizedPnL(currentUnrealized - pnl);

        // Update downstream state
        oiLimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize);
        positionManager.closePosition(positionId);
        accountManager.removePosition(pos.owner, positionId);

        emit PositionClosed(
            positionId, pos.marketId, pos.owner, exitPrice, pnl, borrowFees, accruedFunding, block.timestamp
        );
    }

    /// @dev Settle PnL with AccountManager on position close.
    ///      1. Bookkeeping: release collateral, credit/debit net pnlDelta
    ///      2. Token transfers: vault pays price profits, AccountManager sends price losses to vault,
    ///         borrow fees routed through FeeRouter for 50/30/20 split.
    ///         Funding stays internal to AccountManager (trader-to-trader, no external USDT movement).
    /// @return badDebt Amount the user could not cover (for InsuranceFund routing)
    function _settlePnL(
        address owner,
        uint256 collateral,
        int256 pnl,
        uint256 borrowFees,
        int256 accruedFunding,
        uint256 closingFee
    ) private returns (uint256 badDebt) {
        accountManager.releaseCollateral(owner, collateral);

        // Net change to user's balance beyond their collateral (includes closing fee)
        int256 pnlDelta = pnl - int256(borrowFees) - int256(closingFee) + accruedFunding;

        if (pnlDelta > 0) {
            accountManager.creditPnL(owner, uint256(pnlDelta));
        } else if (pnlDelta < 0) {
            badDebt = accountManager.debitPnL(owner, uint256(-pnlDelta));
        }

        // ── Token transfers ──

        // Inflow: vault pays trader's price profit
        if (pnl > 0) {
            leverVault.fundTraderPnL(address(accountManager), uint256(pnl));
        }

        // Outflows: price loss → vault, fees → FeeRouter
        uint256 pnlLoss = pnl < 0 ? uint256(-pnl) : 0;
        uint256 totalFees = borrowFees + closingFee;
        uint256 totalOutflow = pnlLoss + totalFees;

        if (totalOutflow > 0) {
            uint256 transferable = badDebt >= totalOutflow ? 0 : totalOutflow - badDebt;

            // FeeRouter has priority (protocol revenue), vault absorbs shortfall from bad debt
            uint256 toFeeRouter = totalFees > transferable ? transferable : totalFees;
            uint256 toVault = transferable - toFeeRouter;
            if (toVault > pnlLoss) toVault = pnlLoss;

            if (toVault > 0) {
                accountManager.transferOut(address(leverVault), toVault);
            }
            if (toFeeRouter > 0) {
                accountManager.transferOut(address(feeRouter), toFeeRouter);

                // FIX LEVER-BUG-8: Route borrow fees and closing fee with correct FeeTypes.
                // Previously all fees were routed as BORROW, misclassifying the closing tx fee.
                uint256 borrowToRoute = borrowFees > toFeeRouter ? toFeeRouter : borrowFees;
                uint256 closingToRoute = toFeeRouter - borrowToRoute;
                if (borrowToRoute > 0) feeRouter.routeFees(IFeeRouter.FeeType.BORROW, borrowToRoute);
                if (closingToRoute > 0) feeRouter.routeFees(IFeeRouter.FeeType.TRANSACTION, closingToRoute);
            }
        }

    }

    // ──────────────────────────────────────────────
    // Internal functions
    // ──────────────────────────────────────────────

    /// @dev Compute execution price using the imbalance_delta model
    function _computeExecutionPrice(
        bytes32 marketId,
        bool isLong,
        uint256 notional,
        uint256 pi,
        bool isOpen
    ) internal view returns (uint256 price, uint256 impact) {
        uint256 depth = _getMarketDepth(marketId);
        uint256 baseImpact;
        if (depth == 0) {
            baseImpact = MAX_IMPACT;
        } else {
            baseImpact = notional.wadDiv(depth * 2);
        }

        int256 imbalanceDelta = _computeImbalanceDelta(marketId, isLong, notional, isOpen);

        // impact = base_impact × (1 + imbalance_delta × IMBALANCE_MULTIPLIER)
        int256 adjustment = int256(WAD) + (imbalanceDelta * int256(IMBALANCE_MULTIPLIER)) / int256(WAD);

        if (adjustment < 0) {
            impact = 0;
        } else {
            impact = baseImpact.wadMul(uint256(adjustment));
        }

        if (impact > MAX_IMPACT) {
            impact = MAX_IMPACT;
        }

        // Apply directional pricing
        if (isOpen) {
            if (isLong) {
                price = pi.wadMul(WAD + impact);
            } else {
                price = pi.wadMul(WAD - impact);
            }
        } else {
            if (isLong) {
                price = pi.wadMul(WAD - impact);
            } else {
                price = pi.wadMul(WAD + impact);
            }
        }
    }

    /// @dev Compute imbalance_delta = |imbalance_after| - |imbalance_before|
    function _computeImbalanceDelta(
        bytes32 marketId,
        bool isLong,
        uint256 notional,
        bool isOpen
    ) internal view returns (int256 delta) {
        uint256 longOI = oiLimits.getSideOI(marketId, true);
        uint256 shortOI = oiLimits.getSideOI(marketId, false);
        uint256 totalOI = longOI + shortOI;

        uint256 absBefore;
        if (totalOI > 0) {
            int256 imbalanceBefore = (int256(longOI) - int256(shortOI)) * int256(WAD) / int256(totalOI);
            absBefore = FixedPointMath.abs(imbalanceBefore);
        }

        // Compute post-trade OI
        uint256 longOIAfter;
        uint256 shortOIAfter;
        if (isOpen) {
            longOIAfter = isLong ? longOI + notional : longOI;
            shortOIAfter = isLong ? shortOI : shortOI + notional;
        } else {
            longOIAfter = isLong ? (notional > longOI ? 0 : longOI - notional) : longOI;
            shortOIAfter = isLong ? shortOI : (notional > shortOI ? 0 : shortOI - notional);
        }
        uint256 totalOIAfter = longOIAfter + shortOIAfter;

        uint256 absAfter;
        if (totalOIAfter > 0) {
            int256 imbalanceAfter = (int256(longOIAfter) - int256(shortOIAfter)) * int256(WAD) / int256(totalOIAfter);
            absAfter = FixedPointMath.abs(imbalanceAfter);
        }

        delta = int256(absAfter) - int256(absBefore);
    }

    /// @dev Compute market depth = Market_OI_Cap × Execution_Depth_Mult(R_adjusted)
    function _getMarketDepth(bytes32 marketId) internal view returns (uint256 depth) {
        uint256 marketOICap = oiLimits.getMarketOICap(marketId);
        uint256 rAdjusted = _computeRAdjusted(marketId);
        uint256 depthMult = RiskCurves.executionDepthMultiplier(rAdjusted);
        depth = marketOICap.wadMul(depthMult);
    }

    /// @dev Compute R_adjusted for a market. M_market = 1.0 to avoid circular dependencies.
    function _computeRAdjusted(bytes32 marketId) internal view returns (uint256) {
        uint256 tau = marketRegistry.getTau(marketId);
        bool isLive = marketRegistry.isLive(marketId);
        uint256 tauEff = RiskCurves.computeTauEffective(tau, isLive);
        return RiskCurves.computeR(tauEff);
    }

    /// @dev Compute PnL for a position
    function _computePnL(
        bool isLong,
        uint256 exitPrice,
        uint256 entryPrice,
        uint256 positionSize
    ) internal pure returns (int256 pnl) {
        int256 priceDiff = int256(exitPrice) - int256(entryPrice);
        if (!isLong) priceDiff = -priceDiff;
        pnl = (priceDiff * int256(positionSize)) / int256(WAD);
    }
}
