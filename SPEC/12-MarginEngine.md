# SPEC: MarginEngine

## Purpose
Defines IM (initial margin), MM (maintenance margin), and real-time equity for every position. Creates the pincer effect: rising MM squeezes from below while escalating borrow fees erode equity from above. All view functions — no state of its own. Reads from PositionManager, BorrowFeeEngine, FundingRateEngine, OracleAdapter.

## Dependencies
- IOracleAdapter (PI)
- IPositionManager (position data)
- IBorrowFeeEngine (accrued borrow fees)
- IFundingRateEngine (accrued funding)
- ILeverageModel (max leverage for validation)
- RiskCurves (R_adjusted for MM/IM multipliers)
- IMarketRegistry (τ, is_live)
- IOILimits (market utilization for IM adjustment)
- FixedPointMath

## Build Priority
Phase 5 — Margin & Execution. LiquidationEngine and ExecutionEngine depend on this.

## Access Control
- All functions are view/pure. No state, no access control.

## Constants
```solidity
uint256 constant BASE_MM_RATE = 25e15;      // 2.5% = 0.025
uint256 constant MM_MULT_MAX = 3e18;        // 3.0×
uint256 constant IM_MULT_MAX = 3e18;        // 3.0×
uint256 constant VOL_SENSITIVITY = 5e17;    // 0.5 (α_IM)
uint256 constant UTIL_SENSITIVITY = 1e18;   // 1.0 (β)
uint256 constant UTIL_THRESHOLD_IM = 5e17;  // 50%
uint256 constant LIQUIDATION_BUFFER = 5e15; // 0.5% = 0.005
uint256 constant WITHDRAWAL_BUFFER = 2e16;  // 2.0% = 0.02
```

## Core Equation: Equity
```
Equity = Collateral + PnL(PI) - Accrued_Borrow_Fees + Accrued_Funding

Where:
  PnL = ProbabilityIndex.computePnL(pos.entryPI, currentPI, pos.positionSize, pos.isLong)
  Accrued_Borrow = BorrowFeeEngine.getAccruedFees(positionId)   // uint256, always positive
  Accrued_Funding = FundingRateEngine.getAccruedFunding(positionId)  // int256: + = received, - = paid

Equity = int256(pos.collateral) + pnl - int256(borrowFees) + accruedFunding
```

## Maintenance Margin
```
R_adjusted = ... (from RiskCurves for this market)
mmMult = RiskCurves.mmMultiplier(R_adjusted)    // 3.0 - R × 2.0, range [1.0, 3.0]
MM = BASE_MM_RATE × pos.positionSize / WAD × mmMult / WAD
```

## Initial Margin
```
IM_base = pos.positionSize / leverage_requested    // = collateral at exact leverage

imMult = RiskCurves.imMultiplier(R_adjusted)       // 3.0 - R × 2.0

// Adjustments (additive, can only increase):
vol_adj = VOL_SENSITIVITY × max(0, sigma_current - sigma_baseline) / WAD
util_adj = UTIL_SENSITIVITY × max(0, market_utilization - UTIL_THRESHOLD_IM) / WAD

IM = IM_base × imMult / WAD × (WAD + vol_adj + util_adj) / WAD
```

## Liquidation Check
```
isLiquidatable = Equity < MM + LIQUIDATION_BUFFER × pos.positionSize / WAD
```
The buffer prevents oscillation around the threshold.

## Danger Zone Check
```
isInDangerZone = Equity < 2 × (MM + LIQUIDATION_BUFFER × pos.positionSize / WAD)
```
Position is within 2× of liquidation. Used for UI warnings.

## 10-Step Margin Check (for new positions — see WP Section 11.6)
```
1. leverage_requested ≤ LeverageModel.getEffectiveMaxLeverage(marketId)
2. notional = collateral × leverage
3. OILimits.canIncreaseOI(marketId, user, isLong, notional) == true
4. Compute entry_price via ExecutionEngine.previewExecution(...)
5. Compute IM_final with all adjustments
6. collateral ≥ IM_final
7. collateral_net = collateral - txFee; collateral_net ≥ IM_final
8. collateral_net > MM
9. MR = collateral_net / notional; MR > (MM/notional) + LIQUIDATION_BUFFER + margin
10. All pass → return (true, 0)
```
Return failed check index on failure.

## Collateral Removal Check
```
After removal:
  newEquity = Equity with (collateral - amount)
  newMR = newEquity / positionSize
  Required: newMR ≥ (MM / positionSize) + WITHDRAWAL_BUFFER
```

## Edge Cases
- Equity negative → still computable (int256). isLiquidatable = true. Used for bad debt calculation.
- PI at exactly 0 or WAD (settlement) → large PnL swings. Equity may be very negative.
- BorrowFees exceeding collateral + PnL → equity negative even if PnL is positive. The ticking clock at work.
- Funding received by light side → increases equity (delays liquidation).
- Position with very high MM near resolution (3× multiplier) and simultaneous fee erosion → the pincer.
- MM for a market in PENDING_RESOLUTION: use 2× multiplier (WP Section 18.3).

