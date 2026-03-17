# Leverage Model Debug Report — 2026-03-17

## Problem Statement
LeverageModel.getEffectiveMaxLeverage() returns 1.0x for SpaceX market when it should return ~25-30x based on mathematical analysis.

**Expected:** SpaceX expires Dec 2026 = ~288 days = ~6912 hours from now
τ_effective = 6912 * (1 - 0.70 * is_live) = 6912 * 0.30 = 2073 hours
R(τ) = 1 - e^(-2.0 * 2073 / 24) = 1 - e^(-172) = ~1.0
At R(τ)=1.0, leverage compression should be minimal → ~25-30x max leverage

**Actual:** LeverageModel returns exactly 1.0x leverage

## On-Chain Debug Results

### Market Information
- **SpaceX Market ID:** 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1
- **Name:** "Largest IPO by Market Cap 2026: SpaceX?"
- **Resolution Time:** 1798588800 (Dec 30, 2026)
- **Market State:** ACTIVE

### Step-by-Step Analysis

#### Step 1: Platform Ceiling Components
```
BASE_MAX = 30e18 (30x leverage)
Platform Ceiling = BASE_MAX × TVL_Mult × IFR_Mult × Util_Mult
```

**Results:**
- TVL_Multiplier: 100000000000000000 WAD = **0.1x** ⚠️
- IFR_Multiplier: 1000000000000000000 WAD = **1.0x** ✅
- Util_Multiplier: 1000000000000000000 WAD = **1.0x** ✅
- **Platform Ceiling: 3000000000000000000 WAD = 3.0x**

#### Step 2: Risk Curve Compression
- Compressed Leverage: 4662624297017640 WAD = **~0.0047x**
- This represents: 3.0x × R_adjusted

#### Step 3: Market Adjustment (M_market second application)
- Market Adjustment: 1554208099005880 WAD = **~0.00155x**
- **Final Max Leverage: 1000000000000000000 WAD = 1.0x** (floored at MIN_LEVERAGE)

## ROOT CAUSE: Decimal Format Mismatch

**The critical bug is in TVL handling:**

1. **LeverVault.totalAssets()** returns: 60504028315742
   - This is USDT format (6 decimals) = 60.5M USDT ✅

2. **LeverageModel expects WAD format (18 decimals)**
   - Formula: `TVL_Mult = min(1.0, max(0.10, sqrt(TVL / TVL_MATURITY)))`
   - TVL_MATURITY = 50,000,000e18 (50M in WAD)

3. **What happens:**
   - LeverageModel treats 60504028315742 as WAD
   - This equals 0.00006 WAD (essentially zero)
   - Since TVL appears to be ~0, it uses TVL_MULT_FLOOR = 0.10
   - sqrt(0 / 50M) = 0 → clamped to minimum 0.10x

4. **What should happen:**
   - Convert: 60504028315742 USDT → 60,504,028,315,742,000,000,000,000 WAD
   - Ratio: 60.5M / 50M = 1.21
   - sqrt(1.21) = 1.1 → clamped to max 1.0x
   - TVL_Mult should be **1.0x** not 0.1x

## Impact Analysis

With the bug:
- Platform Ceiling: 30x × **0.1x** × 1.0x × 1.0x = 3.0x
- After risk compression: 3.0x × very_small_R_adj = ~0.0047x
- After market adjustment: ~0.0047x × very_small_M_market = **1.0x (floored)**

With the fix:
- Platform Ceiling: 30x × **1.0x** × 1.0x × 1.0x = 30x
- After risk compression: 30x × R_adj (should be ~0.8-1.0 for far-future markets)
- After market adjustment: Should yield **20-30x** max leverage

## Recommended Fix

The LeverageModel needs to handle the decimal conversion between USDT (6 decimals) and WAD (18 decimals) format when reading TVL from the vault.

**Option 1:** Modify LeverageModel to scale vault.totalAssets() by 1e12
**Option 2:** Make LeverVault.totalAssets() return WAD format
**Option 3:** Add a conversion layer/adapter

This single bug is blocking all realistic leverage trading, market maker operations, and proper fee generation across the entire protocol.