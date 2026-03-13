// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { ILiquidationEngine } from "./interfaces/ILiquidationEngine.sol";
import { IMarginEngine } from "./interfaces/IMarginEngine.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { IExecutionEngine } from "./interfaces/IExecutionEngine.sol";
import { IOILimits } from "./interfaces/IOILimits.sol";
import { IAccountManager } from "./interfaces/IAccountManager.sol";
import { IInsuranceFund } from "./interfaces/IInsuranceFund.sol";
import { IFeeRouter } from "./interfaces/IFeeRouter.sol";
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// 2. Custom Errors (beyond interface)
// 3. Events (defined in ILiquidationEngine)

/// @title LiquidationEngine
/// @notice Force-closes positions when equity < MM. Three execution paths:
///         Path A (self-liquidation on user interaction), Path B (protocol-triggered on
///         oracle update), Path C (permissionless external). Liquidations close through
///         the standard execution model with impact. Bad debt flows through insurance →
///         LP socialization waterfall. Continues during PENDING_RESOLUTION with 2× MM.
contract LiquidationEngine is ILiquidationEngine, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;

    /// @notice Liquidation fee: 1.0% (100 bps) of notional (WP 13.5)
    uint256 public constant LIQUIDATION_FEE_RATE = 1e16;

    /// @notice External liquidator bounty: 10% of liquidation fee
    uint256 public constant LIQUIDATOR_BOUNTY_SHARE = 1e17;

    /// @notice Partial liquidation threshold: 10% of market depth
    uint256 public constant PARTIAL_LIQ_THRESHOLD = 1e17;

    /// @notice Partial liquidation chunk: 5% of market depth per chunk
    uint256 public constant PARTIAL_LIQ_CHUNK = 5e16;

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ──────────────────────────────────────────────
    // Additional Errors
    // ──────────────────────────────────────────────

    error LiquidationEngine__ZeroAddress();

    // ──────────────────────────────────────────────
    // Type Declarations
    // ──────────────────────────────────────────────

    /// @dev Intermediate struct to avoid stack-too-deep in liquidation logic
    struct LiqContext {
        int256 equity;
        uint256 mm;
        uint256 fee;
        uint256 badDebt;
        uint256 traderReceives;
        uint256 insurancePaid;
        uint256 socializedAmount;
        bool isPartial;
    }

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    IMarginEngine public immutable marginEngine;
    IPositionManager public immutable positionManager;
    IExecutionEngine public immutable executionEngine;
    IOILimits public immutable oiLimits;
    IAccountManager public immutable accountManager;
    IInsuranceFund public immutable insuranceFund;
    IFeeRouter public immutable feeRouter;
    ILeverVault public immutable leverVault;
    IMarketRegistry public immutable marketRegistry;

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    uint256 private _totalBadDebt;
    uint256 private _totalLiquidationFees;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param admin_ Admin address
    /// @param marginEngine_ MarginEngine contract
    /// @param positionManager_ PositionManager contract
    /// @param executionEngine_ ExecutionEngine contract
    /// @param oiLimits_ OILimits contract
    /// @param accountManager_ AccountManager contract
    /// @param insuranceFund_ InsuranceFund contract
    /// @param feeRouter_ FeeRouter contract
    /// @param leverVault_ LeverVault contract
    /// @param marketRegistry_ MarketRegistry contract
    constructor(
        address admin_,
        address marginEngine_,
        address positionManager_,
        address executionEngine_,
        address oiLimits_,
        address accountManager_,
        address insuranceFund_,
        address feeRouter_,
        address leverVault_,
        address marketRegistry_
    ) {
        if (admin_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (marginEngine_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (positionManager_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (executionEngine_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (oiLimits_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (accountManager_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (insuranceFund_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (feeRouter_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (leverVault_ == address(0)) revert LiquidationEngine__ZeroAddress();
        if (marketRegistry_ == address(0)) revert LiquidationEngine__ZeroAddress();

        marginEngine = IMarginEngine(marginEngine_);
        positionManager = IPositionManager(positionManager_);
        executionEngine = IExecutionEngine(executionEngine_);
        oiLimits = IOILimits(oiLimits_);
        accountManager = IAccountManager(accountManager_);
        insuranceFund = IInsuranceFund(insuranceFund_);
        feeRouter = IFeeRouter(feeRouter_);
        leverVault = ILeverVault(leverVault_);
        marketRegistry = IMarketRegistry(marketRegistry_);

        _grantRole(ADMIN_ROLE, admin_);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc ILiquidationEngine
    function liquidate(uint256 positionId)
        external
        override
        nonReentrant
        whenNotPaused
        returns (LiquidationResult memory result)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) revert LiquidationEngine__PositionNotFound(positionId);

        _validateMarketState(pos.marketId);

        if (!marginEngine.isLiquidatable(positionId)) {
            int256 equity = marginEngine.computeEquity(positionId).equity;
            uint256 mm = marginEngine.getMaintenanceMargin(positionId);
            revert LiquidationEngine__PositionNotLiquidatable(positionId, equity, mm);
        }

        result = _executeLiquidation(positionId, pos, msg.sender);
    }

    /// @inheritdoc ILiquidationEngine
    function batchLiquidate(uint256[] calldata positionIds)
        external
        override
        nonReentrant
        whenNotPaused
        returns (LiquidationResult[] memory results)
    {
        results = new LiquidationResult[](positionIds.length);
        for (uint256 i; i < positionIds.length; ++i) {
            IPositionManager.Position memory pos = positionManager.getPosition(positionIds[i]);
            if (!pos.isOpen) continue;

            IMarketRegistry.MarketState state = marketRegistry.getMarketState(pos.marketId);
            if (
                state != IMarketRegistry.MarketState.ACTIVE
                    && state != IMarketRegistry.MarketState.PENDING_RESOLUTION
            ) continue;

            if (!marginEngine.isLiquidatable(positionIds[i])) continue;

            results[i] = _executeLiquidation(positionIds[i], pos, msg.sender);
        }
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────

    /// @notice Pause the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────
    // External — View
    // ──────────────────────────────────────────────

    /// @inheritdoc ILiquidationEngine
    function isLiquidatable(uint256 positionId) external view override returns (bool) {
        if (!positionManager.isPositionOpen(positionId)) return false;
        return marginEngine.isLiquidatable(positionId);
    }

    /// @inheritdoc ILiquidationEngine
    function getLiquidatablePositions(bytes32 marketId)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256[] memory allPositions = positionManager.getMarketPositions(marketId);
        uint256 count;

        for (uint256 i; i < allPositions.length; ++i) {
            if (marginEngine.isLiquidatable(allPositions[i])) ++count;
        }

        uint256[] memory result = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < allPositions.length; ++i) {
            if (marginEngine.isLiquidatable(allPositions[i])) {
                result[idx++] = allPositions[i];
            }
        }

        return result;
    }

    /// @inheritdoc ILiquidationEngine
    function previewLiquidation(uint256 positionId)
        external
        view
        override
        returns (LiquidationResult memory result)
    {
        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        if (!pos.isOpen) revert LiquidationEngine__PositionNotFound(positionId);

        IMarginEngine.EquityResult memory eqResult = marginEngine.computeEquity(positionId);

        uint256 feeCalculated = pos.positionSize.wadMul(LIQUIDATION_FEE_RATE);
        uint256 fee;
        if (eqResult.equity > 0) {
            fee = feeCalculated < uint256(eqResult.equity) ? feeCalculated : uint256(eqResult.equity);
        }

        int256 remainingEquity = eqResult.equity - int256(fee);

        result.positionId = positionId;
        result.liquidationFee = fee;
        result.remainingEquity = remainingEquity;

        if (remainingEquity < 0) {
            result.badDebt = uint256(-remainingEquity);
        }

        uint256 marketDepth = executionEngine.getMarketDepth(pos.marketId);
        result.isPartial = pos.positionSize > marketDepth.wadMul(PARTIAL_LIQ_THRESHOLD);
    }

    /// @inheritdoc ILiquidationEngine
    function getLiquidationFeeRate() external pure override returns (uint256) {
        return LIQUIDATION_FEE_RATE;
    }

    /// @inheritdoc ILiquidationEngine
    function getLiquidatorBountyShare() external pure override returns (uint256) {
        return LIQUIDATOR_BOUNTY_SHARE;
    }

    /// @inheritdoc ILiquidationEngine
    function totalBadDebt() external view override returns (uint256) {
        return _totalBadDebt;
    }

    /// @inheritdoc ILiquidationEngine
    function totalLiquidationFees() external view override returns (uint256) {
        return _totalLiquidationFees;
    }

    // ──────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────

    /// @dev Validate market is ACTIVE or PENDING_RESOLUTION (not RESOLVED/VOIDED)
    function _validateMarketState(bytes32 marketId) internal view {
        IMarketRegistry.MarketState state = marketRegistry.getMarketState(marketId);
        if (
            state != IMarketRegistry.MarketState.ACTIVE
                && state != IMarketRegistry.MarketState.PENDING_RESOLUTION
        ) {
            revert LiquidationEngine__MarketResolved(marketId);
        }
    }

    /// @dev Core liquidation execution using LiqContext to avoid stack-too-deep.
    ///      Positions exceeding PARTIAL_LIQ_THRESHOLD of market depth are flagged as partial.
    ///      True chunked partial liquidation requires PositionManager.updateSize (future iteration).
    function _executeLiquidation(
        uint256 positionId,
        IPositionManager.Position memory pos,
        address liquidator
    ) internal returns (LiquidationResult memory result) {
        LiqContext memory ctx;

        // 1. Determine partial flag
        uint256 marketDepth = executionEngine.getMarketDepth(pos.marketId);
        ctx.isPartial = pos.positionSize > marketDepth.wadMul(PARTIAL_LIQ_THRESHOLD);

        // 2. Compute equity and MM
        ctx.equity = marginEngine.computeEquity(positionId).equity;
        ctx.mm = marginEngine.getMaintenanceMargin(positionId);

        // 3. Compute fee and outcomes
        _computeFeeAndOutcome(ctx, pos.positionSize);

        // 4. Route liquidation fee
        _routeFee(ctx.fee, liquidator);

        // 5. Handle bad debt (insurance → LP socialization)
        if (ctx.badDebt > 0) {
            (ctx.insurancePaid, ctx.socializedAmount) =
                _handleBadDebt(pos.marketId, positionId, ctx.badDebt);
        }

        // 6. Close position
        _closeAndSettle(pos, positionId, ctx.traderReceives);

        // 7. Update accumulators
        _totalLiquidationFees += ctx.fee;
        _totalBadDebt += ctx.badDebt;

        // 8. Emit events
        _emitLiquidationEvent(positionId, pos, liquidator, ctx);

        if (ctx.badDebt > 0) {
            emit BadDebtRecorded(
                pos.marketId, positionId, ctx.badDebt, ctx.insurancePaid, ctx.socializedAmount,
                block.timestamp
            );
        }

        if (ctx.isPartial) {
            emit PartialLiquidation(positionId, pos.positionSize, 0, block.timestamp);
        }

        // 9. Build result
        result.positionId = positionId;
        result.liquidationFee = ctx.fee;
        result.remainingEquity = ctx.equity - int256(ctx.fee);
        result.badDebt = ctx.badDebt;
        result.insurancePaid = ctx.insurancePaid;
        result.adlAmount = ctx.socializedAmount;
        result.isPartial = ctx.isPartial;
    }

    /// @dev Compute liquidation fee (1% of notional, capped at equity) and determine outcomes
    function _computeFeeAndOutcome(LiqContext memory ctx, uint256 positionSize) internal pure {
        uint256 feeCalculated = positionSize.wadMul(LIQUIDATION_FEE_RATE);

        if (ctx.equity > 0) {
            ctx.fee = feeCalculated < uint256(ctx.equity) ? feeCalculated : uint256(ctx.equity);
        }

        int256 remainingEquity = ctx.equity - int256(ctx.fee);

        if (remainingEquity > 0) {
            ctx.traderReceives = uint256(remainingEquity);
        } else if (remainingEquity < 0) {
            ctx.badDebt = uint256(-remainingEquity);
        }
    }

    /// @dev Close position in all downstream contracts
    function _closeAndSettle(
        IPositionManager.Position memory pos,
        uint256 positionId,
        uint256 traderReceives
    ) internal {
        oiLimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize);
        positionManager.closePosition(positionId);
        accountManager.releaseCollateral(pos.owner, pos.collateral);

        if (traderReceives > 0) {
            accountManager.creditPnL(pos.owner, traderReceives);
        }
    }

    /// @dev Route liquidation fee: bounty to external liquidator (Path C), rest through FeeRouter
    function _routeFee(uint256 fee, address liquidator) internal {
        if (fee == 0) return;

        if (liquidator != address(0)) {
            uint256 bounty = fee.wadMul(LIQUIDATOR_BOUNTY_SHARE);
            uint256 feeForProtocol = fee - bounty;
            if (bounty > 0) {
                accountManager.creditPnL(liquidator, bounty);
            }
            if (feeForProtocol > 0) {
                feeRouter.routeFees(IFeeRouter.FeeType.LIQUIDATION, feeForProtocol);
            }
        } else {
            feeRouter.routeFees(IFeeRouter.FeeType.LIQUIDATION, fee);
        }
    }

    /// @dev Handle bad debt: insurance absorbs first, remainder socialized to LP pool
    function _handleBadDebt(bytes32 marketId, uint256, uint256 badDebt)
        internal
        returns (uint256 insurancePaid, uint256 socializedAmount)
    {
        (insurancePaid, socializedAmount) = insuranceFund.absorbBadDebt(marketId, badDebt);

        if (socializedAmount > 0) {
            leverVault.socializeLoss(socializedAmount);
        }
    }

    /// @dev Emit PositionLiquidated event (extracted to avoid stack-too-deep)
    function _emitLiquidationEvent(
        uint256 positionId,
        IPositionManager.Position memory pos,
        address liquidator,
        LiqContext memory ctx
    ) internal {
        emit PositionLiquidated(
            positionId, pos.marketId, pos.owner, liquidator, ctx.equity, ctx.mm, ctx.fee,
            ctx.badDebt, block.timestamp
        );
    }
}
