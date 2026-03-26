# LEVER Protocol — Audit Findings V1

**Date:** 2026-03-25
**Auditor:** Claude Opus 4.6
**Scope:** All 19 contracts (~7,200 lines)
**Commit:** Current HEAD on Base Sepolia testnet deployment

---

## Severity Legend

| Level | Meaning |
|-------|---------|
| **CRITICAL** | Direct fund loss, systematic bias, or complete feature failure |
| **HIGH** | Material revenue loss, incorrect accounting, or blocked functionality |
| **MEDIUM** | Spec deviation, missing guards, or design concern |
| **LOW** | Code quality, minor spec drift, or defense-in-depth gap |

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 8 |
| HIGH | 5 |
| MEDIUM | 8 |
| LOW | 2 |
| **Total** | **23** |

---

## CRITICAL Findings

### LEVER-001: PnL Formula Mismatch Between ExecutionEngine and MarginEngine/SettlementEngine

**Severity:** CRITICAL
**Contract:** ExecutionEngine.sol, MarginEngine.sol, SettlementEngine.sol
**Location:** ExecutionEngine:528-537, MarginEngine:366-370, SettlementEngine:528-531

**Description:**
ExecutionEngine._computePnL computes PnL using impact-adjusted prices (entryPrice, exitPrice), while MarginEngine._computeEquity and SettlementEngine._computePositionSettlement compute PnL using raw PI values (entryPI, currentPI/piOutcome).

**Expected (FORMULAS.md §6):**
```
PnL = direction × (PI_current - PI_entry) × position_size
```
PnL should use raw PI values consistently across all contracts.

**Actual:**
- ExecutionEngine line 348: `_computePnL(pos.isLong, exitPrice, pos.entryPrice, pos.positionSize)`
  - exitPrice = PI × (1 ± impact), entryPrice = PI × (1 ± impact)
- MarginEngine line 369: `int256(currentPI) - int256(pos.entryPI)`
  - Uses raw PI values
- SettlementEngine line 529: `int256(piOutcome) - int256(pos.entryPI)`
  - Uses raw PI values

**Impact:**
- Equity calculations disagree across contracts → liquidation checks use different PnL than settlement
- Impact spreads create systematic PnL bias — 38 winners, 0 losers observed on-chain
- Vault drains without corresponding insurance absorption
- Estimated loss contribution: significant portion of the $426K vault drain

**Fix:**
In ExecutionEngine._executeClose, compute PnL using raw PI values to match MarginEngine:
```solidity
int256 pnl = _computePnL(pos.isLong, pi, pos.entryPI, pos.positionSize);
```
Keep impact-adjusted pricing for entry/exit price display in events only.

---

### LEVER-002: InsuranceFund.absorbBadDebt Never Transfers USDT

**Severity:** CRITICAL
**Contract:** InsuranceFund.sol
**Location:** InsuranceFund:113-183

**Description:**
`absorbBadDebt()` decrements the internal `_balance` accounting variable and emits events, but never actually transfers USDT to cover the bad debt. The function is pure bookkeeping — no `usdt.safeTransfer()` call.

**Expected:**
When insurance absorbs bad debt, it should transfer USDT to the caller (or designated recipient) to cover the shortfall.

**Actual:**
- Line 177: `_balance -= insurancePaid;` — accounting only
- No USDT transfer to LiquidationEngine, SettlementEngine, or LeverVault
- The $5M USDT sitting in InsuranceFund contract is untouched

**Impact:**
Bad debt is never actually covered. Insurance fund appears to work (events emitted, balances decremented) but no real money moves. Losses fall entirely on LP vault.

**Fix:**
Add USDT transfer to the caller after computing `insurancePaid`:
```solidity
if (insurancePaid > 0) {
    usdt.safeTransfer(msg.sender, insurancePaid);
}
```
Note: amounts need WAD→USDT decimal conversion (see LEVER-003).

---

### LEVER-003: InsuranceFund WAD/USDT Decimal Mismatch

**Severity:** CRITICAL
**Contract:** InsuranceFund.sol
**Location:** InsuranceFund:35, InsuranceFund:92, InsuranceFund:107

