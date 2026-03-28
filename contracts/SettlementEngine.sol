// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { ISettlementEngine } from "./interfaces/ISettlementEngine.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";
import { IOracleAdapter } from "./interfaces/IOracleAdapter.sol";
import { IBorrowFeeEngine } from "./interfaces/IBorrowFeeEngine.sol";
import { IFundingRateEngine } from "./interfaces/IFundingRateEngine.sol";
import { IInsuranceFund } from "./interfaces/IInsuranceFund.sol";
import { IFeeRouter } from "./interfaces/IFeeRouter.sol";
import { IOILimits } from "./interfaces/IOILimits.sol";
import { IAccountManager } from "./interfaces/IAccountManager.sol";
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// 2. Custom Errors (beyond interface)
// 3. Events (defined in ISettlementEngine)

/// @title SettlementEngine
/// @notice Binary event resolution. PI snaps to 0 or 1. Computes settlement payouts.
///         Handles bad debt via four-layer waterfall: position equity → insurance →
///         ADL (pro-rata winner haircut) → LP socialization. Void handling: all
///         positions refund at current equity, no settlement fee.
contract SettlementEngine is ISettlementEngine, AccessControl, ReentrancyGuard, Pausable {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;

    /// @notice Settlement fee: 0.20% (20 bps) of notional (winners only)
    uint256 public constant SETTLEMENT_FEE_RATE = 2e15;

    /// @notice 2× MM multiplier during PENDING_RESOLUTION state
    uint256 public constant PENDING_RESOLUTION_MM_MULT = 2e18;

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ──────────────────────────────────────────────
    // Additional Errors
    // ──────────────────────────────────────────────

    error SettlementEngine__ZeroAddress();
    error SettlementEngine__MarketAlreadySettled(bytes32 marketId);
    error SettlementEngine__MarketNotVoided(bytes32 marketId);
    error SettlementEngine__MarketNotSettled(bytes32 marketId);

    // ──────────────────────────────────────────────
    // Type Declarations
    // ──────────────────────────────────────────────

    struct MarketSettlementState {
        bool settled;
        uint8 outcome;
        uint256 totalBadDebt;
        uint256 insuranceUsed;
        uint256 adlRemainder;
        uint256 adlHaircut;          // WAD — percentage haircut on winners
        uint256 totalWinnerPayout;   // pre-haircut aggregate
        uint256 feesCollected;
        uint256 finalBorrowIndexLong;
        uint256 finalBorrowIndexShort;
        int256 finalFundingIndex;
        uint256 totalPositions;
        uint256 winnerCount;
        uint256 loserCount;
    }

    /// @dev Intermediate struct to avoid stack-too-deep in per-position calc
    struct SettleContext {
        uint256 piOutcome;
        int256 outcomePnL;
        uint256 borrowFees;
        int256 funding;
        int256 equity;
        bool isWinner;
        uint256 settlementFee;
        uint256 payout;
        uint256 badDebt;
    }

    /// @dev Aggregate totals from first pass (avoids stack-too-deep in settleMarket)
    struct FirstPassResult {
        uint256 totalWinnerPayout;
        uint256 totalLoserDebt;   // FIX LEVER-014: Track total loser debt separately
        uint256 totalBadDebt;
        uint256 totalFees;
        uint256 winnerCount;
        uint256 loserCount;
        uint256 totalPositions;
    }

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    IMarketRegistry public immutable marketRegistry;
    IPositionManager public immutable positionManager;
    IOracleAdapter public immutable oracleAdapter;
    IBorrowFeeEngine public immutable borrowFeeEngine;
    IFundingRateEngine public immutable fundingRateEngine;
    IInsuranceFund public immutable insuranceFund;
    IFeeRouter public immutable feeRouter;
    IOILimits public immutable oiLimits;
    IAccountManager public immutable accountManager;
    ILeverVault public immutable leverVault;

    // ──────────────────────────────────────────────
    // State Variables
    // ──────────────────────────────────────────────

    mapping(bytes32 => MarketSettlementState) private _marketSettlements;
    mapping(uint256 => bool) private _positionSettled;

    /// @dev Stores per-position settlement results computed during settleMarket first pass
    mapping(uint256 => SettlementResult) private _positionResults;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    constructor(
        address admin_,
        address marketRegistry_,
        address positionManager_,
        address oracleAdapter_,
        address borrowFeeEngine_,
        address fundingRateEngine_,
        address insuranceFund_,
        address feeRouter_,
        address oiLimits_,
        address accountManager_,
        address leverVault_
    ) {
        if (admin_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (marketRegistry_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (positionManager_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (oracleAdapter_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (borrowFeeEngine_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (fundingRateEngine_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (insuranceFund_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (feeRouter_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (oiLimits_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (accountManager_ == address(0)) revert SettlementEngine__ZeroAddress();
        if (leverVault_ == address(0)) revert SettlementEngine__ZeroAddress();

        marketRegistry = IMarketRegistry(marketRegistry_);
        positionManager = IPositionManager(positionManager_);
        oracleAdapter = IOracleAdapter(oracleAdapter_);
        borrowFeeEngine = IBorrowFeeEngine(borrowFeeEngine_);
        fundingRateEngine = IFundingRateEngine(fundingRateEngine_);
        insuranceFund = IInsuranceFund(insuranceFund_);
        feeRouter = IFeeRouter(feeRouter_);
        oiLimits = IOILimits(oiLimits_);
        accountManager = IAccountManager(accountManager_);
        leverVault = ILeverVault(leverVault_);

        _grantRole(ADMIN_ROLE, admin_);
    }

    // ──────────────────────────────────────────────
    // External — State Changing
    // ──────────────────────────────────────────────

    /// @inheritdoc ISettlementEngine
    function settleMarket(bytes32 marketId)
        external
        override
        onlyRole(KEEPER_ROLE)
        nonReentrant
        whenNotPaused
    {
        IMarketRegistry.Market memory market = marketRegistry.getMarket(marketId);
        if (market.state != IMarketRegistry.MarketState.RESOLVED) {
            revert SettlementEngine__MarketNotResolved(marketId);
        }
        if (_marketSettlements[marketId].settled) {
            revert SettlementEngine__MarketAlreadySettled(marketId);
        }

        uint8 outcome = market.outcome;
        if (outcome > 1) revert SettlementEngine__InvalidOutcome(outcome);

        uint256 piOutcome = outcome == 1 ? WAD : 0;

        // Snap PI to outcome
        oracleAdapter.snapToOutcome(marketId, piOutcome);

        // Freeze fee indices at external resolution timestamp
        _freezeIndices(marketId, outcome, market.externalResolutionTime);

        // First pass: compute all payouts and identify bad debt
        FirstPassResult memory fp = _firstPass(marketId, piOutcome);

        // Second pass: handle bad debt waterfall
        _handleBadDebtWaterfall(marketId, fp.totalBadDebt, fp.totalWinnerPayout);

        // Finalize state
        MarketSettlementState storage state = _marketSettlements[marketId];
        state.settled = true;
        state.feesCollected = fp.totalFees;
        state.totalPositions = fp.totalPositions;
        state.winnerCount = fp.winnerCount;
        state.loserCount = fp.loserCount;

        // FIX LEVER-014: Use correct totalLoserDebt field instead of duplicating totalBadDebt
        emit MarketSettled(
            marketId, outcome, fp.totalWinnerPayout, fp.totalLoserDebt,
            fp.totalBadDebt, fp.totalFees, block.timestamp
        );

        if (state.adlRemainder > 0) {
            uint256 haircutBps = state.adlHaircut * 10_000 / WAD;
            emit ADLApplied(
                marketId, fp.totalBadDebt, state.insuranceUsed,
                state.adlRemainder, haircutBps, block.timestamp
            );
        }
    }

    /// @inheritdoc ISettlementEngine
    function claimSettlement(uint256 positionId)
        external
        override
        nonReentrant
        whenNotPaused
        returns (SettlementResult memory result)
    {
        if (_positionSettled[positionId]) {
            revert SettlementEngine__PositionAlreadySettled(positionId);
        }

        IPositionManager.Position memory pos = positionManager.getPosition(positionId);
        MarketSettlementState storage state = _marketSettlements[pos.marketId];
        if (!state.settled) {
            revert SettlementEngine__MarketNotSettled(pos.marketId);
        }

        result = _positionResults[positionId];

        // Apply ADL haircut to winners
        if (result.isWinner && state.adlHaircut > 0) {
            result.payout = result.payout.wadMul(WAD - state.adlHaircut);
        }

        _positionSettled[positionId] = true;

        // Execute: decrease OI, close position, release collateral, credit payout
        oiLimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize);
        positionManager.closePosition(positionId);
        accountManager.releaseCollateral(pos.owner, pos.collateral);

        if (result.payout > 0) {
            accountManager.creditPnL(pos.owner, result.payout);
        }

        // FIX LEVER-005: Transfer USDT to FeeRouter before calling routeFees
        if (result.settlementFee > 0) {
            accountManager.transferOut(address(feeRouter), result.settlementFee);
            feeRouter.routeFees(IFeeRouter.FeeType.SETTLEMENT, result.settlementFee);
        }

        emit PositionSettled(
            positionId, pos.marketId, pos.owner, result.isWinner,
            result.outcomePnL, result.settlementFee, result.payout, block.timestamp
        );
    }

    /// @inheritdoc ISettlementEngine
    function settleVoid(bytes32 marketId)
        external
        override
        onlyRole(KEEPER_ROLE)
        nonReentrant
        whenNotPaused
    {
        IMarketRegistry.Market memory market = marketRegistry.getMarket(marketId);
        if (market.state != IMarketRegistry.MarketState.VOIDED) {
            revert SettlementEngine__MarketNotVoided(marketId);
        }
        if (_marketSettlements[marketId].settled) {
            revert SettlementEngine__MarketAlreadySettled(marketId);
        }

        // Freeze fee indices
        uint256 freezeTime = market.externalResolutionTime > 0
            ? market.externalResolutionTime
            : block.timestamp;
        _freezeIndices(marketId, 2, freezeTime);

        uint256[] memory positionIds = positionManager.getMarketPositions(marketId);
        uint256 totalRefunded;
        uint256 positionsRefunded;

        MarketSettlementState storage state = _marketSettlements[marketId];

        for (uint256 i; i < positionIds.length; ++i) {
            uint256 posId = positionIds[i];
            if (!positionManager.isPositionOpen(posId)) continue;

            IPositionManager.Position memory pos = positionManager.getPosition(posId);
            uint256 payout = _processVoidPosition(pos, state);

            _positionSettled[posId] = true;
            oiLimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize);
            positionManager.closePosition(posId);
            accountManager.releaseCollateral(pos.owner, pos.collateral);

            if (payout > 0) {
                accountManager.creditPnL(pos.owner, payout);
                totalRefunded += payout;
            }

            ++positionsRefunded;
        }

        state.settled = true;
        state.outcome = 2;
        state.totalPositions = positionIds.length;

        emit VoidSettlement(marketId, positionsRefunded, totalRefunded, block.timestamp);
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

    /// @inheritdoc ISettlementEngine
    function previewSettlement(uint256 positionId)
        external
        view
        override
        returns (SettlementResult memory result)
    {
        bytes32 mktId = positionManager.getPosition(positionId).marketId;
        MarketSettlementState storage state = _marketSettlements[mktId];
        if (!state.settled) revert SettlementEngine__MarketNotSettled(mktId);

        result = _positionResults[positionId];
        if (result.isWinner && state.adlHaircut > 0) {
            result.payout = result.payout.wadMul(WAD - state.adlHaircut);
        }
    }

    /// @inheritdoc ISettlementEngine
    function getMarketSettlement(bytes32 marketId)
        external
        view
        override
        returns (MarketSettlementSummary memory summary)
    {
        MarketSettlementState storage state = _marketSettlements[marketId];
        summary = MarketSettlementSummary({
            marketId: marketId,
            outcome: state.outcome,
            totalPositions: state.totalPositions,
            winnerCount: state.winnerCount,
            loserCount: state.loserCount,
            totalWinnerPayout: state.totalWinnerPayout,
            totalBadDebt: state.totalBadDebt,
            insuranceUsed: state.insuranceUsed,
            adlApplied: state.adlRemainder,
            feesCollected: state.feesCollected
        });
    }

    /// @inheritdoc ISettlementEngine
    function isSettled(uint256 positionId) external view override returns (bool) {
        return _positionSettled[positionId];
    }

    /// @inheritdoc ISettlementEngine
    function getUnsettledPositions(bytes32 marketId)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256[] memory allPositions = positionManager.getMarketPositions(marketId);
        uint256 count;
        for (uint256 i; i < allPositions.length; ++i) {
            if (!_positionSettled[allPositions[i]] && positionManager.isPositionOpen(allPositions[i])) {
                ++count;
            }
        }

        uint256[] memory unsettled = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < allPositions.length; ++i) {
            if (!_positionSettled[allPositions[i]] && positionManager.isPositionOpen(allPositions[i])) {
                unsettled[idx++] = allPositions[i];
            }
        }
        return unsettled;
    }

    /// @inheritdoc ISettlementEngine
    function getADLHaircut(bytes32 marketId) external view override returns (uint256) {
        return _marketSettlements[marketId].adlHaircut;
    }

    /// @inheritdoc ISettlementEngine
    function isFullySettled(bytes32 marketId) external view override returns (bool) {
        MarketSettlementState storage state = _marketSettlements[marketId];
        if (!state.settled) return false;

        uint256[] memory allPositions = positionManager.getMarketPositions(marketId);
        for (uint256 i; i < allPositions.length; ++i) {
            if (!_positionSettled[allPositions[i]]) return false;
        }
        return true;
    }

    // ──────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────

    /// @dev Freeze borrow and funding indices at the external resolution timestamp
    function _freezeIndices(bytes32 marketId, uint8 outcome, uint256 externalTime) internal {
        MarketSettlementState storage state = _marketSettlements[marketId];
        state.outcome = outcome;
        state.finalBorrowIndexLong = borrowFeeEngine.computeIndexAt(marketId, true, externalTime);
        state.finalBorrowIndexShort = borrowFeeEngine.computeIndexAt(marketId, false, externalTime);
        state.finalFundingIndex = fundingRateEngine.computeIndexAt(marketId, externalTime);
    }

    /// @dev First pass: iterate all positions, compute payouts, store results, aggregate totals
    function _firstPass(bytes32 marketId, uint256 piOutcome)
        internal
        returns (FirstPassResult memory fp)
    {
        MarketSettlementState storage state = _marketSettlements[marketId];
        uint256[] memory positionIds = positionManager.getMarketPositions(marketId);
        fp.totalPositions = positionIds.length;

        for (uint256 i; i < positionIds.length; ++i) {
            uint256 posId = positionIds[i];
            if (!positionManager.isPositionOpen(posId)) continue;

            IPositionManager.Position memory pos = positionManager.getPosition(posId);
            SettleContext memory ctx = _computePositionSettlement(pos, state, piOutcome);

            _positionResults[posId] = SettlementResult({
                positionId: posId,
                isWinner: ctx.isWinner,
                outcomePnL: ctx.outcomePnL,
                finalEquity: ctx.equity,
                settlementFee: ctx.settlementFee,
                payout: ctx.payout,
                badDebt: ctx.badDebt
            });

            if (ctx.isWinner) {
                fp.totalWinnerPayout += ctx.payout;
                fp.totalFees += ctx.settlementFee;
                ++fp.winnerCount;
            } else {
                fp.totalLoserDebt += pos.collateral;   // FIX LEVER-014
                fp.totalBadDebt += ctx.badDebt;
                ++fp.loserCount;
            }
        }
    }

    /// @dev Second pass: insurance → ADL → LP socialization
    function _handleBadDebtWaterfall(
        bytes32 marketId,
        uint256 totalBadDebt,
        uint256 totalWinnerPayout
    ) internal {
        if (totalBadDebt == 0) return;

        MarketSettlementState storage state = _marketSettlements[marketId];

        // FIX LEVER-P04: Pass leverVault as recipient so insurance USDT goes to vault, not this contract
        (uint256 insurancePaid, uint256 remainder) = insuranceFund.absorbBadDebt(marketId, totalBadDebt, address(leverVault));

        state.totalBadDebt = totalBadDebt;
        state.insuranceUsed = insurancePaid;
        state.totalWinnerPayout = totalWinnerPayout;

        if (remainder == 0) return;

        state.adlRemainder = remainder;

        if (totalWinnerPayout > 0) {
            uint256 haircut = remainder.wadDiv(totalWinnerPayout);
            if (haircut > WAD) {
                haircut = WAD;
                leverVault.socializeLoss(remainder - totalWinnerPayout);
            }
            state.adlHaircut = haircut;
        } else {
            // No winners to haircut — all remainder goes to LP socialization
            leverVault.socializeLoss(remainder);
        }
    }

    /// @dev Compute settlement result for a single position
    function _computePositionSettlement(
        IPositionManager.Position memory pos,
        MarketSettlementState storage state,
        uint256 piOutcome
    ) internal view returns (SettleContext memory ctx) {
        ctx.isWinner = (pos.isLong && state.outcome == 1) || (!pos.isLong && state.outcome == 0);

        // PnL = direction × (piOutcome - entryPI) × positionSize / WAD
        int256 piDiff = int256(piOutcome) - int256(pos.entryPI);
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        ctx.outcomePnL = direction * piDiff * int256(pos.positionSize) / int256(WAD);

        ctx.borrowFees = _computeBorrowFees(pos, state);
        ctx.funding = _computeFunding(pos, state);

        // equity = collateral + PnL - borrowFees + funding
        ctx.equity = int256(pos.collateral) + ctx.outcomePnL - int256(ctx.borrowFees) + ctx.funding;

        if (ctx.isWinner) {
            ctx.settlementFee = pos.positionSize.wadMul(SETTLEMENT_FEE_RATE);
            int256 payoutSigned = ctx.equity - int256(ctx.settlementFee);
            if (payoutSigned <= 0) {
                ctx.settlementFee = ctx.equity > 0 ? uint256(ctx.equity) : 0;
                ctx.payout = 0;
            } else {
                ctx.payout = uint256(payoutSigned);
            }
        } else {
            if (ctx.equity > 0) {
                ctx.payout = uint256(ctx.equity);
            } else if (ctx.equity < 0) {
                ctx.badDebt = uint256(-ctx.equity);
            }
        }
    }

    /// @dev Compute borrow fees for a position using frozen indices
    function _computeBorrowFees(
        IPositionManager.Position memory pos,
        MarketSettlementState storage state
    ) internal view returns (uint256 fees) {
        uint256 finalIndex = pos.isLong
            ? state.finalBorrowIndexLong
            : state.finalBorrowIndexShort;
        if (finalIndex <= pos.borrowIndex) return 0;
        fees = pos.positionSize.wadMul(finalIndex - pos.borrowIndex);
    }

    /// @dev Compute funding for a position using frozen index
    function _computeFunding(
        IPositionManager.Position memory pos,
        MarketSettlementState storage state
    ) internal view returns (int256 funding) {
        int256 indexDelta = state.finalFundingIndex - pos.fundingIndex;
        int256 direction = pos.isLong ? int256(1) : int256(-1);
        funding = -direction * int256(pos.positionSize) * indexDelta / int256(WAD);
    }

    /// @dev Process a single void position — returns payout and stores result
    function _processVoidPosition(
        IPositionManager.Position memory pos,
        MarketSettlementState storage state
    ) internal returns (uint256 payout) {
        uint256 borrowFees = _computeBorrowFees(pos, state);
        int256 funding = _computeFunding(pos, state);

        int256 equity = int256(pos.collateral) - int256(borrowFees) + funding;
        payout = equity > 0 ? uint256(equity) : 0;

        _positionResults[pos.id] = SettlementResult({
            positionId: pos.id,
            isWinner: false,
            outcomePnL: 0,
            finalEquity: equity,
            settlementFee: 0,
            payout: payout,
            badDebt: equity < 0 ? uint256(-equity) : 0
        });
    }
}
