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
        address _admin
    ) {
        if (
            _positionManager == address(0) || _oiLimits == address(0) || _marginEngine == address(0)
                || _oracleAdapter == address(0) || _marketRegistry == address(0) || _leverageModel == address(0)
                || _feeRouter == address(0) || _borrowFeeEngine == address(0) || _fundingRateEngine == address(0)
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

        uint256 maxLev = leverageModel.getEffectiveMaxLeverage(params.marketId);
        if (params.leverage > maxLev) {
            revert ExecutionEngine__LeverageExceedsMax(params.leverage, maxLev);
        }

        uint256 notional = params.collateral.wadMul(params.leverage);
        if (notional == 0) revert ExecutionEngine__ZeroSize();

        oiLimits.increaseOI(params.marketId, msg.sender, params.isLong, notional);

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

    /// @dev Compute price, validate margin, create position, emit event
    function _executeOpen(OpenParams calldata params, uint256 notional) private returns (uint256 positionId) {
        OpenContext memory ctx;
        ctx.notional = notional;
        ctx.pi = oracleAdapter.getPI(params.marketId);
        (ctx.entryPrice, ctx.impact) =
            _computeExecutionPrice(params.marketId, params.isLong, notional, ctx.pi, true);
        ctx.collateralNet = params.collateral - feeRouter.collectTransactionFee(notional);

        _validateMargin(params.marketId, params.isLong, ctx.collateralNet, params.leverage);

        positionId = _storePosition(params, ctx);

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

    /// @dev Execute the close: compute exit price, emit event
    function _executeClose(uint256 positionId, IPositionManager.Position memory pos) private {
        uint256 pi = oracleAdapter.getPI(pos.marketId);
        (uint256 exitPrice,) = _computeExecutionPrice(pos.marketId, pos.isLong, pos.positionSize, pi, false);

        int256 pnl = _computePnL(pos.isLong, exitPrice, pos.entryPrice, pos.positionSize);
        uint256 borrowFees = borrowFeeEngine.getAccruedFees(positionId);
        int256 accruedFunding = fundingRateEngine.getAccruedFunding(positionId);

        oiLimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize);
        positionManager.closePosition(positionId);

        emit PositionClosed(
            positionId, pos.marketId, pos.owner, exitPrice, pnl, borrowFees, accruedFunding, block.timestamp
        );
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