**Description:**
`INSURANCE_BOOTSTRAP = 10_000e18` initializes `_balance` in WAD (1e18), but `deposit()` is called by FeeRouter with amounts derived from WAD math. The IFR calculation (`_balance.wadDiv(tvl)`) then divides two WAD values, which is correct only if both are consistently WAD. However, the bootstrap value (10_000e18) is enormous compared to actual USDT transfers.

**Expected:**
All internal accounting uses consistent denomination.

**Actual:**
- Line 92: `_balance = 10_000e18` (= 10 quadrillion in USDT terms if USDT is 6-decimal)
- Line 107: `_balance += amount` where `amount` from FeeRouter is in whatever denomination fees are computed
- IFR starts at ~40% (10_000e18 / 25M in WAD) which may seem correct, but the actual USDT balance doesn't match `_balance`
- On-chain: internal `_balance` ≈ 10 quadrillion, actual USDT = $5M

**Impact:**
- IFR calculation is wrong → wrong fee tier (always Tier 1 instead of Tier 2)
- Daily cap computed on inflated balance → allows excessive absorption
- All InsuranceFund constraint logic is unreliable

**Fix:**
Initialize `_balance` from actual USDT balance or use consistent denomination. If protocol uses WAD internally, bootstrap should match. If using USDT decimals, adjust all constants.

---

### LEVER-004: ExecutionEngine Never Routes Bad Debt to InsuranceFund

**Severity:** CRITICAL
**Contract:** ExecutionEngine.sol
**Location:** ExecutionEngine:355-357

**Description:**
When `_settlePnL` returns `badDebt > 0`, the ExecutionEngine only emits a `BadDebtRecorded` event. It never calls `insuranceFund.absorbBadDebt()` to trigger the insurance waterfall.

**Expected:**
Bad debt should flow through: InsuranceFund → ADL → LP socialization.

**Actual:**
```solidity
if (badDebt > 0) {
    emit BadDebtRecorded(positionId, pos.owner, badDebt);
    // Missing: insuranceFund.absorbBadDebt(pos.marketId, badDebt)
    // Missing: leverVault.socializeLoss(remainder)
}
```

**Impact:**
All bad debt from regular position closes is silently absorbed by the vault through the PnL settlement flow, bypassing the insurance fund entirely. The $5M insurance fund never activates during normal trading.

**Fix:**
Add insurance waterfall after badDebt computation:
```solidity
if (badDebt > 0) {
    (uint256 insurancePaid, uint256 remainder) = insuranceFund.absorbBadDebt(pos.marketId, badDebt);
    if (remainder > 0) {
        leverVault.socializeLoss(remainder);
    }
    emit BadDebtRecorded(positionId, pos.owner, badDebt);
}
```

---

### LEVER-005: FeeRouter Called Without USDT by LiquidationEngine and SettlementEngine

**Severity:** CRITICAL
**Contract:** LiquidationEngine.sol, SettlementEngine.sol
**Location:** LiquidationEngine:420-424, SettlementEngine:269

**Description:**
Both LiquidationEngine._routeFee and SettlementEngine.claimSettlement call `feeRouter.routeFees()` which internally does `usdt.safeTransfer()` to distribute fees. But neither contract transfers USDT to FeeRouter before calling — FeeRouter has no USDT balance to distribute.

**Expected:**
Caller must transfer USDT to FeeRouter before calling `routeFees()`.

**Actual:**
- LiquidationEngine line 421: `feeRouter.routeFees(IFeeRouter.FeeType.LIQUIDATION, feeForProtocol)` — no prior USDT transfer
- SettlementEngine line 269: `feeRouter.routeFees(IFeeRouter.FeeType.SETTLEMENT, result.settlementFee)` — no prior USDT transfer
- ExecutionEngine does it correctly: `accountManager.transferOut(address(feeRouter), toFeeRouter)` then `feeRouter.routeFees(...)`

**Impact:**
- Liquidation fee routing will revert (insufficient USDT balance) → liquidations may fail
- Settlement fee routing will revert → claims may fail
- Note: If FeeRouter accumulated USDT from prior ExecutionEngine calls, it might have enough balance, masking the bug until balance runs low

**Fix:**
Both engines must transfer USDT to FeeRouter before calling routeFees:
```solidity
// LiquidationEngine: transfer from AccountManager to FeeRouter
accountManager.transferOut(address(feeRouter), feeForProtocol);
feeRouter.routeFees(IFeeRouter.FeeType.LIQUIDATION, feeForProtocol);
```

