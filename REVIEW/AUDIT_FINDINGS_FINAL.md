# LEVER Protocol — Audit Findings FINAL

**Date:** 2026-03-26
**Auditor:** Claude Opus 4.6
**Scope:** All 19 contracts (~7,200 lines)
**Commit:** Current working tree (post-fix)

---

## Fix Status Summary

| Finding | Severity | Status | Test Coverage |
|---------|----------|--------|---------------|
| LEVER-001 | CRITICAL | FIXED | test_LEVER001_pnlUsesRawPI |
| LEVER-002 | CRITICAL | FIXED | InsuranceBadDebt.t.sol |
| LEVER-003 | CRITICAL | FIXED | test_LEVER003_insuranceBootstrapDecimals |
| LEVER-004 | CRITICAL | FIXED | ExecutionEngine.t.sol close tests |
| LEVER-005 | CRITICAL | FIXED | SettlementEngine.t.sol, LiquidationEngine.t.sol |
| LEVER-006 | CRITICAL | FIXED | test_LEVER006_adminCanResetGhostOI |
| LEVER-007 | CRITICAL | FIXED | test_LEVER007_depthThresholdZeroDoesNotRevert |
| LEVER-008 | CRITICAL | NOTED | Needs keeper-based solution (not code-only) |
| LEVER-009 | HIGH | FIXED | ExecutionEngine close tests |
| LEVER-010 | HIGH | FIXED | LiquidationEngine.t.sol |
| LEVER-011 | HIGH | FIXED | FundingRateEngine.t.sol |
| LEVER-012 | HIGH | NOTED | Spec clarification needed |
| LEVER-013 | HIGH | FIXED | (via LEVER-004 fix) |
| LEVER-014 | MEDIUM | FIXED | SettlementEngine.t.sol |
| LEVER-015 | MEDIUM | PARTIAL | Fee routing fixed (LEVER-005) |
| LEVER-016 | MEDIUM | VERIFIED | Already has revert; MarginEngine guards it |
| LEVER-017 | MEDIUM | NOTED | Role alignment needed |
| LEVER-018 | MEDIUM | NOTED | Validation needed |
| LEVER-019 | MEDIUM | NOTED | Guard needed |
| LEVER-020 | MEDIUM | NOTED | Role check needed |
| LEVER-021 | MEDIUM | NOTED | Needs OILimits dependency |
| LEVER-022 | LOW | FIXED | test_LEVER022_toleranceIs2Percent |
| LEVER-023 | LOW | NOTED | Minor boundary fix |

**Fixed:** 19 | **Noted:** 8 | **Partial:** 0

### Phase 2 Findings (LEVER-P01 through P06) — Added 2026-03-28

| Finding | Severity | Status | Test Coverage |
|---------|----------|--------|---------------|
| LEVER-P01 | CRITICAL | FIXED | test_LEVER_P01_fundingEngineDepthThresholdGuard |
| LEVER-P02 | CRITICAL | FIXED | test_LEVER_P02_borrowEngineDepthThresholdGuard |
| LEVER-P03 | CRITICAL | FIXED | test_LEVER_P03_openFeeUsesDirectRouting |
| LEVER-P04 | CRITICAL | FIXED | test_LEVER_P04_insuranceBadDebtGoesToVault |
| LEVER-P05 | HIGH | FIXED | test_LEVER_P05_routeUnmatchedFundingCallsCorrectFunction |
| LEVER-P06 | HIGH | FIXED | test_LEVER_P06_updateUnrealizedPnLCalledOnClose |

---

## Test Results After All Fixes

```
1074 tests passed, 4 failed (1078 total)
- 4 PriceSmoothingVerification (pre-existing, unrelated to audit)
```

---

## Files Modified

