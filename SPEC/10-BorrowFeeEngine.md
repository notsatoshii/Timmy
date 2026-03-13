# SPEC: BorrowFeeEngine

## Purpose
Continuous fee on all leveraged positions (1× exempt). Index-based accrual (like Aave/Compound). The "ticking clock" that gives every leveraged position a finite economic lifespan. Primary revenue source for LPs, protocol, and insurance.

Rate = base × M_ttR × (1 + imbalance_surcharge). Time, liveness, volatility, concentration, and imbalance all feed in via R_borrow_adjusted and the surcharge — but the formula itself has three terms, not five separate multipliers.

## Dependencies
- RiskCurves (R_borrow, borrowMttR, M_market)
- IMarketRegistry (τ, is_live)
- IOILimits (imbalance ratio)
- IPositionManager (position data for fee computation)
- FixedPointMath

## Build Priority
Phase 4 — Fee Engines. MarginEngine depends on this for equity calculation.

## Access Control
- KEEPER role: accrueIndex, accrueAll
- Any address: all view functions
- OracleAdapter can also trigger accrueIndex on PI updates

## Constants
```solidity
uint256 constant BASE_BORROW_RATE = 2e14;   // 0.02% per hour in WAD
uint256 constant M_TTR_MAX = 25e18;          // 25×
uint256 constant SURCHARGE_FACTOR = 1e18;    // 1.0
```

## State Variables
```solidity
// Cumulative borrow index per market per side (WAD, starts at WAD)
mapping(bytes32 => uint256) private _longBorrowIndex;
mapping(bytes32 => uint256) private _shortBorrowIndex;
mapping(bytes32 => uint256) private _lastAccrualTime;   // per market
```

## Index-Based Accrual

The pattern: each market side has a cumulative index that increases over time. Each position stores a snapshot of the index at open. Accrued fees = position_notional × (current_index - snapshot_index).

### accrueIndex(bytes32 marketId, bool isLong)
```
deltaT = block.timestamp - _lastAccrualTime[marketId]
if deltaT == 0: return

rate = getCurrentBorrowRate(marketId, isLong)
// rate is per-hour. Convert to per-second for deltaT:
ratePerSecond = rate / 3600

indexDelta = ratePerSecond × deltaT
// Update cumulative index:
if isLong:
  _longBorrowIndex[marketId] += indexDelta
else:
  _shortBorrowIndex[marketId] += indexDelta

_lastAccrualTime[marketId] = block.timestamp
emit BorrowIndexUpdated(marketId, isLong, newIndex, rate, block.timestamp)
```

**Note:** Must accrue BOTH sides on every call (or track last accrual per side separately). Simplest: accrue both in one function call.

### getCurrentBorrowRate(bytes32 marketId, bool isLong) → uint256
```
// 1. Get R_borrow_adjusted for this market
tauEff = RiskCurves.computeTauEffective(MarketRegistry.getTau(marketId), MarketRegistry.isLive(marketId))
rBorrow = RiskCurves.computeRBorrow(tauEff)
mMarket = RiskCurves.computeMarketAdjustment(...)
rBorrowAdj = rBorrow × mMarket / WAD

// 2. Compute M_ttR
mTtR = RiskCurves.borrowMttR(rBorrowAdj)
  // = WAD + (M_TTR_MAX - WAD) × (WAD - rBorrowAdj) / WAD

// 3. Compute imbalance surcharge (heavy side only)
imbalanceRatio = OILimits.getImbalanceRatio(marketId)
if isLong && imbalanceRatio > 0:      // longs are heavy
  surcharge = uint256(imbalanceRatio) × SURCHARGE_FACTOR / WAD
elif !isLong && imbalanceRatio < 0:   // shorts are heavy
  surcharge = uint256(-imbalanceRatio) × SURCHARGE_FACTOR / WAD
else:
  surcharge = 0   // light side or balanced

// 4. Final rate
rate = BASE_BORROW_RATE × mTtR / WAD × (WAD + surcharge) / WAD
return rate   // per hour
```

### getAccruedFees(uint256 positionId) → uint256
```
pos = PositionManager.getPosition(positionId)
if pos.leverage == WAD: return 0    // 1× positions exempt

currentIndex = pos.isLong ? _longBorrowIndex[pos.marketId] : _shortBorrowIndex[pos.marketId]
indexDelta = currentIndex - pos.borrowIndex
fees = pos.positionSize × indexDelta / WAD
return fees
```

## Edge Cases
- 1× leveraged positions: exempt. Check leverage == WAD and return 0.
- Market with zero OI: rate still computes but index doesn't change (no positions to accrue).
- deltaT = 0 (multiple accruals in same block): no-op.
- imbalanceRatio = 0 (balanced): surcharge = 0 for both sides.
- Very high M_ttR near resolution (25×): base 0.02% × 25 = 0.50%/hr. Verify this matches WP table.
- Fee accrual frozen at external resolution timestamp for PENDING_RESOLUTION markets: the SettlementEngine handles this by using the stored externalResolutionTime for fee calculations, not current block time.

## Testing
- Verify M_ttR values against WP Section 15.3 table
- Verify index accrual: two positions opened at different times, same market, different accrued fees
- Verify surcharge: heavy side pays more than light side
- Verify 1× exemption
- Fuzz: accrued fees always increase with time (never decrease)