---

### LEVER-006: Ghost OI — OI Not Fully Decremented

**Severity:** CRITICAL
**Contract:** OILimits.sol, ExecutionEngine.sol
**Location:** OILimits:112-136, ExecutionEngine:360

**Description:**
$3.2M ghost OI remains on-chain despite zero open positions. ExecutionEngine._executeClose does call `oiLimits.decreaseOI()` at line 360. The issue may be:
1. Role authorization failure — ExecutionEngine may lack EXECUTION_ENGINE_ROLE on OILimits causing silent failure
2. Revert handling — if decreaseOI reverts, the entire close TX would revert, so positions couldn't close at all
3. The 48 positions (114 opened - 66 closed) that were never explicitly closed have OI still on the books

**Expected:**
After all positions closed, global OI = 0.

**Actual:**
- Global OI on-chain: $3,201,132
- Open positions: 0
- 114 positions opened, only 66 closed via closePosition
- Remaining 48 positions may have been closed via other paths (settlement, liquidation) or may never have been closed at all

**Impact:**
Ghost OI reduces available capacity for new positions and corrupts utilization metrics.

**Fix:**
1. Verify role grants: ExecutionEngine must have EXECUTION_ENGINE_ROLE on OILimits
2. Add admin function to OILimits for emergency OI reset
3. Investigate the 48 "missing" position closures — check if they're still open in PositionManager

---

### LEVER-007: Zero Liquidations Due to Unset depthThreshold

**Severity:** CRITICAL
**Contract:** MarginEngine.sol, RiskCurves.sol
**Location:** MarginEngine:87, RiskCurves:103-108

**Description:**
`depthThreshold` mapping in MarginEngine defaults to 0 for all markets (never set via `updateMarketRiskParams`). When `_getRAdj()` calls `RiskCurves.computeMarketAdjustment()` with `depthThreshold=0`, `computeDepthFactor` returns `WAD` (1.0) instead of reverting — masking the misconfiguration. But more critically, the Depth_Factor calculation is wrong: `min(1.0, externalDepth / 0)` should be undefined.

Per March 14 review M1: RiskCurves returns WAD for threshold=0 instead of reverting. This means R_adjusted is higher than it should be → MM is lower → fewer positions are liquidatable.

**Expected:**
depthThreshold should be set for every market during deployment/onboarding.

**Actual:**
- depthThreshold = 0 for all markets
- Zero liquidations have ever occurred (despite leveraged positions existing)
- Positions that should have been liquidated were not, contributing to the vault drain

**Impact:**
Liquidation system is completely non-functional. All positions with negative equity erode vault NAV without being force-closed.

**Fix:**
1. Set depthThreshold for all markets via `updateMarketRiskParams`
2. In RiskCurves.computeDepthFactor, revert on threshold=0 (defense in depth)
3. Add a deployment script that configures risk params for each market

---

### LEVER-008: Vault NAV Missing Unrealized PnL Tracking

**Severity:** CRITICAL
**Contract:** LeverVault.sol
**Location:** LeverVault:79, LeverVault:130-133, LeverVault:314-318

**Description:**
`_netUnrealizedPnL` exists as a state variable and is used in `totalAssets()` (line 132), and `updateUnrealizedPnL()` exists (line 314-318). However, `updateUnrealizedPnL` is never called by ExecutionEngine or any other contract during position opens/closes/price updates.

**Expected (FORMULAS.md §10):**
```
NAV = USDT_balance - total_unrealized_trader_pnl
```

**Actual:**
- `_netUnrealizedPnL` is always 0
- `totalAssets()` returns raw USDT balance minus socialized losses
- NAV doesn't reflect mark-to-market trader positions
- Share price is wrong → LPs get wrong redemption amounts

**Impact:**
- Vault share price doesn't reflect actual risk exposure
- Withdrawals overpay if traders are profitable (vault owes them)
- Withdrawals underpay if traders are losing (vault holds their losses)
- Current share price: 0.9836 may not reflect true NAV

**Fix:**
ExecutionEngine should call `leverVault.updateUnrealizedPnL()` after every position open/close. Alternatively, compute unrealized PnL on-the-fly in `totalAssets()` by iterating positions (gas-expensive) or maintain a running tally.

---

## HIGH Findings

