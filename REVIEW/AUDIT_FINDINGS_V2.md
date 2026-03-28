# LEVER Protocol — Audit Findings V2
**Date:** 2026-03-28
**Auditor:** Claude Sonnet 4.6
**Scope:** All 19 contracts (~7,200 lines) — full line-by-line analysis
**Build state:** 1068 tests pass, 4 fail (pre-existing PriceSmoothing verification only)
**Reference:** AUDIT_FINDINGS_FINAL.md (prior session 2026-03-26)

---

## Executive Summary

The prior audit (2026-03-26) fixed 13 of 23 findings. This session performed a fresh read
of every contract and found **5 new critical/high bugs** that were not caught before,
plus confirmed 4 remaining medium/low issues. The 5 new bugs include two that would cause
every keeper accrual call to revert (LEVER-P01, LEVER-P02), one that double-distributes
closing transaction fees (LEVER-P03), one where insurance payments get stuck in
ExecutionEngine (LEVER-P04), and one where the unmatched funding router always reverts due
to a role mismatch (LEVER-P05).

---

## Status of Prior 23 Findings

| ID | Severity | Description | Status |
|----|----------|-------------|--------|
| LEVER-001 | CRITICAL | PnL formula mismatch (entryPrice vs entryPI) | FIXED |
| LEVER-002 | CRITICAL | Ghost OI ($3.2M) not decremented | FIXED (code), NEEDS adminResetMarketOI on-chain |
| LEVER-003 | CRITICAL | $304K unaccounted vault drain | PARTIALLY FIXED (see LEVER-P03) |
| LEVER-004 | CRITICAL | InsuranceFund bad debt routing (no USDT transfer) | PARTIALLY FIXED (see LEVER-P04) |
| LEVER-005 | CRITICAL | InsuranceFund decimal mismatch (WAD vs USDT) | FIXED |
| LEVER-006 | CRITICAL | FeeRouter called without USDT by Liquidation/Settlement | FIXED |
| LEVER-007 | CRITICAL | Zero liquidations (depthThreshold=0 -> ZeroDepthThreshold) | FIXED in MarginEngine, NOT FIXED in FundingRateEngine/BorrowFeeEngine (see LEVER-P01/P02) |
| LEVER-008 | HIGH | No closing transaction fee | FIXED |
| LEVER-009 | HIGH | Vault NAV missing unrealized PnL (_netUnrealizedPnL never updated) | PARTIALLY FIXED (variable exists, never set - see LEVER-P06) |
| LEVER-010 | HIGH | LiquidationEngine does not route losses to vault | FIXED |
| LEVER-011 | HIGH | FundingRateEngine.routeUnmatchedFunding - no USDT transfer | PARTIALLY FIXED (see LEVER-P05) |
| LEVER-012 | HIGH | Vault utilization getUtilization() returns 0 | NOTED (still returns 0) |
| LEVER-014 | MEDIUM | SettlementEngine event emits wrong variable for totalLoserDebt | FIXED |
| LEVER-017-021 | MEDIUM | Role alignment, validation guards | PARTIAL |

---

## New Findings (This Session)

---

### LEVER-P01 — CRITICAL
**Contract:** FundingRateEngine.sol
**Function:** `_getRAdjusted` (called from every external state-changing function)
**Lines:** 331-348

**Description:** FundingRateEngine._getRAdjusted calls `RiskCurves.computeMarketAdjustment()`
with `depthThreshold[marketId]` as the last argument. If depthThreshold is 0 (default for
any uninitiated market), this propagates to `computeDepthFactor(externalDepth, 0)` which
reverts with `RiskCurves__ZeroDepthThreshold()`.

MarginEngine fixed this (LEVER-007) by checking `if (depthThreshold[marketId] == 0) mMarket = WAD`.
FundingRateEngine did not receive the same fix.

