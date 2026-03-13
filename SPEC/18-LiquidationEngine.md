# SPEC: LiquidationEngine

## Purpose
Force-closes positions when equity falls below maintenance margin. Three execution paths: self-liquidation on user interaction (Path A), protocol-triggered on oracle update (Path B), permissionless external (Path C). Liquidations close through the standard execution model (with impact). Handles bad debt via insurance → LP socialization waterfall. Continues during PENDING_RESOLUTION with 2× MM.

**CRITICAL DISTINCTION:** During normal liquidation, bad debt after insurance goes to **LP socialization** (direct NAV hit). ADL (winner haircuts) ONLY exists during settlement (see SettlementEngine spec). There are no "winners" to haircut during normal operation.

## Dependencies
- IMarginEngine (equity, MM, isLiquidatable)
- IPositionManager (close positions)
- IExecutionEngine (compute exit price with impact — liquidation uses standard execution)
- IOracleAdapter (PI)
- IOILimits (decrease OI)
- IAccountManager (release collateral, settle PnL)
- IBorrowFeeEngine (accrued fees)
- IFundingRateEngine (accrued funding)
- IInsuranceFund (absorb bad debt)
- IFeeRouter (route liquidation fees)
- IMarketRegistry (market state)
- FixedPointMath

## Build Priority
Phase 7 — Terminal Contracts.

## Access Control
- Any address: liquidate, batchLiquidate (permissionless — Path C)
- Internal (called by protocol): _checkAndLiquidate (Paths A & B)
- All view functions: public

## Constants
```solidity
uint256 constant LIQUIDATION_FEE_RATE = 1e16;       // 1.0% (100 bps) of notional (WP 13.5)
uint256 constant LIQUIDATOR_BOUNTY_SHARE = 1e17;     // 10% of liquidation fee to external caller
uint256 constant PARTIAL_LIQ_THRESHOLD = 1e17;       // 10% of market depth
uint256 constant PARTIAL_LIQ_CHUNK = 5e16;           // 5% of market depth per chunk
```

## Three-Path Liquidation Model (WP Section 13.2)

### Path A: Self-Liquidation on User Interaction (Primary)
Every state-changing function that touches a position checks liquidation FIRST:
```
function closePosition(positionId) {
    if (isLiquidatable(positionId)) {
        _liquidate(positionId, address(0));  // no bounty (internal)
        return;
    }
    // ... normal close logic
}
```
Applies to: closePosition, addCollateral, removeCollateral, increaseSize.
A user CANNOT interact with an underwater position without triggering liquidation.

### Path B: Protocol-Triggered on Oracle Update (Secondary)
On every PI update, check affected positions:
```
function onPriceUpdate(bytes32 marketId) internal {
    // Called by OracleAdapter after PI update
    uint256[] positions = PositionManager.getMarketPositions(marketId);
    for each positionId:
        if isLiquidatable(positionId):
            _liquidate(positionId, address(0));  // no bounty
}
```
- Atomic with oracle update — no latency between price change and liquidation
- Gas-bounded: if too many, process in priority order (highest leverage first) and emit LiquidationBatchIncomplete for keepers to handle remainder
- Also triggered by: funding index update, borrow index update, R(τ) recalculation

### Path C: Permissionless External Liquidation (Accelerator)
```
function liquidate(uint256 positionId) external {
    require isLiquidatable(positionId);
    _liquidate(positionId, msg.sender);  // bounty to caller
}
```
External liquidators earn 10% of the liquidation fee as a bounty.
LP safety does NOT depend on Path C — Paths A and B provide full coverage.

## _liquidate(uint256 positionId, address liquidator) — Core Logic