### LEVER-009: No Closing Transaction Fee

**Severity:** HIGH
**Contract:** ExecutionEngine.sol
**Location:** ExecutionEngine:344-367

**Description:**
`_executeClose()` does not call `feeRouter.collectTransactionFee(pos.positionSize)`. The spec requires TX_FEE (10 bps) on both open AND close.

**Expected:**
10 bps transaction fee on close, deducted from payout.

**Actual:**
Fee only collected on open (line 291 in `_executeOpen`). Close is free.

**Impact:**
Protocol foregoes 50% of transaction fee revenue. With 66 closed positions and ~$3.2M notional, approximately $3,200 in fees lost.

**Fix:**
Add TX fee collection in `_executeClose`:
```solidity
uint256 closingFee = feeRouter.collectTransactionFee(pos.positionSize);
// Deduct from payout or add to costs
```

---

### LEVER-010: LiquidationEngine Doesn't Route PnL Losses to Vault or Borrow Fees

**Severity:** HIGH
**Contract:** LiquidationEngine.sol
**Location:** LiquidationEngine:396-408

**Description:**
`_closeAndSettle()` releases collateral and credits remaining equity to the trader, but:
1. Never computes or routes PnL losses to the vault (when position loses, vault should receive the loss amount)
2. Never routes accrued borrow fees through FeeRouter
3. Doesn't debit the trader's losses from AccountManager or transfer to vault

**Expected:**
Liquidation should mirror the ExecutionEngine settlement flow: compute PnL, route losses to vault, route borrow fees through FeeRouter.

**Actual:**
```solidity
function _closeAndSettle(...) internal {
    oiLimits.decreaseOI(...);
    positionManager.closePosition(positionId);
    accountManager.releaseCollateral(pos.owner, pos.collateral);
    if (traderReceives > 0) {
        accountManager.creditPnL(pos.owner, traderReceives);
    }
    // Missing: PnL loss → vault
    // Missing: borrow fees → FeeRouter
}
```

**Impact:**
When liquidated positions have losses, the USDT stays in AccountManager instead of flowing to the vault. Borrow fees are lost entirely on liquidated positions.

**Fix:**
Compute PnL and borrow fees, transfer losses to vault, route borrow fees through FeeRouter (with USDT pre-transfer).

---

### LEVER-011: FundingRateEngine.routeUnmatchedFunding No-Op

**Severity:** HIGH
**Contract:** FundingRateEngine.sol
**Location:** FundingRateEngine:123-130

**Description:**
`routeUnmatchedFunding()` zeroes `_pendingUnmatchedFunding` and emits an event, but never calls `rewardsDistributor.receiveUnmatchedFunding()` or transfers USDT. The contract doesn't even import IRewardsDistributor.

**Expected:**
Unmatched funding (LP revenue from imbalanced OI) should be transferred as USDT to RewardsDistributor.

**Actual:**
```solidity
function routeUnmatchedFunding(bytes32 marketId) external {
    uint256 pending = _pendingUnmatchedFunding[marketId];
    _pendingUnmatchedFunding[marketId] = 0;
    emit UnmatchedFundingRouted(marketId, pending, block.timestamp);
    // Missing: actual USDT transfer to RewardsDistributor
}
```

**Impact:**
LPs lose all unmatched funding yield. This revenue from imbalanced OI is tracked but never paid out.

**Fix:**
Add RewardsDistributor dependency and transfer USDT:
```solidity
accountManager.transferOut(address(rewardsDistributor), pending);
rewardsDistributor.depositRewards(pending);
```

---

### LEVER-012: MarginEngine IM Uses Fixed Rate Instead of Notional/Leverage

**Severity:** HIGH
**Contract:** MarginEngine.sol
**Location:** MarginEngine:37, MarginEngine:424-426

**Description:**
IM_base is computed as `notional × BASE_IM_RATE` (5% fixed rate) instead of `notional / leverage` as specified.

**Expected (FORMULAS.md §6):**
```
IM_base = Position_Notional / leverage_requested
```

**Actual:**
```solidity
uint256 public constant BASE_IM_RATE = 5e16; // 0.05
uint256 imBase = notional.wadMul(BASE_IM_RATE); // IM = 5% of notional
```

