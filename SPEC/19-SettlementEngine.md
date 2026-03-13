# SPEC: SettlementEngine

## Purpose
Binary event resolution. PI snaps to 0 or 1. Computes settlement payouts for all positions. Handles bad debt via four-layer waterfall: position equity → insurance → ADL (pro-rata winner haircut) → LP socialization. Void handling: all positions refund at current equity, no settlement fee. Build last — depends on everything.

## Dependencies
- IOracleAdapter (snapToOutcome, getPI)
- IMarketRegistry (market state, outcome, external resolution timestamp)
- IPositionManager (read/close positions)
- IBorrowFeeEngine (accrued borrow fees — frozen at external timestamp)
- IFundingRateEngine (accrued funding — frozen at external timestamp)
- IInsuranceFund (absorb bad debt)
- IFeeRouter (route settlement fees)
- IOILimits (decrease OI)
- IAccountManager (release collateral, credit PnL)
- FixedPointMath, ProbabilityIndex

## Build Priority
Phase 7 — Terminal. Build LAST. Depends on all other contracts.

## Access Control
- KEEPER role: settleMarket, settleVoid
- Any address: claimSettlement (permissionless — anyone can claim for any position)
- Any address: all view functions

## Constants
```solidity
uint256 constant SETTLEMENT_FEE_RATE = 2e15;       // 0.20% (20 bps)
uint256 constant PENDING_RESOLUTION_MM_MULT = 2e18; // 2× MM during oracle gap
```

## State Variables
```solidity
mapping(bytes32 => MarketSettlementState) private _marketSettlements;
mapping(uint256 => bool) private _positionSettled;   // positionId → claimed

struct MarketSettlementState {
    bool settled;             // settleMarket has been called
    uint8 outcome;            // 0 or 1
    uint256 totalBadDebt;
    uint256 insuranceUsed;
    uint256 adlRemainder;     // bad debt not covered by insurance → ADL/socialization
    uint256 adlHaircut;       // WAD — percentage haircut on winners (0 if no ADL)
    uint256 totalWinnerPayout; // pre-haircut aggregate (for computing haircut ratio)
    uint256 feesCollected;
    // Frozen fee indices at external resolution time:
    uint256 finalBorrowIndexLong;
    uint256 finalBorrowIndexShort;
    int256 finalFundingIndex;    // single index (direction applied per-position)
}
```

## settleMarket(bytes32 marketId)

**Gas strategy:** settleMarket does NOT iterate all positions. It computes aggregate totals using pre-tracked values (OILimits tracks per-side OI, BorrowFeeEngine tracks per-side indices). Individual position settlement happens in claimSettlement, which recomputes each position's result using the stored frozen indices and ADL haircut. This is O(1) per claim, not O(n) up front.

For the ADL haircut calculation, settleMarket needs totalBadDebt and totalWinnerPayout. These can be estimated from aggregate data:
- Total winner notional = side OI of winning side (from OILimits)
- Total loser notional = side OI of losing side
- Bad debt estimation requires knowing per-position equity, which IS O(n)

**Practical approach:** settleMarket freezes indices and sets the market as settled. The FIRST N claims process normally. If any claim discovers bad debt (final_equity < 0), it records it. After all claims complete, a finalizeSettlement() call processes the bad debt waterfall and computes ADL haircut. Claims that already completed are retroactively adjusted (or: all claims are held in escrow until finalization).

**Simpler v1 approach:** Accept the O(n) first pass for v1. Cap markets at ~500 positions via per-user OI limits and allocation weights. Optimize in v2 if needed. This is a TESTNET deployment.

