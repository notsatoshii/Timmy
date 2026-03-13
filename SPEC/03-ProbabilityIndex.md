# SPEC: ProbabilityIndex (Library)

## Purpose
Helper library for PI validation, bounds checking, PnL computation, and boundary detection. Pure math, no state. Small library — keep it focused.

## Dependencies
- FixedPointMath

## Build Priority
Phase 1 — Foundation. Used by OracleAdapter, MarginEngine.

## Constants
```solidity
uint256 constant PI_MIN = 0;
uint256 constant PI_MAX = 1e18;  // WAD = 1.0
```

## Functions

### isValid(uint256 pi) → bool
```
return pi <= PI_MAX;
```
- PI is in [0, WAD]. Always unsigned. 0 and WAD are both valid (settlement values).

### clamp(uint256 pi) → uint256
```
return pi > PI_MAX ? PI_MAX : pi;
```

### computePnL(uint256 piEntry, uint256 piCurrent, uint256 positionSize, bool isLong) → int256
```
if isLong:
  pnl = int256(piCurrent) - int256(piEntry)) × positionSize / WAD
if short:
  pnl = (int256(piEntry) - int256(piCurrent)) × positionSize / WAD
```
- Result is SIGNED. Positive = profit, negative = loss.
- positionSize is notional in WAD.
- At settlement: piCurrent is 0 or WAD. Verify PnL is correct for both outcomes.

### isNearBoundary(uint256 pi, uint256 threshold) → bool
```
return pi < threshold || pi > (PI_MAX - threshold);
```
- Used to flag markets near resolution where binary jump risk is highest.

## Edge Cases
- computePnL with piEntry = piCurrent → pnl = 0
- computePnL with piCurrent = 0, isLong, piEntry = 0.5 → large negative PnL
- computePnL with piCurrent = WAD, isLong, piEntry = 0.5 → large positive PnL
- isNearBoundary(0, any threshold > 0) → true
- isNearBoundary(WAD, any threshold > 0) → true

