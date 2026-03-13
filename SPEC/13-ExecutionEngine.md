# SPEC: ExecutionEngine

## Purpose
Orchestrates position opens/closes. Computes entry/exit prices via PI + imbalance-adjusted linear impact using imbalance_delta. Delegates storage to PositionManager, margin checks to MarginEngine, OI tracking to OILimits, collateral to AccountManager. This is the "router" — it coordinates but relies on specialized contracts for each concern.

## Dependencies
- IOracleAdapter (PI)
- IPositionManager (create/close positions)
- IAccountManager (lock/release collateral, credit/debit PnL)
- IMarginEngine (validate margin checks, compute equity)
- IOILimits (increase/decrease OI, get imbalance data)
- ILeverageModel (validate leverage)
- IBorrowFeeEngine (get accrued fees on close, get borrow index snapshot)
- IFundingRateEngine (get accrued funding on close, get funding index snapshot)
- IFeeRouter (collect TX fees)
- RiskCurves (Execution_Depth_Mult)
- IMarketRegistry (market state checks)
- FixedPointMath

## Build Priority
Phase 5 — Margin & Execution.

## Access Control
- Any user: openPosition, closePosition, addCollateral, removeCollateral (on own positions)
- LIQUIDATION_ENGINE role: forceClose (internal, called during liquidation)
- SETTLEMENT_ENGINE role: forceClose (internal, called during settlement)

## Constants
```solidity
uint256 constant IMBALANCE_MULTIPLIER = 2e18;  // 2.0
uint256 constant MAX_IMPACT = 5e16;             // 5% = 0.05
```

## Impact Model (WP Section 10.2)

### computeMarketDepth(bytes32 marketId) → uint256
```
marketOICap = OILimits.getMarketOICap(marketId)
tauEff = RiskCurves.computeTauEffective(...)
r = RiskCurves.computeR(tauEff)
mMarket = RiskCurves.computeMarketAdjustment(...)
rAdj = r × mMarket / WAD
depthMult = RiskCurves.executionDepthMultiplier(rAdj)  // 0.30 + R × 0.70
return marketOICap × depthMult / WAD
```

### computeBaseImpact(bytes32 marketId, uint256 tradeSize) → uint256
```
depth = computeMarketDepth(marketId)
if depth == 0: revert (market has no depth)
return tradeSize × WAD / (depth × 2)
```

### computeImbalanceDelta(bytes32 marketId, bool isLong, uint256 notional) → int256
```
longOI = OILimits.getSideOI(marketId, true)
shortOI = OILimits.getSideOI(marketId, false)
totalOI = longOI + shortOI

// Handle zero OI edge case
if totalOI == 0:
  return 0   // first trade has no imbalance effect

// Before trade
imbalanceBefore = abs(int256(longOI) - int256(shortOI)) × WAD / totalOI

// After trade
if isLong:
  longOI_after = longOI + notional
else:
  shortOI_after = shortOI + notional
totalOI_after = totalOI + notional
imbalanceAfter = abs(int256(longOI_after) - int256(shortOI_after)) × WAD / totalOI_after

// Delta (signed)
return int256(imbalanceAfter) - int256(imbalanceBefore)
// Positive = worsens. Negative = improves.
```

### computeImpact(bytes32 marketId, bool isLong, uint256 notional) → uint256
```
baseImpact = computeBaseImpact(marketId, notional)
delta = computeImbalanceDelta(marketId, isLong, notional)

// impact = base × (1 + delta × multiplier)
adjustment = delta × int256(IMBALANCE_MULTIPLIER) / int256(WAD)
impactRaw = int256(baseImpact) × (int256(WAD) + adjustment) / int256(WAD)

// Floor at 0 (impact cannot be negative — that would mean trader gets paid to trade)
impact = impactRaw < 0 ? 0 : uint256(impactRaw)

// Cap at MAX_IMPACT
impact = min(impact, MAX_IMPACT)
return impact
```

