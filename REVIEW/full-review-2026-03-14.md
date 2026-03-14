# LEVER Protocol — Full Contract Review
**Date:** 2026-03-14
**Reviewer:** Claude Opus 4.6
**Scope:** All 16 contracts + 3 libraries vs SPEC/, FORMULAS.md, CONSTANTS.md

## Build Status
- **Compilation:** PASS (warnings only — safe typecasts, naming lint)
- **Tests:** 864/864 PASS across 19 test suites

---

## Severity Legend
| Level | Meaning |
|-------|---------|
| CRITICAL | Incorrect values deployed to chain; direct fund loss risk |
| HIGH | Logic bug affecting pricing, fees, or safety invariants |
| MEDIUM | Spec deviation, missing functionality, or design concern |
| LOW | Code quality, minor spec drift, or defense-in-depth gap |

---

## CRITICAL Issues (1)

### C1. OracleAdapter — CONSISTENCY_TOLERANCE is 5% instead of 2%
**File:** `contracts/core/OracleAdapter.sol:33`
**Expected:** `CONSISTENCY_TOLERANCE = 2e16` (2%) per CONSTANTS.md
**Actual:** `CONSISTENCY_TOLERANCE = 5e16` (5%)
**Impact:** Anti-manipulation validation is 2.5x looser than designed. Malicious oracle pushes with up to 5% deviation from smoothed price will pass validation instead of being rejected at 2%.

---

## HIGH Issues (5)

### H1. ExecutionEngine — OI increased BEFORE entry price computation
**File:** `contracts/ExecutionEngine.sol:161-163`
**Issue:** `oiLimits.increaseOI()` is called at line 161, then `_executeOpen()` (which calls `_computeExecutionPrice`) at line 163. The imbalance_delta calculation inside price computation reads from OILimits, but OI has already been updated to include the new position. This double-counts the trade's OI in the imbalance calculation.
**Spec:** Step 5 = OI cap check, Step 6 = entry price, Step 15 = OI increase.
**Fix:** Move `oiLimits.increaseOI()` after `_executeOpen()`, or split into `checkOI()` + `commitOI()`.

### H2. ExecutionEngine — closePosition missing TX fee collection
**File:** `contracts/ExecutionEngine.sol:313-327`
**Issue:** `_executeClose` does not call `feeRouter.collectTransactionFee()`. The spec requires TX_FEE (10 bps) on both open AND close.
**Impact:** 50% of transaction fee revenue is lost.

### H3. ExecutionEngine — closePosition missing market state check
**File:** `contracts/ExecutionEngine.sol:167-174`
**Issue:** No `_validateMarket()` call before closing. Positions can be closed during PENDING_RESOLUTION, which the spec explicitly prohibits.

### H4. FundingRateEngine — routeUnmatchedFunding is a no-op
**File:** `contracts/FundingRateEngine.sol:123-130`
**Issue:** Zeroes `_pendingUnmatchedFunding` and emits an event, but never calls `rewardsDistributor.receiveUnmatchedFunding(marketId, amount)`. The contract doesn't even import IRewardsDistributor.
**Impact:** Unmatched funding (LP revenue from imbalanced OI) is tracked but never routed. LPs lose this yield entirely.

### H5. AccountManager — debitPnL reverts instead of debiting available
**File:** `contracts/core/AccountManager.sol:112-119`
**Expected (spec):** `_balances[user] -= min(amount, _balances[user])` — debit what's available, let remainder become bad debt.
**Actual:** Reverts with `InsufficientBalance` if `amount > balance`.
**Impact:** LiquidationEngine and SettlementEngine will revert when processing losing positions where losses exceed user balance, blocking the liquidation/settlement flow.

---

## MEDIUM Issues (14)

### M1. RiskCurves — computeDepthFactor returns WAD for threshold=0 instead of reverting
**File:** `contracts/libraries/RiskCurves.sol:103`
**Spec says:** Revert on depthThreshold=0 (division by zero).
**Actual:** Returns WAD (1.0), masking misconfigured markets.

### M2. ProbabilityIndex — isNearBoundary uses <= / >= instead of < / >
**File:** `contracts/libraries/ProbabilityIndex.sol:58`
**Impact:** PI exactly equal to threshold is treated as "near boundary" when spec says it shouldn't be.

