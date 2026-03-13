# SPEC: RiskCurves (Library)

## Purpose
Computes the two risk curves R(τ) and R_borrow(τ), effective time-to-resolution, market-specific adjustments, and all parameter mappings. Pure math, no state. The mathematical heartbeat of the protocol — every risk parameter flows from these functions.

## Dependencies
- FixedPointMath

## Build Priority
Phase 1 — Foundation. LeverageModel, OILimits, MarginEngine, BorrowFeeEngine, FundingRateEngine, ExecutionEngine all depend on this.

## Constants
```solidity
uint256 constant LAMBDA = 2e18;
uint256 constant TAU_REF = 24;              // hours (NOT WAD — raw integer)
uint256 constant TAU_REF_BORROW = 168;      // hours
uint256 constant LIVE_COMPRESSION = 7e17;   // 0.70
uint256 constant CONCENTRATION_THRESHOLD = 15e16;  // 0.15
uint256 constant CONCENTRATION_FLOOR = 5e17;       // 0.50
```

## Functions

### computeTauEffective(uint256 tau, bool isLive) → uint256
```
τ_effective = τ × (1 - LIVE_COMPRESSION × is_live)
```
- tau: hours to resolution in WAD (e.g., 6 hours = 6e18)
- When not live: τ_effective = τ
- When live: τ_effective = τ × 0.30
- Result in WAD-encoded hours

### computeR(uint256 tauEffective) → uint256
```
R(τ) = 1 - e^(-λ × τ_effective / τ_ref)
     = WAD - wadExp(-LAMBDA × tauEffective / TAU_REF)
```
- Result: [0, WAD]. 0 = max tightening, WAD = full flexibility.
- When tauEffective = 0: R = 0
- When tauEffective very large: R → WAD
- The negative exponent means wadExp receives a negative value

### computeRBorrow(uint256 tauEffective) → uint256
```
R_borrow(τ) = 1 - e^(-λ × τ_effective / τ_ref_borrow)
```
- Same shape as R(τ) but with 168h reference (7× longer)
- This curve starts tightening a full week before resolution

### computeVolFactor(uint256 sigmaCurrent, uint256 sigmaBaseline) → uint256
```
Vol_Factor = WAD / (WAD + max(0, sigmaCurrent - sigmaBaseline))
```
- Result: (0, WAD]. 1.0 when volatility at baseline. Decreases with excess volatility.
- If sigmaCurrent ≤ sigmaBaseline: return WAD

### computeDepthFactor(uint256 externalDepth, uint256 depthThreshold) → uint256
```
Depth_Factor = min(WAD, externalDepth × WAD / depthThreshold)
```
- Result: [0, WAD]. 1.0 when depth meets threshold.
- depthThreshold = 0 → revert (division by zero)

### computeConcentrationFactor(uint256 marketOI, uint256 globalOI) → uint256
```
C = marketOI / globalOI
Concentration_Factor = max(CONCENTRATION_FLOOR, WAD - 2 × max(0, C - CONCENTRATION_THRESHOLD))
```
- Result: [0.5, 1.0] in WAD
- If globalOI = 0: return WAD (no concentration when nothing is open)
- If C < 0.15: return WAD (no penalty)
- If C = 0.40: factor = max(0.5, 1 - 2×0.25) = 0.5 (floor)
- If C ≥ 0.40: factor = 0.5 (floor)

### computeMarketAdjustment(...) → uint256
```
M_market = min(WAD, volFactor × depthFactor × concentrationFactor)
```
- Combines all three factors. Can only reduce (≤ WAD).

### computeRAdjusted(uint256 r, uint256 mMarket) → uint256
```
R_adjusted = r × mMarket / WAD
```

### Parameter Mapping Functions
Each takes R_adjusted (or R_borrow_adjusted) and returns a WAD value:

```
leverageCompression(rAdj) = rAdj
oiCapMultiplier(rAdj) = 2e17 + rAdj × 8e17 / WAD        // 0.20 + R × 0.80
mmMultiplier(rAdj) = 3e18 - rAdj × 2e18 / WAD            // 3.0 - R × 2.0
imMultiplier(rAdj) = 3e18 - rAdj × 2e18 / WAD            // 3.0 - R × 2.0
executionDepthMultiplier(rAdj) = 3e17 + rAdj × 7e17 / WAD // 0.30 + R × 0.70
borrowMttR(rBorrowAdj) = WAD + (25e18 - WAD) × (WAD - rBorrowAdj) / WAD  // 1 + 24×(1-R)
oracleFrequency(rAdj) = 30 + rAdj × 270 / WAD            // seconds
liquidationSLA(rAdj) = 15 + rAdj × 75 / WAD              // seconds
```

## Edge Cases to Test
- tau = 0 → R = 0, R_borrow = 0 (resolution, max tightening)
- tau = 10000 hours → R ≈ WAD (far from resolution)
- isLive transition at tau = 6 hours: R jumps from R(6) to R(1.8)
- globalOI = 0 → concentration factor = WAD (not division by zero)
- All factors at 1.0 → M_market = WAD
- All factors at minimum → M_market = 0.5 × depthFactor × volFactor (verify floor behavior)
- Verify with worked example from WP Section 8.8:
  - tau=6h, is_live=true → τ_eff=1.8h → R(1.8) ≈ 0.14
  - Match the table values exactly

## Testing Strategy
- Verify R(τ) against the full table in WP Section 8.5 (λ=2.0 column)
- Verify R_borrow(τ) against WP Section 15.2 table
- Verify parameter mappings produce correct values at R=0, R=0.5, R=1.0
- Fuzz: R(τ) is monotonically increasing with τ
- Fuzz: all parameter mappings are monotonic with R_adjusted
- Fuzz: M_market ∈ [0, WAD] for all valid inputs