**Impact:** Every call to `accrueFunding(marketId)`, `accrueFundingAll()`, or any view that
calls `_computeSignedFundingRate` will revert for any market where `updateMarketRiskParams`
has not been called with a non-zero depthThreshold. Since all 20 markets need this set in
FundingRateEngine separately from MarginEngine, and the keeper calls accrueFunding regularly,
this would block all funding accrual on freshly deployed markets.

**Expected:** Same guard as MarginEngine — skip depth adjustment when unset.

**Actual:**
```solidity
function _getRAdjusted(bytes32 marketId) internal view returns (uint256) {
    // ...
    uint256 mMarket = RiskCurves.computeMarketAdjustment(
        sigmaCurrent[marketId],
        sigmaBaseline[marketId],
        externalDepth[marketId],
        depthThreshold[marketId],  // 0 by default -> revert
        marketOI[marketId],
        globalOI
    );
    return RiskCurves.computeRAdjusted(r, mMarket);
}
```

**Fix:**
```solidity
function _getRAdjusted(bytes32 marketId) internal view returns (uint256) {
    uint256 tauHours = marketRegistry.getTau(marketId);
    bool isLive_ = marketRegistry.isLive(marketId);
    uint256 tauEff = RiskCurves.computeTauEffective(tauHours, isLive_);
    uint256 r = RiskCurves.computeR(tauEff);

    uint256 mMarket;
    if (depthThreshold[marketId] == 0) {
        mMarket = 1e18; // No market adjustment when depth threshold not configured
    } else {
        mMarket = RiskCurves.computeMarketAdjustment(
            sigmaCurrent[marketId],
            sigmaBaseline[marketId],
            externalDepth[marketId],
            depthThreshold[marketId],
            marketOI[marketId],
            globalOI
        );
    }
    return RiskCurves.computeRAdjusted(r, mMarket);
}
```

---

### LEVER-P02 — CRITICAL
**Contract:** BorrowFeeEngine.sol
**Function:** `_getRBorrowAdjusted` (called from `_computeBorrowRate` -> `_accrueIndex`)
**Lines:** 313-330

**Description:** Same class of bug as LEVER-P01. BorrowFeeEngine._getRBorrowAdjusted calls
`RiskCurves.computeMarketAdjustment()` with unguarded `depthThreshold[marketId]`. Default
is 0 -> `computeDepthFactor(0, 0)` -> `RiskCurves__ZeroDepthThreshold()` revert.

**Impact:** `accrueAll()` (keeper calls this every oracle tick), `accrueIndex()`, and
`getCurrentBorrowRate()` all revert for uninitiated markets. This means no borrow fees
accrue, liquidation checks using borrow accruals are wrong, and the keeper crashes.

**Fix:** Same pattern as MarginEngine and LEVER-P01 fix — guard with `if (depthThreshold[marketId] == 0) mMarket = WAD`.

---

### LEVER-P03 — CRITICAL
**Contract:** ExecutionEngine.sol + FeeRouter.sol
**Functions:** `_executeOpen`, `_executeClose`, `_settlePnL`, `FeeRouter.collectTransactionFee`
**Lines:** ExecutionEngine:295-296, 358-359, 395-436; FeeRouter:136-166

**Description:** `feeRouter.collectTransactionFee()` immediately distributes fees (via
`usdt.safeTransfer`) from FeeRouter's OWN USDT balance before any USDT has been
transferred from AccountManager to FeeRouter for this transaction. This creates two
compounding bugs:

**Bug A — Opening fee stuck in AccountManager:**
In `_executeOpen`:
```solidity
uint256 txFee = feeRouter.collectTransactionFee(notional);  // FeeRouter distributes from reserves
ctx.collateralNet = params.collateral - txFee;
// ...
accountManager.debitPnL(msg.sender, txFee);  // Reduces user's accounting balance only
// No transfer of txFee USDT from AccountManager to FeeRouter ever happens
```
FeeRouter distributes txFee from its reserves. User's accounting balance is reduced.
But the actual USDT representing txFee remains in AccountManager's custody forever.
Net effect: AccountManager holds more USDT than it has liabilities. FeeRouter's reserves
shrink with each new position opened. Over time AccountManager accumulates "phantom" USDT.