### M3. RiskCurves — mmMultiplier/imMultiplier/borrowMttR underflow if rAdjusted > WAD
**File:** `contracts/libraries/RiskCurves.sol:196,204,220`
**Issue:** `3e18 - rAdjusted.wadMul(2e18)` underflows if rAdjusted > 1.5e18. No input clamping.

### M4. MarketRegistry — Multiple role assignment mismatches vs spec
**File:** `contracts/core/MarketRegistry.sol:99,112,125,144,158`
- `resolveMarket` uses MARKET_MANAGER (spec: ORACLE)
- `activateMarket/setLive/setPendingResolution` use KEEPER (spec: MARKET_MANAGER/ORACLE)
- `voidMarket` uses MARKET_MANAGER (spec: ADMIN)

### M5. MarketRegistry — resolveMarket doesn't validate outcome is 0 or 1
**File:** `contracts/core/MarketRegistry.sol:140-155`
**Issue:** Accepts any uint8 value. Could accidentally set invalid outcome.

### M6. MarketRegistry — setLive doesn't revert when already live
**File:** `contracts/core/MarketRegistry.sol:112-121`
**Impact:** Silently resets liveStartTime, corrupting tau_effective downstream.

### M7. OracleAdapter — Volatility EMA formula differs from spec's SMA
**File:** `contracts/core/OracleAdapter.sol:326`
**Spec:** Simple moving average with N=20.
**Actual:** EMA with smoothing=0.10 (effective N~10).

### M8. BorrowFeeEngine — accrueIndex/accrueAll are permissionless
**File:** `contracts/BorrowFeeEngine.sol:112,117`
**Spec says:** KEEPER role required.

### M9. FundingRateEngine — accrueFunding/routeUnmatchedFunding are permissionless
**File:** `contracts/FundingRateEngine.sol:118,123`
**Spec says:** KEEPER role required.

### M10. FeeRouter — routeFees has no token pull from caller
**File:** `contracts/FeeRouter.sol:105`
**Issue:** Assumes USDT is already in the contract. No transferFrom. Fragile pattern.

### M11. MarginEngine — IM uses fixed 5% rate instead of notional/leverage
**File:** `contracts/MarginEngine.sol:37,426`
**Spec:** IM_base = notional / leverage. Implementation: IM_base = notional * 5%.
**Impact:** Under-margins positions below 20x leverage, over-margins above 20x.

### M12. MarginEngine — Missing PENDING_RESOLUTION 2x MM multiplier
**File:** `contracts/MarginEngine.sol`
**Spec:** PENDING_RESOLUTION_MM_MULT = 2.0x should be applied.

### M13. OILimits + ExecutionEngine — R_adjusted without M_market
**Files:** `contracts/OILimits.sol:272`, `contracts/ExecutionEngine.sol:427`
**Issue:** Both use R(tau) with M_market=1.0 to avoid circular dependency. OI caps and market depth are more permissive than spec intends under stress.

### M14. ExecutionEngine — Missing forceClose function
**File:** `contracts/ExecutionEngine.sol`
**Issue:** No forceClose for LiquidationEngine/SettlementEngine to call.

---

## Confirmed Correct (Key Invariants)

| Invariant | Status | Location |
|-----------|--------|----------|
| M_market applied TWICE in leverage pipeline | CORRECT | LeverageModel.sol:194,197 |
| imbalance_delta (not ratio) for execution impact | CORRECT | ExecutionEngine.sol:381-416 |
| Pincer effect (rising MM + borrow erosion) | CORRECT | MarginEngine.sol:361-389 |
| R(tau) with tau_ref=24h for mechanical curve | CORRECT | RiskCurves.sol |
| R_borrow(tau) with tau_ref=168h for borrow fees | CORRECT | RiskCurves.sol, BorrowFeeEngine.sol |
| Funding uses R(tau), not R_borrow(tau) | CORRECT | FundingRateEngine.sol:320 |
| Fee split 50/30/20 (LP/Protocol/Insurance) | CORRECT | FeeRouter.sol |
| All constants match CONSTANTS.md | CORRECT | All contracts (except C1) |

---

## Infrastructure Review
*(Pending — agent still running. Will be appended.)*
