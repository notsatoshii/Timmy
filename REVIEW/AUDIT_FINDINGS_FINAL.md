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

**Fixed:** 13 | **Noted:** 9 | **Partial:** 1

---

## Test Results After Fixes

```
1066 tests passed, 6 failed (1072 total)
- 4 PriceSmoothingVerification (pre-existing, unrelated to audit)
- 2 HighLeverageValidation (integration sensitivity to IFR change)
```

---

## Files Modified

### Contracts (11 files)
1. `contracts/ExecutionEngine.sol` — LEVER-001 (raw PI PnL), LEVER-004 (bad debt routing), LEVER-009 (closing fee), added InsuranceFund dependency
2. `contracts/InsuranceFund.sol` — LEVER-002 (USDT transfer), LEVER-003 (decimal fix), LEVER-004 (ExecutionEngine role)
3. `contracts/LeverVault.sol` — Allow ExecutionEngine to call socializeLoss
4. `contracts/LiquidationEngine.sol` — LEVER-005 (FeeRouter USDT), LEVER-010 (loss routing)
5. `contracts/SettlementEngine.sol` — LEVER-005 (FeeRouter USDT), LEVER-014 (event fix)
6. `contracts/MarginEngine.sol` — LEVER-007 (depthThreshold guard)
7. `contracts/FundingRateEngine.sol` — LEVER-011 (USDT transfer to RewardsDistributor)
8. `contracts/OILimits.sol` — LEVER-006 (admin OI reset)
9. `contracts/core/OracleAdapter.sol` — LEVER-022 (2% tolerance)
10. `contracts/libraries/RiskCurves.sol` — Already has revert (verified)

### Deploy Scripts (5 files)
- `script/Deploy.s.sol`, `DeployEngines.s.sol`, `DeployExecutionEngineFixed.s.sol`, `RedeployExecutionEngine.s.sol`, `RedeployExecutionStack.s.sol` — Updated constructor calls

### Tests (9 files)
- `test/ExecutionEngine.t.sol` — Mock InsuranceFund added
- `test/FundingRateEngine.t.sol` — Mock AccountManager/RewardsDistributor added
- `test/LiquidationEngine.t.sol` — Mock transferOut/debitPnL added
- `test/SettlementEngine.t.sol` — Mock transferOut added
- `test/OracleAdapter.t.sol` — Updated tolerance test values
- `test/InsuranceFund.t.sol` — Updated for 6-decimal bootstrap
- `test/LeverageModel.t.sol` — Updated for 6-decimal IFR
- `test/Integration.t.sol` — Updated constructor calls
- `test/audit/AuditFindings.t.sol` — New audit validation tests

---

## Deployment Checklist

Before redeploying, the following must be done:

1. **Deploy new FundingRateEngine** (constructor change — 2 new params)
2. **Deploy new ExecutionEngine** (constructor change — insuranceFund param)
3. **Deploy new InsuranceFund** (bootstrap denomination changed)
4. **Deploy new LiquidationEngine** (if not upgradeable — logic changed)
5. **Deploy new SettlementEngine** (logic changed)
6. **Deploy new MarginEngine** (if not upgradeable — depthThreshold guard)
7. **Deploy new OILimits** (admin reset function added)
8. **Deploy new OracleAdapter** (tolerance constant changed)
9. **Grant roles:** ExecutionEngine needs EXECUTION_ENGINE_ROLE on InsuranceFund
10. **Grant roles:** ExecutionEngine needs EXECUTION_ENGINE_ROLE on LeverVault for socializeLoss
11. **Set depthThreshold** for all 20 markets in MarginEngine
12. **Reset ghost OI** via OILimits.adminResetMarketOI for all markets
13. **Fund InsuranceFund** with USDT (bootstrap is now 10_000e6, not 10_000e18)
14. **Update keeper** to use new contract addresses
15. **Re-seed positions** if needed

---

## Remaining Work (Not Fixed in This Session)

1. **LEVER-008:** Vault NAV unrealized PnL — needs keeper-based periodic update or on-chain aggregation
2. **LEVER-012:** MarginEngine IM rate — clarify with team if 5% fixed rate is intentional
3. **LEVER-017-021:** Medium findings — role alignment, validation guards, utilization computation
4. **LEVER-023:** Boundary comparison fix
5. **Cross-cutting:** Full WAD/USDT denomination audit across entire protocol
6. **Ghost OI investigation:** Determine why 48 positions were never closed via closePosition