```
1. market = MarketRegistry.getMarket(marketId)
   require market.state == RESOLVED
   require !_marketSettlements[marketId].settled

2. outcome = market.outcome   // 0 or 1
   piOutcome = outcome == 1 ? WAD : 0

3. Snap PI to outcome:
   OracleAdapter.snapToOutcome(marketId, piOutcome)

4. Freeze fee indices at external resolution timestamp:
   externalTime = market.externalResolutionTime
   state.finalBorrowIndexLong = BorrowFeeEngine.computeIndexAt(marketId, true, externalTime)
   state.finalBorrowIndexShort = BorrowFeeEngine.computeIndexAt(marketId, false, externalTime)
   state.finalFundingIndex = FundingRateEngine.computeIndexAt(marketId, externalTime)

5. FIRST PASS — Compute all payouts, identify bad debt:
   totalWinnerPayout = 0
   totalBadDebt = 0
   
   for each positionId:
     if !PositionManager.isPositionOpen(positionId): continue
     pos = PositionManager.getPosition(positionId)
     
     // Determine winner/loser
     isWinner = (pos.isLong && outcome == 1) || (!pos.isLong && outcome == 0)
     
     // Compute PnL against final PI
     outcomePnL = pos.positionSize × abs(int256(piOutcome) - int256(pos.entryPI)) / WAD
     if !isWinner: outcomePnL = -outcomePnL  // negative for losers
     
     // Accrued fees (frozen at external resolution timestamp — use stored values)
     borrowFees = BorrowFeeEngine.getAccruedFees(positionId)
     funding = FundingRateEngine.getAccruedFunding(positionId)
     
     // Final equity
     equity = int256(pos.collateral) + outcomePnL - int256(borrowFees) + funding
     
     if isWinner:
       settlementFee = pos.positionSize × SETTLEMENT_FEE_RATE / WAD
       payout = equity - int256(settlementFee)
       if payout < 0: payout = 0; settlementFee = max(0, equity)
       totalWinnerPayout += uint256(payout)
     else:
       // Loser
       if equity < 0:
         totalBadDebt += uint256(-equity)
     
     // Store per-position result for later claiming

6. SECOND PASS — Handle bad debt:
   if totalBadDebt > 0:
     (insurancePaid, remainder) = InsuranceFund.absorbBadDebt(marketId, totalBadDebt)
     
     // SETTLEMENT-SPECIFIC: remainder goes to ADL (winner haircuts), NOT LP socialization
     // This is DIFFERENT from normal liquidation where remainder → LP socialization
     // ADL only exists at settlement because that's when there are winners to haircut
     if remainder > 0 && totalWinnerPayout > 0:
       haircut = remainder × WAD / totalWinnerPayout
       // Each winner's payout reduced by haircut%
       // If haircut > WAD (bad debt exceeds winner payouts): cap at WAD, rest → LP socialization
       if haircut > WAD:
         haircut = WAD
         lpSocializationAmount = remainder - totalWinnerPayout
         LeverVault.socializeLoss(lpSocializationAmount)
     elif remainder > 0 && totalWinnerPayout == 0:
       // No winners to haircut — all bad debt goes to LP socialization
       LeverVault.socializeLoss(remainder)
   
   _marketSettlements[marketId] = MarketSettlementState(
     settled: true, outcome: outcome, totalBadDebt: totalBadDebt,
     insuranceUsed: insurancePaid, adlAmount: adlAmount, adlHaircut: haircut,
     totalWinnerPayout: totalWinnerPayout, feesCollected: totalFees
   )

7. emit MarketSettled(...)
   if adlAmount > 0: emit ADLApplied(...)
```

## claimSettlement(uint256 positionId) → SettlementResult

```
1. require !_positionSettled[positionId]
2. pos = PositionManager.getPosition(positionId)
3. settlement = _marketSettlements[pos.marketId]
   require settlement.settled

4. Recompute this position's result (or read from stored results):
   // Same calculation as in settleMarket first pass
   isWinner = ...
   equity = ...
   
   if isWinner:
     settlementFee = ...
     payout = max(0, equity - int256(settlementFee))
     // Apply ADL haircut
     payout = payout × (WAD - settlement.adlHaircut) / WAD
   else:
     payout = max(0, equity)   // losers get remaining equity if any
     settlementFee = 0

5. Execute:
   _positionSettled[positionId] = true
   OILimits.decreaseOI(pos.marketId, pos.owner, pos.isLong, pos.positionSize)
   PositionManager.closePosition(positionId)
   AccountManager.releaseCollateral(pos.owner, pos.collateral)
   if payout > 0: AccountManager.creditPnL(pos.owner, payout)
   if settlementFee > 0: FeeRouter.routeFees(FeeType.SETTLEMENT, settlementFee)

6. emit PositionSettled(...)
   return result
```