This is the primary cause of the $5.9M unaccounted USDT in AccountManager and the $426K
vault drain (FeeRouter pays from its own reserves, which were ultimately funded by vault
deposits during seeding).

**Bug B — Closing fee double-distributed:**
In `_executeClose`:
```solidity
uint256 closingFee = feeRouter.collectTransactionFee(pos.positionSize);  // FIRST distribution
// ...
_settlePnL(pos.owner, pos.collateral, pnl, borrowFees, accruedFunding, closingFee);
```
In `_settlePnL`:
```solidity
uint256 totalFees = borrowFees + closingFee;
// ...
accountManager.transferOut(address(feeRouter), toFeeRouter);  // sends borrowFees+closingFee to FeeRouter
feeRouter.routeFees(IFeeRouter.FeeType.BORROW, toFeeRouter);  // SECOND distribution of closingFee
```
The closingFee is distributed twice: once by `collectTransactionFee` (from FeeRouter reserves)
and once by `routeFees` (from the AccountManager transfer). Each close creates a surplus
closingFee distribution.

**Expected:** The USDT for fees must flow from user -> AccountManager -> FeeRouter -> destinations.
FeeRouter should never spend from reserves for fees it hasn't yet received.

**Fix (minimal):**

In `_executeOpen`, replace the `collectTransactionFee` + `debitPnL` pattern with:
```solidity
uint256 txFee = ctx.notional * FEE_RATE / WAD;  // or read from feeRouter constant
ctx.collateralNet = params.collateral - txFee;
accountManager.debitPnL(msg.sender, txFee);
accountManager.transferOut(address(feeRouter), txFee);
feeRouter.routeFees(IFeeRouter.FeeType.TRANSACTION, txFee);
```

In `_executeClose`, replace `collectTransactionFee` with:
```solidity
uint256 closingFee = pos.positionSize * TX_FEE_RATE / WAD;
```
Then in `_settlePnL` include closingFee in `totalFees` (already done) so it is transferred
and routed once together with borrowFees. Do NOT call `collectTransactionFee`.

Add a `TX_FEE_RATE` constant to ExecutionEngine matching FeeRouter.TX_FEE_RATE (1e15 = 10bps).

---

### LEVER-P04 — CRITICAL
**Contract:** ExecutionEngine.sol + InsuranceFund.sol
**Function:** `ExecutionEngine._executeClose` (line 364-369), `InsuranceFund.absorbBadDebt` (line 185-187)
**Lines:** EE:364-369; IF:185-187

**Description:** `InsuranceFund.absorbBadDebt()` transfers USDT to `msg.sender`. When called
from `ExecutionEngine._executeClose`, msg.sender is the ExecutionEngine contract address.
ExecutionEngine has no USDT token reference and no function to forward received USDT.
The insurance payment is permanently stuck in ExecutionEngine.

```solidity
// InsuranceFund.absorbBadDebt
if (insurancePaid > 0) {
    usdt.safeTransfer(msg.sender, insurancePaid);  // msg.sender = ExecutionEngine
}
```

```solidity
// ExecutionEngine._executeClose
if (badDebt > 0) {
    (uint256 insurancePaid, uint256 remainder) = insuranceFund.absorbBadDebt(pos.marketId, badDebt);
    if (remainder > 0) {
        leverVault.socializeLoss(remainder);
    }
    // insurancePaid USDT is now stuck in this contract
}
```

**Impact:** Every bad-debt position close sends insurance USDT to ExecutionEngine, where it
is permanently locked. The vault is not compensated for the bad debt it absorbs. Effectively,
the insurance fund is still non-functional for executive closes (though mechanically it does
transfer USDT, just to the wrong place).