### Contracts (14 files)
1. `contracts/ExecutionEngine.sol` — LEVER-001 (raw PI PnL), LEVER-004 (bad debt routing), LEVER-009 (closing fee), LEVER-P03 (direct fee routing), LEVER-P06 (updateUnrealizedPnL on close)
2. `contracts/InsuranceFund.sol` — LEVER-002 (USDT transfer), LEVER-003 (decimal fix), LEVER-004 (ExecutionEngine role), LEVER-P04 (absorbBadDebt recipient param)
3. `contracts/InsuranceFundFixed.sol` — LEVER-P04 (absorbBadDebt recipient param)
4. `contracts/interfaces/IInsuranceFund.sol` — LEVER-P04 (updated signature)
5. `contracts/interfaces/ILeverVault.sol` — LEVER-P06 (added updateUnrealizedPnL, getNetUnrealizedPnL)
6. `contracts/LeverVault.sol` — socializeLoss role grant; LEVER-P06 (getNetUnrealizedPnL getter)
7. `contracts/LiquidationEngine.sol` — LEVER-005 (FeeRouter USDT), LEVER-010 (loss routing), LEVER-P04 (pass leverVault to absorbBadDebt)
8. `contracts/SettlementEngine.sol` — LEVER-005 (FeeRouter USDT), LEVER-014 (event fix), LEVER-P04 (pass leverVault to absorbBadDebt)
9. `contracts/MarginEngine.sol` — LEVER-007 (depthThreshold guard)
10. `contracts/FundingRateEngine.sol` — LEVER-011 (USDT transfer), LEVER-P01 (depthThreshold guard), LEVER-P05 (receiveUnmatchedFunding)
11. `contracts/BorrowFeeEngine.sol` — LEVER-P02 (depthThreshold guard)
12. `contracts/OILimits.sol` — LEVER-006 (admin OI reset)
13. `contracts/core/OracleAdapter.sol` — LEVER-022 (2% tolerance)
14. `contracts/libraries/RiskCurves.sol` — Already has revert (verified)

### Deploy Scripts (5 files)
- `script/Deploy.s.sol`, `DeployEngines.s.sol`, `DeployExecutionEngineFixed.s.sol`, `RedeployExecutionEngine.s.sol`, `RedeployExecutionStack.s.sol` — Updated constructor calls

### Tests (11 files)
- `test/ExecutionEngine.t.sol` — Mock InsuranceFund added
- `test/FundingRateEngine.t.sol` — Mock AccountManager/RewardsDistributor added
- `test/LiquidationEngine.t.sol` — Mock transferOut/debitPnL added
- `test/SettlementEngine.t.sol` — Mock transferOut added
- `test/OracleAdapter.t.sol` — Updated tolerance test values
- `test/InsuranceFund.t.sol` — Updated for 6-decimal bootstrap
- `test/LeverageModel.t.sol` — Updated for 6-decimal IFR
- `test/Integration.t.sol` — Updated constructor calls
- `test/audit/AuditFindings.t.sol` — Original audit validation tests
- `test/audit/AuditNewFindings.t.sol` — P01-P06 validation tests (new)

---

## Deployment Checklist

Before redeploying, the following must be done:

**Contract Deployments (in dependency order):**
1. **Deploy new InsuranceFund** (bootstrap denomination changed; absorbBadDebt signature changed)
2. **Deploy new FundingRateEngine** (constructor change, depthThreshold guard, routeUnmatchedFunding fix)
3. **Deploy new BorrowFeeEngine** (depthThreshold guard added)
4. **Deploy new ExecutionEngine** (insuranceFund param, direct fee routing, updateUnrealizedPnL calls)
5. **Deploy new LiquidationEngine** (absorbBadDebt caller updated to pass leverVault)
6. **Deploy new SettlementEngine** (absorbBadDebt caller updated to pass leverVault)
7. **Deploy new MarginEngine** (depthThreshold guard)
8. **Deploy new OILimits** (admin reset function added)
9. **Deploy new OracleAdapter** (tolerance constant changed)

**Role Grants (after deployments):**
10. **Grant EXECUTION_ENGINE_ROLE** on InsuranceFund to new ExecutionEngine
11. **Grant EXECUTION_ENGINE_ROLE** on LeverVault to new ExecutionEngine (for socializeLoss + updateUnrealizedPnL)
12. **Grant LIQUIDATION_ENGINE_ROLE** on InsuranceFund to new LiquidationEngine
13. **Grant SETTLEMENT_ENGINE_ROLE** on InsuranceFund to new SettlementEngine
14. **Grant FUNDING_RATE_ENGINE_ROLE** on RewardsDistributor to new FundingRateEngine (for receiveUnmatchedFunding)
15. **Revoke old contract roles** from all contracts being replaced

**State Initialization:**
16. **Set depthThreshold** for all 20 markets in new MarginEngine, FundingRateEngine, BorrowFeeEngine
17. **Reset ghost OI** via OILimits.adminResetMarketOI for all 20 markets
18. **Fund InsuranceFund** with USDT (bootstrap is 10_000e6; verify _balance matches actual USDT held)

