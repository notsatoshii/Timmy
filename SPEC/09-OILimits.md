# SPEC: OILimits

## Purpose
Four-tier OI cap system: global, per-market, per-side, per-user. Tracks current OI at all levels. Every cap is dynamic — scales with TVL, compresses with R(τ). Enforces hard capacity constraints. When a cap is reached, no new positions open on that side.

## Dependencies
- RiskCurves (R_adjusted, oiCapMultiplier)
- IMarketRegistry (τ, is_live, allocation weights)
- ILeverVault (TVL)
- FixedPointMath

## Build Priority
Phase 3 — Risk & Leverage.

## Access Control
- EXECUTION_ENGINE role: increaseOI, decreaseOI
- LIQUIDATION_ENGINE role: decreaseOI
- SETTLEMENT_ENGINE role: decreaseOI
- Any address: all view functions

## Constants
```solidity
uint256 constant GLOBAL_OI_RATIO = 6e17;   // 0.60 — 60% of TVL
uint256 constant OI_CAP_FLOOR = 2e17;      // 0.20 — per-market floor
uint256 constant SIDE_OI_RATIO = 7e17;     // 0.70 — per-side
uint256 constant USER_OI_RATIO = 2e17;     // 0.20 — per-user
```

## State Variables
```solidity
uint256 private _globalOI;
mapping(bytes32 => uint256) private _marketOI;         // total OI per market
mapping(bytes32 => uint256) private _longOI;           // long OI per market
mapping(bytes32 => uint256) private _shortOI;          // short OI per market
mapping(bytes32 => mapping(address => uint256)) private _userOI;  // per user per market
```

## Tier Formulas

### Tier 1: Global OI Cap
```
Global_OI_Cap = TVL × GLOBAL_OI_RATIO / WAD
```
- Does NOT compress with R(τ). Fixed at 60% of TVL.
- Recalculate on TVL change or every hour.

### Tier 2: Per-Market OI Cap
```
Base_Market_Cap = Global_OI_Cap × allocationWeight / WAD
Market_OI_Cap = Base_Market_Cap × oiCapMultiplier(R_adjusted) / WAD
oiCapMultiplier = 0.20 + R_adjusted × 0.80
```
- Compresses with R(τ). Floor at 20% of base.

### Tier 3: Per-Side OI Cap
```
Side_OI_Cap = Market_OI_Cap × SIDE_OI_RATIO / WAD    // 70%
```

### Tier 4: Per-User OI Cap
```
User_OI_Cap = Market_OI_Cap × USER_OI_RATIO / WAD    // 20%
```

## increaseOI(bytes32 marketId, address user, bool isLong, uint256 notional)
```
Check all four tiers — revert with specific tier if any breached:
1. _globalOI + notional <= Global_OI_Cap
2. _marketOI[marketId] + notional <= Market_OI_Cap
3. sideOI + notional <= Side_OI_Cap      // _longOI or _shortOI based on isLong
4. _userOI[marketId][user] + notional <= User_OI_Cap

If all pass:
  _globalOI += notional
  _marketOI[marketId] += notional
  _longOI[marketId] += notional (or _shortOI)
  _userOI[marketId][user] += notional
  emit OIIncreased
```

## decreaseOI(bytes32 marketId, address user, bool isLong, uint256 notional)
```
_globalOI -= notional     // safe sub, floor at 0
_marketOI[marketId] -= notional
_longOI[marketId] -= notional (or _shortOI)
_userOI[marketId][user] -= notional
emit OIDecreased
```

## getImbalanceRatio(bytes32 marketId) → int256
```
longOI = _longOI[marketId]
shortOI = _shortOI[marketId]
totalOI = longOI + shortOI
if totalOI == 0: return 0
return (int256(longOI) - int256(shortOI)) × WAD / int256(totalOI)
```
- Range: [-WAD, +WAD]. Positive = long-heavy.
- Used by ExecutionEngine (imbalance_delta), BorrowFeeEngine (surcharge), FundingRateEngine.

## Edge Cases
- TVL drops → caps shrink → existing OI may exceed new caps. This is fine — grandfathered. No new opens on that side/market until OI falls below new cap.
- globalOI could temporarily exceed cap after TVL withdrawal. increaseOI will block new positions but existing ones stay.
- Market with 0 allocation weight → all caps are 0 → no positions can open.
- decreaseOI by more than tracked → floor at 0, don't underflow.
- getImbalanceRatio when no OI → return 0 (balanced).