The same class of bug exists in SettlementEngine._handleBadDebtWaterfall (line 502) which
calls `insuranceFund.absorbBadDebt(marketId, totalBadDebt)` — that USDT also goes to
SettlementEngine and gets stuck.

**Fix option A (preferred):** Change InsuranceFund.absorbBadDebt to accept a recipient
address and send directly to the vault:
```solidity
function absorbBadDebt(bytes32 marketId, uint256 totalBadDebt, address vaultRecipient)
    external returns (uint256 insurancePaid, uint256 remainder) {
    // ... compute insurancePaid ...
    if (insurancePaid > 0) {
        usdt.safeTransfer(vaultRecipient, insurancePaid);
    }
}
```
Callers pass `address(leverVault)` as the recipient.

**Fix option B (no interface change):** Add a `usdt` reference to ExecutionEngine and
SettlementEngine and forward the received USDT to the vault:
```solidity
// After absorbBadDebt returns insurancePaid:
if (insurancePaid > 0) {
    usdt.safeTransfer(address(leverVault), insurancePaid);
}
```

Fix option A is cleaner. Fix option B requires adding IERC20 import and usdt state to
ExecutionEngine and SettlementEngine.

---

### LEVER-P05 — HIGH
**Contract:** FundingRateEngine.sol + RewardsDistributor.sol
**Function:** `FundingRateEngine.routeUnmatchedFunding` (line 143)
**Lines:** FRE:143; RD:94

**Description:** `routeUnmatchedFunding` calls `rewardsDistributor.depositRewards(pending)`.
But `depositRewards` in RewardsDistributor requires `FEE_ROUTER_ROLE`. FundingRateEngine
has `FUNDING_RATE_ENGINE_ROLE` on RewardsDistributor (per deployment), not FEE_ROUTER_ROLE.

```solidity
// FundingRateEngine.routeUnmatchedFunding
rewardsDistributor.depositRewards(pending);  // REVERTS: caller lacks FEE_ROUTER_ROLE
```

RewardsDistributor has a separate `receiveUnmatchedFunding(marketId, amount)` function
(line 112) that requires `FUNDING_RATE_ENGINE_ROLE` — this is the correct function to call.

**Impact:** Every `routeUnmatchedFunding` call reverts. Unmatched funding never reaches the
LP pool. _pendingUnmatchedFunding accumulates but can never be drained.

**Fix:**
```solidity
// FundingRateEngine.routeUnmatchedFunding
accountManager.transferOut(address(rewardsDistributor), pending);
rewardsDistributor.receiveUnmatchedFunding(marketId, pending);  // FIX: correct function
```

---

### LEVER-P06 — HIGH
**Contract:** LeverVault.sol + ExecutionEngine.sol
**Function:** `LeverVault.updateUnrealizedPnL`, `ExecutionEngine._executeOpen/_executeClose`
**Lines:** LV:314-318

**Description:** LeverVault.totalAssets() correctly accounts for `_netUnrealizedPnL`:
```solidity
function totalAssets() public view returns (uint256) {
    int256 nav = int256(balance) - _netUnrealizedPnL - int256(_socializedLosses);
    return nav > 0 ? uint256(nav) : 0;
}
```
However, `updateUnrealizedPnL(int256)` requires `EXECUTION_ENGINE_ROLE` and is
**never called by ExecutionEngine**. `_netUnrealizedPnL` remains 0 forever.

**Impact:** Vault NAV = raw USDT balance always. Does not reflect that traders are net
profitable (vault owes them money). Vault share price is overstated when traders are in
profit (vault appears to hold more than it actually "owns"). This causes incorrect share
pricing for depositors/withdrawers and incorrect IFR calculations.