**Impact:**
- Under-margins positions below 20x leverage (5% rate matches 20x leverage)
- Over-margins positions above 20x leverage
- 10x leveraged positions require only 5% collateral instead of 10%

**Fix:**
Use `notional / leverage` for IM_base, or document the rate-based approach as intentional deviation from spec.

---

### LEVER-013: AccountManager.debitPnL Returns Bad Debt But Callers May Not Handle It

**Severity:** HIGH
**Contract:** AccountManager.sol, ExecutionEngine.sol
**Location:** AccountManager:112-123, ExecutionEngine:390

**Description:**
AccountManager.debitPnL correctly handles insufficient balance by debiting what's available and returning the remainder as bad debt. ExecutionEngine._settlePnL captures this return value. However, the bad debt amount from debitPnL is used for the emit-only path (LEVER-004), so it's never actually routed to insurance.

**Expected:**
Bad debt returned by debitPnL should trigger the insurance waterfall.

**Actual:**
The bad debt is captured at line 390 but only used at line 355-357 for an event emission.

**Impact:**
This compounds with LEVER-004 — even though the accounting correctly identifies bad debt, no remediation occurs.

**Fix:**
Already covered by LEVER-004 fix — route badDebt to InsuranceFund.

---

## MEDIUM Findings

### LEVER-014: SettlementEngine Event Emits Wrong Variable

**Severity:** MEDIUM
**Contract:** SettlementEngine.sol
**Location:** SettlementEngine:219-220