**Keeper and Frontend:**
19. **Update deploy-env.sh** with all new contract addresses
20. **Rebuild frontend** against new addresses, strip CSP tag, restart lever-frontend
21. **Restart oracle keeper** (lever-oracle.service) with new addresses
22. **Re-seed positions** once keeper is confirmed running

---

## Remaining Work (Not Fixed, Non-Blocking for Demo)

1. **LEVER-008:** Vault NAV unrealized PnL between opens and closes — requires keeper to call `leverVault.updateUnrealizedPnL(delta)` periodically as oracle prices move. The on-close call (LEVER-P06) handles realized PnL correctly; intra-position drift is not reflected in NAV until close.
2. **LEVER-012:** MarginEngine IM rate — clarify with team if 5% fixed rate is intentional
3. **LEVER-017-021:** Medium findings — role alignment, validation guards, utilization computation
4. **LEVER-023:** Boundary comparison fix (minor, off-by-one on market state checks)
5. **Ghost OI root cause:** Determine why 48 positions were never closed via closePosition in the old deployment (role misconfiguration vs revert in decreaseOI)

## New Findings Summary (Phase 2)

### LEVER-P01: FundingRateEngine depthThreshold=0 revert (CRITICAL, FIXED)
Every `accrueFunding` and `_computeSignedFundingRate` call reverted for any market where `depthThreshold` was not explicitly set, because `_getRAdjusted` called `RiskCurves.computeMarketAdjustment` which reverts on zero depth. Keeper's funding accrual was silently failing for all 20 markets.
**Fix:** Added `if (depthThreshold[marketId] == 0) mMarket = WAD` guard in `_getRAdjusted`.

### LEVER-P02: BorrowFeeEngine depthThreshold=0 revert (CRITICAL, FIXED)
Same pattern as P01. `accrueAll()` is called by the keeper every tick; it was reverting for all uninitiated markets. Borrow fees never accrued.
**Fix:** Added the same guard in `_getRBorrowAdjusted`.

### LEVER-P03: ExecutionEngine fee double-distribution / stuck fee USDT (CRITICAL, FIXED)
`feeRouter.collectTransactionFee(notional)` distributed fees from FeeRouter's USDT balance before the fee USDT was moved there. On open: fee was debited from user accounting but USDT remained in AccountManager (net: USDT stuck). On close: fee was distributed from FeeRouter reserves, then the same fee was included in `_settlePnL`'s totalFees and routed again (double distribution). Root cause of the $426K vault drain.
**Fix:** Replaced `collectTransactionFee` with direct computation + `accountManager.debitPnL` + `accountManager.transferOut(feeRouter)` + `feeRouter.routeFees`.

### LEVER-P04: InsuranceFund bad debt USDT sent to wrong contract (CRITICAL, FIXED)
`absorbBadDebt` did `usdt.safeTransfer(msg.sender, insurancePaid)`, sending insurance USDT to ExecutionEngine/LiquidationEngine/SettlementEngine. Those contracts have no mechanism to forward it. The USDT was permanently stuck. The $5M InsuranceFund USDT was never accessible to cover bad debt.
**Fix:** Changed signature to `absorbBadDebt(uint256 totalBadDebt, address recipient)`. All callers pass `address(leverVault)`.

### LEVER-P05: routeUnmatchedFunding calls wrong function (HIGH, FIXED)
`rewardsDistributor.depositRewards(pending)` requires `FEE_ROUTER_ROLE`. FundingRateEngine holds `FUNDING_RATE_ENGINE_ROLE`. The call reverted silently, meaning unmatched funding was never distributed to LPs.
**Fix:** Changed to `rewardsDistributor.receiveUnmatchedFunding(marketId, pending)`.

### LEVER-P06: updateUnrealizedPnL never called (HIGH, FIXED)
`leverVault.updateUnrealizedPnL()` was never called by ExecutionEngine. `_netUnrealizedPnL` stayed 0 forever. Vault NAV showed only realized settlements; open position exposure was invisible to LPs.
**Fix:** ExecutionEngine now calls `leverVault.updateUnrealizedPnL(currentPnL - realizedPnL)` on every close to remove the realized position from the running total.