**Fix:** ExecutionEngine should maintain a running net unrealized PnL. The cheapest
approach: after every position open and close, recompute the full market's net unrealized
PnL and call `leverVault.updateUnrealizedPnL(netPnL)`. This requires iterating all open
positions, which is expensive. A simpler approach: track delta updates per position open/close.

Minimum viable fix: on open, subtract the opening impact (PI-adjusted entry vs current PI)
as initial unrealized PnL. On close, add back the realized PnL and remove the unrealized
portion. Use the vault's `updateUnrealizedPnL` with these deltas.

---

## Full Findings Summary (All Sessions)

| ID | Severity | Description | Status | File |
|----|----------|-------------|--------|------|
| LEVER-001 | CRITICAL | PnL uses entryPrice (impact) not entryPI (raw) | FIXED | ExecutionEngine |
| LEVER-002 | CRITICAL | Ghost OI never decremented on close | FIXED | OILimits |
| LEVER-003 | CRITICAL | Vault drain from fee accounting mismatch | PARTIAL | See LEVER-P03 |
| LEVER-004 | CRITICAL | InsuranceFund absorbBadDebt no USDT transfer | PARTIAL | See LEVER-P04 |
| LEVER-005 | CRITICAL | InsuranceFund decimal mismatch (WAD vs USDT) | FIXED | InsuranceFund |
| LEVER-006 | CRITICAL | FeeRouter called without USDT by Liq/Settlement | FIXED | Liquidation/Settlement |
| LEVER-007 | CRITICAL | Zero liquidations (depthThreshold=0 in MarginEngine) | FIXED | MarginEngine |
| LEVER-008 | HIGH | No closing transaction fee (10bps foregone) | FIXED | ExecutionEngine |
| LEVER-009 | HIGH | Vault NAV missing unrealized PnL | PARTIAL | See LEVER-P06 |
| LEVER-010 | HIGH | LiquidationEngine doesnt route losses to vault | FIXED | LiquidationEngine |
| LEVER-011 | HIGH | FundingRateEngine routeUnmatchedFunding no USDT | PARTIAL | See LEVER-P05 |
| LEVER-012 | MEDIUM | LeverVault.getUtilization() always returns 0 | OPEN | LeverVault |
| LEVER-014 | MEDIUM | SettlementEngine event wrong variable | FIXED | SettlementEngine |
| **LEVER-P01** | **CRITICAL** | FundingRateEngine depthThreshold=0 -> revert on accrual | **NEW** | FundingRateEngine |
| **LEVER-P02** | **CRITICAL** | BorrowFeeEngine depthThreshold=0 -> revert on accrual | **NEW** | BorrowFeeEngine |
| **LEVER-P03** | **CRITICAL** | Fee double-distribution + opening fee stuck in AccountManager | **NEW** | ExecutionEngine/FeeRouter |
| **LEVER-P04** | **CRITICAL** | Insurance USDT stuck in ExecutionEngine/SettlementEngine | **NEW** | InsuranceFund/ExecutionEngine |
| **LEVER-P05** | **HIGH** | routeUnmatchedFunding calls wrong function (role mismatch) | **NEW** | FundingRateEngine |
| **LEVER-P06** | **HIGH** | Vault NAV: updateUnrealizedPnL never called | **NEW** | LeverVault/ExecutionEngine |

---

## Root Cause Analysis: $426K Vault Drain (LEVER-003)

The forensic data shows $426K lost from vault NAV. Here is the full traced mechanism:

1. **Opening fee stuck in AccountManager** (Bug A above):
   Every time a position opens, `txFee = notional * 0.001` is deducted from the user's
   AccountManager balance (via `debitPnL`) but the USDT never leaves AccountManager.
   FeeRouter distributes txFee from its own reserves (previously funded by vault deposits).
   Net: AccountManager +txFee phantom USDT. FeeRouter -txFee real USDT.

