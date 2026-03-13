# SPEC: LeverageModel

## Purpose
Three-step pipeline computing Effective_Max_Leverage for any market at any time.
Step 1: Platform Ceiling (TVL × IFR × utilization). Step 2: Compress by R_adjusted. Step 3: Compress AGAIN by M_market. M_market is intentionally applied twice — it already lives inside R_adjusted, and is applied again here because leverage is the most dangerous parameter.

## Dependencies
- RiskCurves (R, M_market, parameter mappings)
- FixedPointMath
- ILeverVault (TVL)
- IInsuranceFund (IFR)
- IOILimits (global utilization)
- IMarketRegistry (τ, is_live, for passing to RiskCurves)

## Build Priority
Phase 3 — Risk & Leverage.

## Access Control
- All functions are view/pure — no state changes, no access control needed.

## Constants
```solidity
uint256 constant BASE_MAX = 30e18;           // 30×
uint256 constant TVL_MATURITY = 50_000_000e18; // $50M
uint256 constant TVL_MULT_FLOOR = 1e17;      // 0.10
uint256 constant IFR_TARGET = 2e17;          // 0.20
uint256 constant IFR_MULT_FLOOR = 4e17;      // 0.40
uint256 constant UTIL_THRESHOLD = 3e17;      // 0.30
uint256 constant UTIL_MULT_FLOOR = 3e17;     // 0.30
uint256 constant UTIL_SLOPE = 7e17;          // 0.70
uint256 constant UTIL_RANGE = 7e17;          // 0.70
uint256 constant MIN_LEVERAGE = 1e18;        // 1× floor
```

## Step 1: Platform Ceiling
```
TVL_Mult = min(WAD, max(TVL_MULT_FLOOR, wadSqrt(TVL × WAD / TVL_MATURITY)))

IFR = InsuranceFund.getBalance() × WAD / LeverVault.totalAssets()
IFR_Mult = min(WAD, max(IFR_MULT_FLOOR, IFR_MULT_FLOOR + (WAD - IFR_MULT_FLOOR) × IFR / IFR_TARGET))
  // Simplifies to: min(1.0, max(0.40, 0.40 + 0.60 × IFR/0.20))

U_global = OILimits.getGlobalUtilization()
Util_Mult = max(UTIL_MULT_FLOOR, WAD - UTIL_SLOPE × max(0, U_global - UTIL_THRESHOLD) / UTIL_RANGE)

Platform_Ceiling = BASE_MAX × TVL_Mult / WAD × IFR_Mult / WAD × Util_Mult / WAD
```

## Step 2: Risk Factor Compression
```
// Get R_adjusted for this market (already includes M_market once)
tauEff = RiskCurves.computeTauEffective(MarketRegistry.getTau(marketId), MarketRegistry.isLive(marketId))
r = RiskCurves.computeR(tauEff)
mMarket = RiskCurves.computeMarketAdjustment(...)  // needs sigma, depth, OI data
rAdj = RiskCurves.computeRAdjusted(r, mMarket)

Compressed = Platform_Ceiling × rAdj / WAD
```

## Step 3: Market-Specific Adjustment (SECOND M_market)
```
Market_Adjustment = mMarket    // Same value, applied AGAIN
Effective_Max = max(MIN_LEVERAGE, Compressed × Market_Adjustment / WAD)
```

**CRITICAL: The double application is intentional (WP Section 9.9).** Market stress compounds on leverage. Do NOT simplify to single application.

## Worked Example (verify against WP Section 9.10)
Platform: TVL=$10M, IFR=6%, U_global=40%, Base=30×
Market: τ=4h, is_live=true, high volatility (Vol_Factor=0.7), thin depth (Depth_Factor=0.8), C=0.10 (Conc_Factor=1.0)

```
TVL_Mult = sqrt(10M/50M) = 0.447
IFR_Mult = max(0.40, 0.40 + 0.60 × 0.06/0.20) = 0.58
Util_Mult = max(0.30, 1.0 - 0.70 × max(0, 0.40-0.30)/0.70) = 0.90

Ceiling = 30 × 0.447 × 0.58 × 0.90 = 7.0×

τ_eff = 4 × 0.30 = 1.2h
R(1.2) = 1 - e^(-2×1.2/24) = 1 - e^(-0.1) = 0.095
M_market = min(1.0, 0.7 × 0.8 × 1.0) = 0.56
R_adjusted = 0.095 × 0.56 = 0.053

Compressed = 7.0 × 0.053 = 0.37×
Step 3 = max(1.0, 0.37 × 0.56) = max(1.0, 0.21) = 1.0×
```
Result: 1× (no leverage). Correct for a live event 4h out on a stressed platform.

## Edge Cases
- TVL = 0 → TVL_Mult = floor (0.10). Platform still works at 3×.
- Insurance = 0 → IFR = 0 → IFR_Mult = floor (0.40)
- Resolution (τ=0) → R=0 → Compressed=0 → Effective=1× (floor)
- All factors at 1.0 → full 30× available
- U_global > 100% (shouldn't happen but defensive) → Util_Mult = floor

