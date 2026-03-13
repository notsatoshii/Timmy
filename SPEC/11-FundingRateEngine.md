# SPEC: FundingRateEngine

## Purpose
Trader↔trader periodic payments incentivizing balanced OI. Heavy side pays light side. OI splits into matched (trader↔trader, zero-sum) and unmatched (trader→LP pool, risk compensation). Funding does NOT go through 50/30/20 split. Does NOT involve protocol treasury or insurance.

## Dependencies
- RiskCurves (R_adjusted for funding_multiplier)
- IMarketRegistry (τ, is_live)
- IOILimits (longOI, shortOI, imbalance)
- IPositionManager (position data)
- IRewardsDistributor (to route unmatched funding)
- FixedPointMath

## Build Priority
Phase 4 — Fee Engines. MarginEngine depends on this for equity calculation.

## Access Control
- KEEPER role: accrueFunding, routeUnmatchedFunding
- Any address: all view functions

## Constants
```solidity
uint256 constant BASE_FUNDING_RATE = 1e14;      // 0.01% per hour
uint256 constant MAX_FUNDING_RATE = 5e14;        // 0.05% per hour
uint256 constant FUNDING_ESCALATION_MAX = 4e18;  // 4.0 (range becomes 1×→5×)
```

## State Variables
```solidity
mapping(bytes32 => int256) private _fundingIndex;           // single cumulative index per market (signed)
mapping(bytes32 => uint256) private _lastFundingTime;
mapping(bytes32 => uint256) private _pendingUnmatchedFunding;  // USDT to route to LP
```

## Funding Rate Calculation

### getCurrentFundingRate(bytes32 marketId) → int256
```
longOI = OILimits.getSideOI(marketId, true)
shortOI = OILimits.getSideOI(marketId, false)
totalOI = longOI + shortOI
if totalOI == 0: return 0

imbalanceRatio = |longOI - shortOI| × WAD / totalOI

// Escalation near resolution
tauEff = RiskCurves.computeTauEffective(...)
r = RiskCurves.computeR(tauEff)
mMarket = RiskCurves.computeMarketAdjustment(...)
rAdj = r × mMarket / WAD
fundingMultiplier = WAD + (FUNDING_ESCALATION_MAX - WAD) × (WAD - rAdj) / WAD
  // Range: 1× (far) → 5× (at resolution)

rateCalc = BASE_FUNDING_RATE × imbalanceRatio / WAD × fundingMultiplier / WAD
rate = min(rateCalc, MAX_FUNDING_RATE)

// Sign: positive = longs pay (long-heavy), negative = shorts pay (short-heavy)
if longOI > shortOI: return int256(rate)
if shortOI > longOI: return -int256(rate)
return 0
```

### accrueFunding(bytes32 marketId)
```
deltaT = block.timestamp - _lastFundingTime[marketId]
if deltaT == 0: return

rate = getCurrentFundingRate(marketId)  // signed, per hour
ratePerSecond = rate / 3600

// SINGLE INDEX — positive rate means index increases when longs pay
_fundingIndex[marketId] += ratePerSecond × int256(deltaT)

// Track unmatched funding for LP routing
longOI = OILimits.getSideOI(marketId, true)
shortOI = OILimits.getSideOI(marketId, false)
unmatchedOI = abs(int256(longOI) - int256(shortOI))
unmatchedFunding = abs(rate) × unmatchedOI / WAD × deltaT / 3600
_pendingUnmatchedFunding[marketId] += unmatchedFunding

_lastFundingTime[marketId] = block.timestamp
emit FundingIndexUpdated(marketId, _fundingIndex[marketId], rate, block.timestamp)
```

### getAccruedFunding(uint256 positionId) → int256
```
pos = PositionManager.getPosition(positionId)
currentIndex = _fundingIndex[pos.marketId]
indexDelta = currentIndex - pos.fundingIndex    // pos.fundingIndex is the snapshot at open

// DIRECTION-AWARE: negate for longs so positive = received, negative = paid
direction = pos.isLong ? int256(1) : int256(-1)
funding = -direction × int256(pos.positionSize) × indexDelta / int256(WAD)
return funding

// Sign verification:
// Long-heavy market (rate > 0): index rises → indexDelta > 0
//   Long:  -( 1 × pos × positive) = NEGATIVE → "paid" ✓
//   Short: -(-1 × pos × positive) = POSITIVE → "received" ✓
```

### routeUnmatchedFunding(bytes32 marketId)
```
amount = _pendingUnmatchedFunding[marketId]
if amount == 0: return
_pendingUnmatchedFunding[marketId] = 0
RewardsDistributor.receiveUnmatchedFunding(marketId, amount)
// Actual USDT transfer from... where? From the LP vault (the counterparty).
// The heavy side pays to the vault via position equity reduction.
emit UnmatchedFundingRouted(marketId, amount, block.timestamp)
```

## Edge Cases
- Perfectly balanced book (longOI = shortOI): rate = 0, no payments.
- 100% on one side: rate = base × 1.0 × multiplier. Maximum rate.
- Imbalance flips direction: sign changes smoothly (crosses zero).
- Max rate cap: 0.05%/hr = $50/hr on $100K notional. Prevents single-mechanism liquidation pressure.
- Rate frozen at external resolution timestamp for settled markets (same as borrow).

## Testing
- Verify zero-imbalance → zero funding
- Verify heavy side pays, light side receives
- Verify cap at MAX_FUNDING_RATE
- Verify escalation: same imbalance closer to resolution → higher rate
- Verify matched vs unmatched split amounts are consistent
- Fuzz: getAccruedFunding for longs + shorts on same market sums to ≈ 0 (matched portion cancels)