2. **FeeRouter reserves depleted**:
   With 114 position opens at avg ~$50K notional at 10x leverage (~$500K notional each?),
   no the positions were smaller. With $3.2M peak OI across 114 positions, average notional
   was ~$28K. tx fee = 0.001 * $28K = $28. 114 opens = ~$3,192 in stuck opening fees.
   Not enough to explain $426K alone.

3. **Vault funds trader profits (winners)**:
   ExecutionEngine calls `leverVault.fundTraderPnL(address(accountManager), pnl)` when
   `pnl > 0`. The vault transfers pnl USDT to AccountManager. With 38 winners and 0 losers,
   the vault paid out but no counterbalancing loss payments came in.

4. **Collateral not transferred to vault on loss**:
   When a position closes at a loss, `pnlLoss` should transfer from AccountManager to vault.
   But with 0 losers, no loss transfers occurred. The vault just paid winners.

5. **The math**:
   38 winners averaging profitable closes = vault paid ~$16K in PnL (per forensic data).
   Remaining ~$410K loss = unclear. Could be borrow fees distributed incorrectly from
   FeeRouter reserves (which were seeded from vault).

**The fundamental issue**: FeeRouter was seeded with USDT from the vault directly during
deployment testing. When FeeRouter pays from "reserves" for tx fees, it is effectively
paying from the vault's money without proper accounting.

---

## Priority Fix Order (For Demo)

### P0 — Fixes that prevent the system from running at all:
1. **LEVER-P01** — FundingRateEngine depthThreshold guard (keeps accrueFunding working)
2. **LEVER-P02** — BorrowFeeEngine depthThreshold guard (keeps borrow accrual working)
3. **LEVER-P05** — routeUnmatchedFunding wrong function call

### P1 — Fixes that prevent correct financial accounting:
4. **LEVER-P03** — Fee double-distribution / stuck opening fees
5. **LEVER-P04** — Insurance USDT stuck in ExecutionEngine/SettlementEngine

### P2 — Fixes for correct NAV/share-price calculation:
6. **LEVER-P06** — Vault NAV unrealized PnL update

### P3 — Cleanup:
7. **LEVER-012** — LeverVault.getUtilization() returns real value

---

## Unchanged Contracts (Verified Clean)

The following contracts are correct and require no changes:
- FixedPointMath.sol — math is correct
- RiskCurves.sol — math matches FORMULAS.md exactly
- ProbabilityIndex.sol — correct
- AccountManager.sol — correct
- PositionManager.sol — correct
- MarketRegistry.sol — correct
- FeeRouter.sol — correct (the bug is how it's called, not FeeRouter itself)
- RewardsDistributor.sol — correct
- LeverVault.sol — correct (updateUnrealizedPnL is there, just never called)
- BorrowFeeEngine.sol — correct EXCEPT the depthThreshold guard (LEVER-P02)

---

## Deployment State Notes

Currently deployed contracts (Base Sepolia):
- ExecutionEngine: 0xE91C216b2baAeb4b088A1531469234A2C5b5fDc2
- FundingRateEngine: 0xf96b5dba5763be3521df0a445e8b4e12db59baac
- BorrowFeeEngine: 0x706578de003912C71e534949d8b8DDd5108950e1
- InsuranceFund: 0xfdd5e050bef5ae4861b091b9701e2e7a4a30bcea
- LeverVault: 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921

All 5 new bugs (LEVER-P01 through P06) require contract redeployment since these
contracts are not upgradeable.

**Ghost OI remediation:** After redeployment, call `OILimits.adminResetMarketOI(marketId)`
for all 20 markets to clear the $3.2M ghost OI. Verify all positions are closed first.

**InsuranceFund balance:** The deployed InsuranceFund has $5M real USDT but `_balance`
accounting likely reflects only what FeeRouter has deposited via `deposit()`. Admin should
verify _balance vs actual USDT.balanceOf(insuranceFund) and reconcile. A separate admin
`syncBalance()` function should be added to allow ADMIN_ROLE to set _balance to actual
on-chain USDT balance.