### computeEntryPrice(bytes32 marketId, bool isLong, uint256 notional) → uint256
```
pi = OracleAdapter.getPI(marketId)
impact = computeImpact(marketId, isLong, notional)
if isLong:
  return pi × (WAD + impact) / WAD    // pay above PI
else:
  return pi × (WAD - impact) / WAD    // pay below PI
```

### computeExitPrice(bytes32 marketId, bool isLong, uint256 notional) → uint256
```
// Closing is reverse direction
pi = OracleAdapter.getPI(marketId)
// For closing, recompute delta with the OI DECREASE
// (closing a long = reducing longOI, which usually improves balance)
impact = computeImpactForClose(marketId, isLong, notional)
if isLong:
  return pi × (WAD - impact) / WAD    // receive below PI
else:
  return pi × (WAD + impact) / WAD    // receive above PI
```

## openPosition(OpenParams params) → uint256 positionId

Full sequence:
```
1. MarketRegistry.getMarketState(marketId) == ACTIVE
2. !OracleAdapter.isFrozen(marketId) && !OracleAdapter.isStale(marketId)
3. LeverageModel.validateLeverage(marketId, leverage)
4. notional = collateral × leverage / WAD
5. OILimits.canIncreaseOI(marketId, msg.sender, isLong, notional)
6. entryPrice = computeEntryPrice(marketId, isLong, notional)
7. pi = OracleAdapter.getPI(marketId)
8. txFee = FeeRouter.collectTransactionFee(notional)
9. collateralNet = collateral - txFee
10. MarginEngine.validateMarginChecks(marketId, msg.sender, isLong, collateralNet, leverage) → must pass
11. AccountManager.lockCollateral(msg.sender, collateral)    // lock FULL amount including fee
12. borrowIndex = BorrowFeeEngine.getBorrowIndex(marketId, isLong)
13. fundingIndex = FundingRateEngine.getFundingIndex(marketId)   // single index, no isLong
14. positionId = PositionManager.createPosition(
      msg.sender, marketId, isLong, pi, entryPrice, notional,
      collateralNet, leverage, borrowIndex, fundingIndex
    )
15. OILimits.increaseOI(marketId, msg.sender, isLong, notional)
16. emit PositionOpened(...)
```

## closePosition(uint256 positionId)
```
1. pos = PositionManager.getPosition(positionId)
2. require pos.owner == msg.sender && pos.isOpen
3. require MarketRegistry.getMarketState(pos.marketId) == ACTIVE  // no close during PENDING_RESOLUTION
4. exitPrice = computeExitPrice(pos.marketId, pos.isLong, pos.positionSize)
5. equity = MarginEngine.computeEquity(positionId)
6. txFee = FeeRouter.collectTransactionFee(pos.positionSize)
7. payout = max(0, equity.equity - int256(txFee))
8. OILimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize)
9. PositionManager.closePosition(positionId)
10. AccountManager.releaseCollateral(pos.owner, pos.collateral)
11. if payout > 0: AccountManager.creditPnL(pos.owner, uint256(payout))
    if payout <= 0: AccountManager.debitPnL(pos.owner, uint256(-equity.equity))
12. emit PositionClosed(...)
```

## Edge Cases
- First trade on empty market: totalOI = 0 → imbalance_delta = 0 → standard impact
- Market depth = 0 (cap compressed to zero) → revert, cannot trade
- Impact > 5% → capped at 5%. Trade still executes, just at worst-case price.
- PI = 0 or PI = WAD → entry_price works fine (impact is PI-independent percentage-wise, but the dollar price changes). PI = 0 means entry_price for long = 0 × (1 + impact) = 0. This is a settled market — should be blocked by state check.
- Close during PENDING_RESOLUTION → blocked (WP Section 18.3)
- Position with negative equity on close → payout = 0, loss is the collateral. Bad debt handled by liquidation path, not voluntary close (if equity < MM, should have been liquidated first).