```
1. pos = PositionManager.getPosition(positionId)
   require pos.isOpen

2. market = MarketRegistry.getMarket(pos.marketId)
   require market.state == ACTIVE || market.state == PENDING_RESOLUTION
   // Liquidations CONTINUE during PENDING_RESOLUTION (WP 18.3)
   // Liquidations STOP after RESOLVED (settlement handles those)

3. // LIQUIDATION CLOSES THROUGH THE STANDARD EXECUTION MODEL (WP 13.4)
   // The position is closed at the current execution price WITH impact
   exitPrice = ExecutionEngine.computeExitPrice(pos.marketId, pos.isLong, pos.positionSize)
   // Impact applies — liquidations that improve balance get better pricing

4. // Compute equity at close (includes execution impact cost)
   equityResult = MarginEngine.computeEquity(positionId)
   // equityResult.equity already includes PnL, borrow, funding

5. // Compute liquidation fee
   feeCalculated = pos.positionSize × LIQUIDATION_FEE_RATE / WAD    // 1.0% of notional
   fee = min(feeCalculated, max(0, equityResult.equity))             // capped at remaining equity
   
   remainingEquity = equityResult.equity - int256(fee)

6. // Handle outcomes
   if remainingEquity > 0:
     // Outcome A: Normal — trader gets residual
     traderReceives = uint256(remainingEquity)
     badDebt = 0
   elif remainingEquity == 0:
     // Outcome B: Marginal — fee consumed everything
     traderReceives = 0
     badDebt = 0
   else:
     // Outcome C: Bad debt — position went negative
     traderReceives = 0
     badDebt = uint256(-remainingEquity)

7. // Route liquidation fee
   if fee > 0:
     if liquidator != address(0):
       // Path C: external liquidator gets bounty
       bounty = fee × LIQUIDATOR_BOUNTY_SHARE / WAD    // 10%
       feeForProtocol = fee - bounty
       USDT.transfer(liquidator, bounty)
       FeeRouter.routeFees(FeeType.LIQUIDATION, feeForProtocol)
     else:
       // Path A/B: no bounty, full fee through split
       FeeRouter.routeFees(FeeType.LIQUIDATION, fee)

8. // Handle bad debt (INSURANCE → LP SOCIALIZATION, NOT ADL)
   if badDebt > 0:
     (insurancePaid, remainder) = InsuranceFund.absorbBadDebt(pos.marketId, badDebt)
     if remainder > 0:
       // LP socialization — direct NAV hit. NO ADL during normal liquidation.
       // The LP pool absorbs this as a loss. NAV decreases.
       LeverVault.socializeLoss(remainder)

9. // Close position
   OILimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize)
   PositionManager.closePosition(positionId)
   AccountManager.releaseCollateral(pos.owner, pos.collateral)
   if traderReceives > 0:
     AccountManager.creditPnL(pos.owner, traderReceives)

10. emit PositionLiquidated(
      positionId, pos.marketId, pos.owner, liquidator,
      equityResult.equity, mm, fee, badDebt, block.timestamp
    )
    if badDebt > 0: emit BadDebtRecorded(...)
```

## Partial Liquidation (WP Section 13.7)

For large positions, full liquidation produces excessive execution impact.

```
function _liquidate(positionId, liquidator) {
    pos = PositionManager.getPosition(positionId)
    marketDepth = ExecutionEngine.getMarketDepth(pos.marketId)
    
    if pos.positionSize > marketDepth × PARTIAL_LIQ_THRESHOLD / WAD:
        // Partial liquidation mode
        chunkSize = marketDepth × PARTIAL_LIQ_CHUNK / WAD    // 5% of depth
        _partialLiquidate(positionId, chunkSize, liquidator)
    else:
        _fullLiquidate(positionId, liquidator)
}

function _partialLiquidate(positionId, chunkSize, liquidator) {
    while true:
        // Close one chunk
        _closeChunk(positionId, chunkSize, liquidator)
        
        // Recheck: is reduced position still liquidatable?
        if !isLiquidatable(positionId):
            break    // Position rescued — trader keeps the remainder
        
        if PositionManager.getPosition(positionId).positionSize < chunkSize:
            _fullLiquidate(positionId, liquidator)    // close remainder
            break
}
```

Benefits: reduces market impact, may rescue the position (partial close raises MR above MM), each chunk may improve balance → better pricing on subsequent chunks.

## batchLiquidate(uint256[] positionIds) → LiquidationResult[]
```
for each positionId:
  try liquidate(positionId) → push result
  catch → push empty result
```

## Edge Cases
- Position barely below MM → liquidatable. Small fee, trader gets residual.
- Position deeply underwater (equity << 0) → fee = 0, all is bad debt.
- Liquidation during PENDING_RESOLUTION: MM = normal_MM × 2.0. More positions become liquidatable. This cleans up risky positions before settlement.
- Borrow fees alone pushed equity below MM (PI flat) → valid liquidation. The ticking clock.
- Position opened in same block → theoretically possible if PI moves in same tx. Handle gracefully.
- Two keepers try to liquidate same position → second call sees isOpen=false, reverts.
- Gas limit hit during Path B batch → process highest-leverage first, emit incomplete event, rest handled by Path C or next oracle update.
- Liquidation improves market balance → better exit price → less bad debt. Intentional design.

## Testing
- Path A: user calls closePosition on underwater position → auto-liquidated
- Path B: oracle update makes positions liquidatable → liquidated atomically
- Path C: external caller liquidates → receives bounty
- Verify 1.0% fee on notional, capped at remaining equity
- Verify bounty = 10% of fee to external caller
- Bad debt → insurance absorbs → remainder hits LP NAV
- Partial liquidation: large position chunks down, stops when MR > MM
- PENDING_RESOLUTION: verify 2× MM multiplier triggers more liquidations
- Fuzz: equity computation matches MarginEngine independently

