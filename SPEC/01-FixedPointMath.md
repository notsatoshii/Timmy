# SPEC: FixedPointMath (Library)

## Purpose
18-decimal fixed-point arithmetic. WAD = 1e18. Every monetary value, rate, and ratio in the protocol uses this. Zero dependencies. Build and test first.

## Dependencies
None.

## Build Priority
Phase 1 — Foundation. No other contract can be built without this.

## Constants
```solidity
uint256 constant WAD = 1e18;
uint256 constant HALF_WAD = 5e17;
uint256 constant WAD_SQUARED = 1e36;
```

## Functions

### wadMul(uint256 a, uint256 b) → uint256
```
result = (a * b + HALF_WAD) / WAD
```
- Rounds to nearest (not truncate) via HALF_WAD addition
- Must revert on overflow of (a * b)
- wadMul(0, anything) = 0
- wadMul(WAD, x) = x

### wadDiv(uint256 a, uint256 b) → uint256
```
result = (a * WAD + b / 2) / b
```
- Rounds to nearest
- Must revert on b = 0
- wadDiv(0, anything) = 0
- wadDiv(x, WAD) = x

### wadExp(int256 x) → uint256
```
e^x where x is WAD-encoded signed integer
```
- Used by RiskCurves: R(τ) = 1 - e^(-λτ/τ_ref)
- Must handle negative x (the primary use case)
- Precision: within 1e-8 of actual value
- wadExp(0) = WAD (e^0 = 1)
- wadExp(WAD) ≈ 2.718e18
- For very large negative x: return 0 (e^(-∞) = 0)
- For very large positive x: revert (overflow)
- Recommend: use solmate's or solady's battle-tested implementation

### wadLn(uint256 x) → int256
```
ln(x) where x is WAD-encoded
```
- wadLn(WAD) = 0
- wadLn(0) → revert
- Needed if computing inverse risk curves

### wadSqrt(uint256 x) → uint256
```
sqrt(x) where x is WAD-encoded
```
- Used by LeverageModel: TVL_Multiplier = (TVL/TVL_maturity)^0.5
- Used by SmoothingEngine: w_time = sqrt(τ/τ_max)
- wadSqrt(WAD) = WAD
- wadSqrt(0) = 0
- Implementation: Babylonian method or solmate's sqrt, adjusted for WAD

### wadPow(uint256 x, uint256 n) → uint256
General power function. May not be needed if only sqrt is used.

### clamp(uint256 value, uint256 minVal, uint256 maxVal) → uint256
```
if value < minVal → minVal
if value > maxVal → maxVal
else → value
```

### clampInt(int256 value, int256 minVal, int256 maxVal) → int256
Signed version of clamp.

### abs(int256 x) → uint256
```
x >= 0 ? uint256(x) : uint256(-x)
```
- abs(type(int256).min) → revert (cannot negate)

### toInt256(uint256 x) → int256
- Revert if x > uint256(type(int256).max)

### toUint256(int256 x) → uint256
- Revert if x < 0

## Edge Cases to Test
- wadMul with max uint values → overflow revert
- wadDiv by zero → revert
- wadDiv by 1 (not WAD) → result is x * WAD (common mistake)
- wadExp with x = -100e18 → should return ~0, not revert
- wadExp with x = +100e18 → should revert (overflow)
- wadSqrt(1) → not WAD! sqrt(1) in WAD = sqrt(1e18) ≈ 1e9. Make sure WAD-encoding is correct.
- All functions with 0 inputs
- Rounding: verify wadMul(3, WAD/3) = 1 (not 0)

## Testing Strategy
- Unit tests for every function with known values
- Fuzz tests: wadMul(a, b) / wadDiv result matches Solidity's native math at lower precision
- Fuzz tests: wadDiv(wadMul(a, b), b) ≈ a (round-trip)
- Compare wadExp output against precomputed table for key values used by RiskCurves
- Gas benchmarks for each function