**Description:**
The `MarketSettled` event emits `fp.totalBadDebt` twice — once for what should be `totalLoserDebt` (total amount losers couldn't cover):
```solidity
emit MarketSettled(
    marketId, outcome, fp.totalWinnerPayout, fp.totalBadDebt,
    fp.totalBadDebt, fp.totalFees, block.timestamp  // 4th and 5th args are both totalBadDebt
);
```

**Fix:**
The 4th argument should be a separate variable representing total loser collateral absorbed, or the parameter should be named correctly.

---

### LEVER-015: SettlementEngine.claimSettlement Missing USDT Transfers

**Severity:** MEDIUM
**Contract:** SettlementEngine.sol
**Location:** SettlementEngine:233-276

**Description:**
claimSettlement credits payout to the trader's AccountManager balance and tries to route settlement fees, but:
1. No USDT is transferred from LeverVault to fund winner payouts (winners get creditPnL but no USDT backing)
2. Settlement fee routing will fail without USDT pre-transfer (LEVER-005)

**Expected:**
- Winners: vault should fund payout via `leverVault.fundTraderPnL()`
- Losers: their collateral should flow back to vault
- Fees: USDT should be transferred to FeeRouter before routeFees

**Fix:**
Add proper USDT flow: vault funds winners, losers' excess collateral returns to vault, USDT pre-transferred for fee routing.

---

### LEVER-016: RiskCurves.computeDepthFactor Returns WAD for threshold=0

**Severity:** MEDIUM
**Contract:** RiskCurves.sol
**Location:** RiskCurves:103-108

**Description:**
When `depthThreshold = 0`, `computeDepthFactor` returns `WAD` (1.0) instead of reverting. This masks misconfigured markets.

**Fix:**
```solidity
if (depthThreshold == 0) revert ZeroDepthThreshold();
```

---

### LEVER-017: MarketRegistry Role Mismatches vs Spec

**Severity:** MEDIUM
**Contract:** MarketRegistry.sol
**Location:** MarketRegistry:99,112,125,144,158

**Description:**
Multiple functions use wrong roles:
- `resolveMarket`: uses MARKET_MANAGER (spec: ORACLE)
- `activateMarket/setLive/setPendingResolution`: uses KEEPER (spec: MARKET_MANAGER/ORACLE)
- `voidMarket`: uses MARKET_MANAGER (spec: ADMIN)

**Fix:**
Align roles with spec.

---

### LEVER-018: MarketRegistry.resolveMarket Doesn't Validate Outcome

**Severity:** MEDIUM
**Contract:** MarketRegistry.sol
**Location:** MarketRegistry:140-155

**Description:**
Accepts any uint8 value as outcome. Could set outcome > 1, which SettlementEngine would reject.

**Fix:**
```solidity
if (outcome > 1) revert InvalidOutcome();
```

---

### LEVER-019: MarketRegistry.setLive Doesn't Revert When Already Live

**Severity:** MEDIUM
**Contract:** MarketRegistry.sol
**Location:** MarketRegistry:112-121

**Description:**
Silently resets `liveStartTime`, corrupting `tau_effective` calculations downstream.

**Fix:**
```solidity
if (market.isLive) revert AlreadyLive();
```

---

### LEVER-020: BorrowFeeEngine/FundingRateEngine Missing KEEPER Role Check

**Severity:** MEDIUM
**Contract:** BorrowFeeEngine.sol, FundingRateEngine.sol
**Location:** BorrowFeeEngine:112,117; FundingRateEngine:118,123

**Description:**
`accrueIndex`/`accrueAll` and `accrueFunding`/`routeUnmatchedFunding` are permissionless. Spec says KEEPER role required.

**Impact:**
Anyone can trigger accruals at arbitrary times, potentially manipulating funding/borrow rates.

**Fix:**
Add `onlyRole(KEEPER_ROLE)` modifier.

---

### LEVER-021: LeverVault.getUtilization Returns Hardcoded 0

**Severity:** MEDIUM
**Contract:** LeverVault.sol
**Location:** LeverVault:413-415

**Description:**
```solidity
function getUtilization() external view returns (uint256) {
    return 0;
}
```
Always returns 0 instead of computing `Global_OI / TVL`.

**Impact:**
Utilization-based withdrawal restrictions never trigger. Withdrawals allowed even at 100% utilization.

**Fix:**
Compute actual utilization from OILimits global OI vs vault TVL.

---

## LOW Findings

### LEVER-022: OracleAdapter CONSISTENCY_TOLERANCE is 5% Instead of 2%

**Severity:** LOW
**Contract:** OracleAdapter.sol
**Location:** OracleAdapter:33

**Description:**
`CONSISTENCY_TOLERANCE = 5e16` (5%) but CONSTANTS.md specifies 2% (`2e16`).

**Fix:**
Change to `2e16`.

---

### LEVER-023: ProbabilityIndex.isNearBoundary Uses <= / >= Instead of < / >

**Severity:** LOW
**Contract:** ProbabilityIndex.sol
**Location:** ProbabilityIndex:58

**Description:**
PI exactly equal to threshold is treated as "near boundary" when spec says it shouldn't be.

**Fix:**
Change `<=` to `<` and `>=` to `>`.

---

## Deployment/Configuration Issues (Not Code Bugs)

### DEPLOY-001: depthThreshold Not Set for Any Market
All 20 markets have `depthThreshold = 0` in MarginEngine, preventing proper R_adjusted calculation.

### DEPLOY-002: Missing Risk Parameter Configuration
`sigmaCurrent`, `sigmaBaseline`, `externalDepth`, `marketOI`, `globalOI` are all 0 in both MarginEngine and FundingRateEngine for all markets.

### DEPLOY-003: Ghost OI Cleanup Required
$3.2M OI on-chain with zero open positions. Need admin function or redeployment to reset.

---

## Cross-Cutting Concerns

### USDT Decimal Handling
The entire protocol uses WAD (1e18) internally per CLAUDE.md, but USDT on mainnet has 6 decimals. If the testnet MockUSDT also uses 6 decimals, every `usdt.safeTransfer(to, wadAmount)` would transfer astronomically wrong amounts. Need to verify MockUSDT decimal configuration.

### Missing forceClose Function
ExecutionEngine has no `forceClose()` function for LiquidationEngine/SettlementEngine to call. Both engines manage their own close logic independently, leading to inconsistent settlement flows.

---

## Fix Priority Order

1. **LEVER-001** — PnL formula (root cause of vault drain)
2. **LEVER-004** — Bad debt not routed to insurance
3. **LEVER-002** — InsuranceFund no USDT transfer
4. **LEVER-003** — InsuranceFund decimal mismatch
5. **LEVER-005** — FeeRouter called without USDT
6. **LEVER-007** — depthThreshold unset (zero liquidations)
7. **LEVER-008** — Vault NAV unrealized PnL
8. **LEVER-006** — Ghost OI
9. **LEVER-009** — Closing TX fee
10. **LEVER-010** — Liquidation PnL/fee routing
11. **LEVER-011** — Unmatched funding no-op
12. **LEVER-012** — IM rate-based vs leverage-based
13. All MEDIUM and LOW findings