## settleVoid(bytes32 marketId)

```
1. market = MarketRegistry.getMarket(marketId)
   require market.state == VOIDED

2. positionIds = PositionManager.getMarketPositions(marketId)

3. For each position:
   // PnL = 0 (entry price is irrelevant)
   // Fees are NOT refunded (they compensated LPs for real risk)
   equity = int256(pos.collateral) - int256(borrowFees) + funding
   payout = max(0, equity)
   // No settlement fee on void
   
   // Close and pay out
   PositionManager.closePosition(positionId)
   OILimits.decreaseOI(...)
   AccountManager.releaseCollateral(...)
   if payout > 0: AccountManager.creditPnL(pos.owner, payout)

4. emit VoidSettlement(...)
```

## Edge Cases
- All OI on one side, that side loses → every position loses. No winners → no ADL target. Bad debt after insurance → LP socialization via LeverVault.socializeLoss(). This is the worst-case scenario for LPs.
- Winner with equity < settlement fee → fee reduced to equity, payout = 0. NOT bad debt.
- Position liquidated during PENDING_RESOLUTION → already closed. claimSettlement skips it.
- Oracle delay > 24h → settleMarket still works whenever outcome is finally recorded. Fee accrual is anchored to externalResolutionTime, not block.timestamp.
- Multiple markets resolve simultaneously → each settles independently. Only cross-market constraint is insurance daily cap (25%).
- claimSettlement called twice for same position → reverts (already settled).
- Empty market (no positions) → settleMarket succeeds with zero payouts.
- ADL haircut > 100% (bad debt > winner payouts) → remaining goes to LP socialization. Haircut capped at WAD.

## Fee Accrual Timing
**CRITICAL:** Borrow and funding fees are frozen at `market.externalResolutionTime`, NOT at the current block timestamp. The SettlementEngine must use this external timestamp when computing accrued fees.

Implementation (WP Section 18.5):
```
// When settleMarket is called, compute and store frozen indices:
finalBorrowIndex_long = BorrowFeeEngine.computeIndexAt(marketId, true, externalResolutionTime)
finalBorrowIndex_short = BorrowFeeEngine.computeIndexAt(marketId, false, externalResolutionTime)
finalFundingIndex = FundingRateEngine.computeIndexAt(marketId, externalResolutionTime)
  // Single funding index — direction applied per-position in accrued calc

// Then for each position, accrued fees use frozen indices:
borrowFees = pos.positionSize × (finalBorrowIndex[side] - pos.borrowIndex) / WAD

fundingDelta = finalFundingIndex - pos.fundingIndex
direction = pos.isLong ? 1 : -1
accruedFunding = -direction × int256(pos.positionSize) × fundingDelta / int256(WAD)
  // Positive = received, negative = paid (consistent with equity equation)
```

BorrowFeeEngine.computeIndexAt() and FundingRateEngine.computeIndexAt() are view functions that return what the index would have been at a specific historical timestamp. They extrapolate from the last known accrual point.

## Testing
- Full settlement flow: open positions → PI moves → resolve → claim → verify payouts
- ADL: create scenario where losers have bad debt, verify winner haircut math
- Void: open positions → void → verify PnL=0, fees deducted, no settlement fee
- Fee freezing: verify fees don't accrue past external resolution timestamp
- Edge: all positions on losing side → no winners, no ADL, insurance + LP socialization
- Edge: single position in market → settles cleanly
- Permissionless claim: third party calls claimSettlement for another user's position → works

