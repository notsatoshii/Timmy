# LEVER Protocol — Spec Review & Formula Audit
**Date:** 2026-03-14
**Scope:** All 16 contracts + 3 libraries vs SPEC/*.md + KNOWLEDGE/FORMULAS.md

---

## Executive Summary

Audited all 19 Solidity implementations against their spec files and formula reference. Core math is overwhelmingly correct — the protocol's critical formulas (risk curves, equity, PnL, settlement payouts, fee splits, ADL haircuts) are faithfully implemented. The issues found are primarily in integration gaps (missing cross-contract calls), spec deviations (role assignments, constant values), and incomplete features (partial liquidation, utilization gates).

### Issue Counts

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 2 | Protocol safety mechanisms missing |
| MEDIUM | 19 | Formula deviations, missing logic, incomplete features |
| LOW | 18 | Spec deviations, dead code, minor inconsistencies |
| INFO | 15 | Documentation, cosmetic, non-functional |

---

## CRITICAL Issues

### C1. OracleAdapter: CONSISTENCY_TOLERANCE is 5% instead of 2%
**File:** `contracts/core/OracleAdapter.sol:33`
**Spec:** CONSTANTS.md says 2e16 (2%). Implementation uses 5e16 (5%).
**Impact:** Oracle pushes with up to 5% pYes+pNo deviation pass validation. A manipulated source could push inconsistent probabilities.

### C2. LeverVault: Missing utilization gate on withdrawal execution
**File:** `contracts/LeverVault.sol`
**Spec:** 16-LeverVault.md requires `postUtil <= MAX_UTIL_FOR_WITHDRAWAL (80%)` check before executing withdrawal.
**Impact:** LPs can withdraw even when vault is over-leveraged, enabling bank-run scenarios that leave insufficient backing for open positions. `getUtilization()` returns hardcoded `0`, `MAX_UTIL_FOR_WITHDRAWAL` is defined but never used.

---

## MEDIUM Issues

### Formulas & Math

**M1. MarginEngine: IM formula uses fixed 5% rate instead of `notional/leverage`**
`contracts/MarginEngine.sol:426` — Spec says `IM_base = notional / leverage`. Implementation uses `BASE_IM_RATE (5%) * notional`, making IM independent of leverage. At 2x leverage, spec says 50% IM but implementation gives 5%.

**M2. ExecutionEngine: OI incremented before price computation (double-counting)**
`contracts/ExecutionEngine.sol:161,163` — `oiLimits.increaseOI()` called before `_executeOpen()`, so imbalance_delta reads post-trade OI and adds the trade again, systematically worsening execution prices.

**M3. ExecutionEngine: First trade penalized with full imbalance delta**
`contracts/ExecutionEngine.sol` — When `totalOI == 0`, spec says `imbalance_delta = 0`. Implementation computes delta = WAD (100% worsening), tripling base impact for the first trader.

**M4. BorrowFeeEngine: `getAccruedFees` returns stale data**
`contracts/BorrowFeeEngine.sol` — Reads stored index without projecting to `block.timestamp`. Downstream contracts (MarginEngine) get incorrect equity unless `accrueIndex` was called in the same block.

### Missing Logic

**M5. MarginEngine: Missing PENDING_RESOLUTION 2x MM multiplier**
`contracts/MarginEngine.sol` — Spec says use 2.0x MM multiplier for markets in PENDING_RESOLUTION state. No code handles this.

**M6. MarginEngine: Only 5 of 10 spec'd validation steps implemented**
`contracts/MarginEngine.sol:250-287` — Missing: leverage cap check, OI capacity check, entry price preview, txFee deduction, post-fee MR floor check.

**M7. FundingRateEngine: `routeUnmatchedFunding` doesn't call RewardsDistributor**
`contracts/FundingRateEngine.sol:123-130` — Zeroes pending amount and emits event but never calls `RewardsDistributor.receiveUnmatchedFunding()`. No actual token routing.

**M8. ExecutionEngine: M_market omitted from market depth calculation**
`contracts/ExecutionEngine.sol:426-432` — Uses raw R(tau) without M_market adjustment. Volatile/concentrated/illiquid markets get same execution depth as ideal markets.

**M9. ExecutionEngine: No `forceClose` for liquidation/settlement**
`contracts/ExecutionEngine.sol` — Spec defines role-gated force-close. LiquidationEngine and SettlementEngine have no entry point to close through the execution pipeline.

**M10. LiquidationEngine: No execution impact on liquidation exit price**
`contracts/LiquidationEngine.sol` — Uses raw PI via MarginEngine equity instead of impact-adjusted exit price from ExecutionEngine. Liquidated traders get better pricing than intended.

**M11. LiquidationEngine: Partial liquidation is flag-only**
`contracts/LiquidationEngine.sol:319` — `isPartial` set but position always fully closed. `PARTIAL_LIQ_CHUNK` defined but unused.

**M12. SettlementEngine: Void settlement silently drops bad debt**
`contracts/SettlementEngine.sol:580-598` — Voided positions with negative equity (from borrow fees) create untracked bad debt. Never routed to insurance or socialization.

**M13. InsuranceFund: `absorbBadDebt` doesn't transfer USDT out**
`contracts/InsuranceFund.sol` — Decrements `_balance` but never calls `safeTransfer()`. Tokens remain stuck in the contract.

**M14. InsuranceFund: Bootstrap balance is accounting-only**
`contracts/InsuranceFund.sol` — Constructor sets `_balance = 10_000e18` but no USDT is deposited. Accounting says $10K but contract holds $0.

**M15. LeverVault: Pending yield lost on withdrawal**
`contracts/LeverVault.sol` — Spec says `totalPayout = assets + yield`. Implementation only pays assets. Tranches removed without harvesting yield.

**M16. LeverVault: No FIFO enforcement on withdrawal queue**
`contracts/LeverVault.sol` — Spec says "Strict FIFO. No queue-jumping." Implementation allows any mature receipt to execute regardless of queue position.

**M17. RewardsDistributor: Rewards when totalSupply=0 are permanently stranded**
`contracts/RewardsDistributor.sol` — Index doesn't increase when no shares exist. USDT sits in contract with no distribution mechanism.

**M18. OracleAdapter: Source registration system is dead code**
`contracts/core/OracleAdapter.sol:144-180` — `registerSource`, `removeSource`, etc. exist but are never consulted during `pushPrice`. Any ORACLE role holder can push regardless of source registration.

**M19. OracleAdapter: Volatility uses EMA instead of spec's SMA**
`contracts/core/OracleAdapter.sol:326` — Spec says SMA with N=20 window. Implementation uses EMA with alpha=0.10 (~10 effective window). Volatility responds faster than intended.

### Access Control Mismatches

**M20. MarketRegistry: 5 role mismatches vs spec**
`activateMarket`/`setLive` use KEEPER (spec: MARKET_MANAGER), `setPendingResolution` uses KEEPER (spec: ORACLE), `resolveMarket` uses MARKET_MANAGER (spec: ORACLE), `voidMarket` uses MARKET_MANAGER (spec: ADMIN). ORACLE role absent entirely.

**M21. AccountManager: `debitPnL` reverts instead of debiting available**
`contracts/core/AccountManager.sol:115-116` — Spec says "debit what's available, loss is bad debt." Implementation reverts with `InsufficientBalance`, potentially blocking liquidation/settlement flows.

---

## LOW Issues

| # | Contract | Issue |
|---|----------|-------|
| L1 | OracleAdapter | freeze/unfreeze uses KEEPER instead of ADMIN |
| L2 | OracleAdapter | `removeSource` doesn't clean up `_sourceAddresses` array (unbounded gas growth) |
| L3 | OracleAdapter | `registerSource` allows duplicate registration |
| L4 | MarketRegistry | `setLive` doesn't revert when already live (overwrites `liveStartTime`) |
| L5 | MarketRegistry | `resolveMarket` doesn't validate outcome is 0 or 1 |
| L6 | AccountManager | Missing events for lock/release/credit/debit operations |
| L7 | AccountManager/PositionManager | Single ENGINE role instead of 3 spec'd roles |
| L8 | PositionManager | `closePosition` removes from arrays (spec says don't) |
| L9 | OILimits | M_market always 1.0 for OI cap computation |
| L10 | OILimits | `decreaseOI` error message misleading |
| L11 | BorrowFeeEngine | `accrueIndex`/`accrueAll` lack KEEPER role access control |
| L12 | BorrowFeeEngine | `nonReentrant` not applied to state-changing functions |
| L13 | FundingRateEngine | `accrueFunding`/`routeUnmatchedFunding` lack KEEPER role check |
| L14 | FundingRateEngine | Event signature has longIndex/shortIndex but both set to same value |
| L15 | LeverageModel | `Pausable` inherited but never used (dead code) |
| L16 | ExecutionEngine | No TX fee collected on close |
| L17 | ExecutionEngine | No market state validation on close (allows close during PENDING_RESOLUTION) |
| L18 | SettlementEngine | `MarketSettled` event emits `totalBadDebt` for both loserDebt and badDebt params |

---

## INFO Issues

| # | Contract | Issue |
|---|----------|-------|
| I1 | FixedPointMath | `WAD_SQUARED` unused |
| I2 | RiskCurves | Redundant floor check in `computeConcentrationFactor` |
| I3 | ProbabilityIndex | `isNearBoundary` uses non-strict inequalities vs spec |
| I4 | OracleAdapter | No per-category default smoothing params (spec defines 4 tiers) |
| I5 | OracleAdapter | Convergence enforcement not implemented (spec says SHOULD) |
| I6 | MarketRegistry | activateMarket/setLive emit same event (MarketLive) |
| I7 | PositionManager | `UnauthorizedCaller` error defined but never used |
| I8 | LeverageModel | `PlatformCeilingUpdated` event declared but never emitted |
| I9 | BorrowFeeEngine | `BorrowFeesAccrued` event declared but never emitted |
| I10 | BorrowFeeEngine | `getAnnualizedRate` uses simple multiplication (not compounding) |
| I11 | FundingRateEngine | Risk params stored locally, not pulled live (can be stale) |
| I12 | FundingRateEngine | Spec says multiplier range "1x-5x" but formula gives 1x-4x |
| I13 | InsuranceFund | Unused interface errors (DailyCapExceeded, FloorBreached, InsufficientFunds) |
| I14 | LeverVault | `weightedAge()` is a stub (returns tranche count) |
| I15 | LeverVault | `compound()` bypasses ERC-4626 deposit flow |

---

## Contracts With Clean Bills

These contracts had **no CRITICAL or MEDIUM issues** — formulas, constants, and logic all match spec:

- **FixedPointMath** — All WAD math correct
- **RiskCurves** — All risk curve formulas correct (1 MEDIUM on depthFactor=0 handling)
- **ProbabilityIndex** — Validation and PnL correct
- **LeverageModel** — 3-step pipeline with double M_market correctly implemented
- **FeeRouter** — 50/30/20 split, tier logic, TX fee all correct

---

## Integration Test Gap Analysis (Top 10)

| Priority | Gap | Risk |
|----------|-----|------|
| 1 | **No actual `liquidate()` call tested** — only `isLiquidatable()` checked | Full liquidation waterfall untested |
| 2 | **No SettlementEngine integration** — never deployed or called | Settlement payouts, fees, ADL untested |
| 3 | **Insurance exhaustion -> LP socialization never tested end-to-end** | Bad debt waterfall untested with real contracts |
| 4 | **ADL (Auto-Deleveraging) completely missing** | Critical safety mechanism untested |
| 5 | **No RewardsDistributor claim flow tested** | Fee -> FeeRouter -> RewardsDistributor -> LP claim untested |
| 6 | **All core tests use MockFeeRouter** | Real 50/30/20 split never tested cross-contract |
| 7 | **No withdrawal under high utilization** | 80% gate untested (also unimplemented per C2) |
| 8 | **No fee accrual near resolution (tau->0)** | M_ttR spike to 25x, leverage compression untested |
| 9 | **No void market with open positions** | Position refund/void handling untested |
| 10 | **No cascading liquidations** | Liquidation -> price impact -> more liquidations untested |

---

## Recommendations

### Immediate (Pre-Testnet)
1. Fix C1 (CONSISTENCY_TOLERANCE 5% -> 2%)
2. Fix C2 (implement utilization gate on withdrawals)
3. Fix M2 (move OI increment after price computation)
4. Fix M3 (return 0 imbalance_delta when totalOI=0)
5. Fix M21 (debitPnL should debit available, not revert)

### High Priority
6. Fix M4 (use `computeIndexAt(block.timestamp)` in `getAccruedFees`)
7. Fix M7 (actually call RewardsDistributor from FundingRateEngine)
8. Fix M13/M14 (InsuranceFund token transfer + bootstrap deposit)
9. Implement M5 (PENDING_RESOLUTION MM multiplier)
10. Write integration tests for gaps #1-4

### Should Fix
11. Fix M1 (IM formula to use notional/leverage)
12. Implement M10 (execution impact on liquidation)
13. Fix M15/M16 (yield on withdrawal, FIFO queue)
14. Resolve access control mismatches (M20, L1, L7, L11, L13)
15. Add missing events (L6)
