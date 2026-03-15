# LEVER Protocol — Known Issues Tracker

## CRITICAL
- [x] **OracleAdapter source validation was dead code** — FIXED 2026-03-15

## MEDIUM
- [ ] **OracleAdapter role assignments** — freezeMarket/unfreezeMarket/updateSmoothingParams use KEEPER not ADMIN
- [ ] **OracleAdapter missing auto-freeze on staleness**
- [ ] **ExecutionEngine is bookkeeping-only** — no token transfers for PnL settlement. Needs settlement layer wiring.
- [ ] **Root's /root/lever-protocol copy** — should be deleted after confirming /home/lever is canonical
- [ ] **LiquidationEngine: no execution impact in equity calc** — spec requires computeExitPrice for liquidation equity, currently uses marginEngine.computeEquity (PI-based, no impact)
- [ ] **LiquidationEngine: partial liquidation not chunked** — flagged but full position closed in one call. Comment says "future iteration"
- [ ] **LiquidationEngine: Path A/B not implemented** — only permissionless Path C exists. Spec requires internal paths from closePosition and oracle updates.
- [ ] **LeverVault: executeWithdrawal missing yield** — spec says totalPayout = assets + yield. Users must claim() before withdrawal or lose tranche yield on burned shares.
- [ ] **LeverVault: utilization gate stubbed** — getUtilization() returns 0, withdrawalsEnabled() returns true. No OILimits dependency for 80% gate.
- [ ] **SettlementEngine: MarketSettled event passes totalBadDebt for totalLoserDebt param** — semantic mismatch in event, logic correct

## LOW
- [ ] **OracleAdapter consistency tolerance** — 5% vs spec 2%
- [ ] **OracleAdapter volatility EMA** — lookback ~10 vs spec ~20
- [ ] **OracleAdapter convergence enforcement** — not implemented (spec says SHOULD)
- [ ] **MarginEngine PENDING_RESOLUTION MM multiplier** — spec says use 2× (WP 18.3), not implemented
- [ ] **MarginEngine IM uses rate-based (5%) instead of notional/leverage** — deliberate to avoid circularity, documented
- [ ] **BorrowFeeEngine/FundingRateEngine: permissionless accrual** — spec says KEEPER, implementation allows anyone. Safer but deviates.
- [ ] **FundingRateEngine: routeUnmatchedFunding bookkeeping-only** — emits event but no actual USDT transfer to RewardsDistributor
- [ ] **LeverVault: weightedAge() stub** — returns tranche count, not weighted age

## FIXED (MarketRegistry — 2026-03-15)
- [x] **5 role misassignments** — activateMarket/setLive were KEEPER (spec: MARKET_MANAGER), setPendingResolution/resolveMarket were KEEPER/MARKET_MANAGER (spec: ORACLE), voidMarket was MARKET_MANAGER (spec: ADMIN)
- [x] **resolveMarket accepted any outcome** — no validation that outcome is 0 or 1. Could store garbage.
- [x] **setLive allowed re-setting** — overwrote liveStartTime silently. Spec says revert if already live.
- [x] **activateMarket emitted MarketLive** — misleading event. Now emits MarketActivated.

## FIXED (AccountManager — 2026-03-15)
- [x] **debitPnL reverted on insufficient balance** — spec says cap at balance, return bad debt. Was blocking liquidation/settlement of underwater positions. Now returns badDebt amount for InsuranceFund routing.

## FIXED (ExecutionEngine — 2026-03-15)
- [x] **OI double-counted in imbalance_delta for opens** — increaseOI was called before price computation, so the trade's own OI was already in getSideOI(). Then _computeImbalanceDelta added it again. Moved increaseOI after price computation.

## AUDIT PROGRESS
- [x] FixedPointMath — PASS
- [x] RiskCurves — PASS
- [x] ProbabilityIndex — PASS
- [x] OracleAdapter — ISSUES FOUND (see above)
- [x] MarketRegistry — ISSUES FOUND & FIXED (see above)
- [x] AccountManager — ISSUE FOUND & FIXED (see above)
- [x] PositionManager — PASS
- [x] LeverageModel — PASS
- [x] OILimits — PASS
- [x] ExecutionEngine — ISSUE FOUND & FIXED (see above)
- [x] MarginEngine — PASS (deviations noted in LOW)
- [x] BorrowFeeEngine — PASS (permissionless accrual noted in LOW)
- [x] FundingRateEngine — PASS (permissionless accrual, bookkeeping routing noted)
- [x] FeeRouter — PASS
- [x] LeverVault — PASS (utilization gate stubbed, yield gap noted in MEDIUM)
- [x] RewardsDistributor — PASS
- [x] InsuranceFund — PASS
- [x] LiquidationEngine — ISSUES NOTED (see MEDIUM)
- [x] SettlementEngine — PASS (event param issue noted in MEDIUM)
