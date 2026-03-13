# SPEC: InsuranceFund

## Purpose
Bad debt absorption mechanism. Funded by 20% of protocol fees (via FeeRouter). Three simultaneous constraints protect the fund from depletion: daily cap (25%), tiered insurance/ADL split, and 5% IFR floor. Bootstrapped at $10,000 at launch.

## Dependencies
- ILeverVault (TVL for IFR calculation)
- USDT token
- FixedPointMath

## Build Priority
Phase 6 — Fee Routing & LP Pool.

## Access Control
- FEE_ROUTER role: deposit
- LIQUIDATION_ENGINE role: absorbBadDebt
- SETTLEMENT_ENGINE role: absorbBadDebt
- Any address: all view functions

## Constants
```solidity
uint256 constant INSURANCE_BOOTSTRAP = 10_000e18;   // $10K initial seed
uint256 constant DAILY_CAP_PCT = 25e16;              // 25% of balance
uint256 constant IFR_FLOOR = 5e16;                   // 5% of TVL
uint256 constant IFR_TARGET = 2e17;                  // 20% of TVL
uint256 constant TIER_1_THRESHOLD = 15e16;           // 15% IFR
uint256 constant TIER_2_THRESHOLD = 1e17;            // 10% IFR
uint256 constant TIER_3_THRESHOLD = 5e16;            // 5% IFR
```

## State Variables
```solidity
uint256 private _balance;
uint256 private _dailySpent;       // amount spent in current 24h window
uint256 private _dailyWindowStart; // timestamp of current window start
uint256 private _totalAbsorbed;    // lifetime bad debt absorbed
```

## absorbBadDebt(bytes32 marketId, uint256 totalBadDebt) → (uint256 insurancePaid, uint256 remainder)

**CRITICAL:** The `remainder` return value means different things depending on caller:
- Called by **LiquidationEngine** (normal operation): remainder → LP socialization (direct NAV hit). No winners to haircut.
- Called by **SettlementEngine** (market resolution): remainder → ADL (pro-rata haircut on winning positions). LP socialization only if ADL insufficient.

The InsuranceFund itself doesn't know the difference — it just returns how much it covered and how much is left. The CALLER decides what to do with the remainder.

Three constraints applied simultaneously:

```
// 1. Reset daily window if needed
if block.timestamp > _dailyWindowStart + 24 hours:
  _dailySpent = 0
  _dailyWindowStart = block.timestamp

// 2. Determine tier (insurance vs ADL split)
ifr = getIFR()
if ifr > TIER_1_THRESHOLD:      insurancePct = WAD;  adlPct = 0
elif ifr > TIER_2_THRESHOLD:    insurancePct = 7e17; adlPct = 3e17    // 70/30
elif ifr > TIER_3_THRESHOLD:    insurancePct = 4e17; adlPct = 6e17    // 40/60
else:                           insurancePct = 1e17; adlPct = 9e17    // 10/90

// Insurance's share of this bad debt event
insuranceTarget = totalBadDebt × insurancePct / WAD

// 3. Apply daily cap constraint
dailyCap = _balance × DAILY_CAP_PCT / WAD
dailyRemaining = dailyCap > _dailySpent ? dailyCap - _dailySpent : 0
insuranceTarget = min(insuranceTarget, dailyRemaining)

// 4. Apply floor constraint (fund cannot drop below 5% of TVL)
tvl = LeverVault.totalAssets()
floor = tvl × IFR_FLOOR / WAD
maxSpend = _balance > floor ? _balance - floor : 0
insuranceTarget = min(insuranceTarget, maxSpend)

// 5. Final amounts
insurancePaid = insuranceTarget
remainder = totalBadDebt - insurancePaid

// 6. Execute
_balance -= insurancePaid
_dailySpent += insurancePaid
_totalAbsorbed += insurancePaid

emit BadDebtAbsorbed(marketId, totalBadDebt, insurancePaid, remainder, block.timestamp)
return (insurancePaid, remainder)
```

## getIFR() → uint256
```
tvl = LeverVault.totalAssets()
if tvl == 0: return WAD   // if no TVL, fund is "infinite" relative to exposure
return _balance × WAD / tvl
```

## isFullyFunded() → bool
```
return getIFR() >= IFR_TARGET
```
Used by FeeRouter to determine tier 1 vs tier 2 fee split.

## Edge Cases
- Multiple bad debt events in one block → daily cap correctly accumulates
- TVL drops to near-zero → floor is near-zero → fund can still spend
- Fund at exactly the floor → maxSpend = 0 → all bad debt goes to ADL
- Bad debt exceeds entire fund → fund pays what it can, rest is ADL
- Bootstrap: constructor should seed _balance = INSURANCE_BOOTSTRAP

