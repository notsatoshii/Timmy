# LEVER Protocol — Known Issues Tracker

## CRITICAL
- [x] **OracleAdapter source validation was dead code** — FIXED 2026-03-15
- [ ] **Oracle fallback sources broken — SINGLE POINT OF FAILURE** — DISCOVERED 2026-03-15. Gamma API returns 0.0 prices for all markets (broken parameter/parsing). CLOB orderbook returns static 0.5 for all markets (empty books). Only CLOB midpoint functional. If primary source fails, oracle provides invalid prices.
- [ ] **Feed monitor fallback chain non-functional** — DISCOVERED 2026-03-15. Current feed_monitor.py 3-tier fallback (CLOB→Gamma→cached) would fail in production due to broken Gamma integration. Single point of failure creates liquidation risk.

## MEDIUM
- [x] **OracleAdapter role assignments** — FIXED 2026-03-16. freezeMarket/unfreezeMarket/updateSmoothingParams now use DEFAULT_ADMIN_ROLE as per spec.
- [ ] **OracleAdapter missing auto-freeze on staleness**
- [x] **ExecutionEngine is bookkeeping-only** — FIXED 2026-03-15. _settlePnL now moves USDT: vault↔AccountManager for price PnL, AccountManager→FeeRouter for borrow fees. Bad debt tracked via event.
- [x] **Root's auto-backup cron conflict** — INVESTIGATION COMPLETE 2026-03-15: No active root cron jobs doing git/backup operations found. Checked system cron directories, running processes, systemd timers. Only backup operation is lever user's nightly.py. Root process (dashboard.py) only reads git data. No conflicting operations detected. Issue appears resolved or was preventative.
- [ ] **LiquidationEngine: no execution impact in equity calc** — spec requires computeExitPrice for liquidation equity, currently uses marginEngine.computeEquity (PI-based, no impact)
- [ ] **LiquidationEngine: partial liquidation not chunked** — flagged but full position closed in one call. Comment says "future iteration"
- [ ] **LiquidationEngine: Path A/B not implemented** — only permissionless Path C exists. Spec requires internal paths from closePosition and oracle updates.
- [ ] **LeverVault: executeWithdrawal missing yield** — spec says totalPayout = assets + yield. Users must claim() before withdrawal or lose tranche yield on burned shares.
- [ ] **LeverVault: utilization gate stubbed** — getUtilization() returns 0, withdrawalsEnabled() returns true. No OILimits dependency for 80% gate.
- [ ] **SettlementEngine: MarketSettled event passes totalBadDebt for totalLoserDebt param** — semantic mismatch in event, logic correct

- [ ] **Decimal mismatch: protocol uses WAD (1e18) internally, real USDT is 6 decimals** — Need scaling at deposit/withdrawal boundaries (AccountManager.deposit, LeverVault.deposit/withdraw). Test suite uses 18-decimal mock, so this gap is invisible until testnet deployment.
## LOW
- [ ] **OracleAdapter consistency tolerance** — 5% vs spec 2%
- [ ] **OracleAdapter volatility EMA** — lookback ~10 vs spec ~20
- [ ] **OracleAdapter convergence enforcement** — not implemented (spec says SHOULD)
- [ ] **MarginEngine PENDING_RESOLUTION MM multiplier** — spec says use 2× (WP 18.3), not implemented
- [ ] **MarginEngine IM uses rate-based (5%) instead of notional/leverage** — deliberate to avoid circularity, documented
- [ ] **BorrowFeeEngine/FundingRateEngine: permissionless accrual** — spec says KEEPER, implementation allows anyone. Safer but deviates.
- [ ] **FundingRateEngine: routeUnmatchedFunding bookkeeping-only** — emits event but no actual USDT transfer to RewardsDistributor
- [ ] **LeverVault: weightedAge() stub** — returns tranche count, not weighted age
- [ ] **Puppeteer Chrome sandboxing issues** — CONFIRMED 2026-03-15. Both system chromium-browser (snap, xdg-settings missing) and Puppeteer's bundled Chrome (missing libatk-1.0.so.0, other shared libs) fail to launch in sandboxed environment. Screenshot script functional but blocked by missing dependencies. Would require: apt install libatk1.0-0 libgtk-3-0 libx11-xcb1 libxcomposite1 libxcursor1 libxdamage1 libxi6 libxtst6 libnss3 libxss1 libgconf-2-4 libxrandr2 libasound2 libpangocairo-1.0-0 libcups2 + other GUI libs not available in this environment.

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

**CRITICAL (added 2026-03-16):**
- Insurance Fund display shows raw undivided value ($1000000000000000.00). Likely WAD (1e18) value being displayed without conversion to USDT (1e6). Fix in frontend stats banner component.
- ~~Wallet button stuck on "Loading..."~~ — FIXED 2026-03-16. Replaced Privy with standard wagmi injected connector. Connect Wallet button renders correctly.

**STATS CALCULATION BUGS (added 2026-03-16 by Eric):**
- CRITICAL: LP APY shows 0.00% despite active OI ($30,400) generating borrow fees. APY must be calculated as: (annualized borrow fee revenue flowing to LPs) / TVL. The LP share is 50% of borrow fees via FeeRouter. Check if RewardsDistributor is receiving fees and if the frontend APY calculation reads from it.
- MEDIUM: Insurance Fund shows $10,000 (bootstrap only). Verify FeeRouter is actually routing 20% of fees to InsuranceFund. If fees are accruing in BorrowFeeEngine but not being distributed, the router needs to be called.
- MEDIUM: Total OI is only $30,400 against $60M TVL (~0.05% utilization). This will improve when trader bots deposit and open positions (Phase 7 task). Not a bug, just needs bot activity.
- NOTE: 24h Volume $1,520 is low but accurate for current test trades. Will increase with bot activity.

**STATS CALCULATION BUGS (added 2026-03-16 by Eric):**
- CRITICAL: LP APY shows 0.00% despite active OI ($30,400) generating borrow fees. APY must be calculated as: (annualized borrow fee revenue flowing to LPs) / TVL. The LP share is 50% of borrow fees via FeeRouter. Check if RewardsDistributor is receiving fees and if the frontend APY calculation reads from it.
- MEDIUM: Insurance Fund shows $10,000 (bootstrap only). Verify FeeRouter is actually routing 20% of fees to InsuranceFund. If fees are accruing in BorrowFeeEngine but not being distributed, the router needs to be called.
- MEDIUM: Total OI is only $30,400 against $60M TVL (~0.05% utilization). This will improve when trader bots deposit and open positions (Phase 7 task). Not a bug, just needs bot activity.
- NOTE: 24h Volume $1,520 is low but accurate for current test trades. Will increase with bot activity.

**UI/UX BUGS (added 2026-03-16 by Eric):**

- CRITICAL: Price mismatch between Markets browse cards and Market Detail view. Markets page shows different price than when you click into a market. Both should read from OracleAdapter and show identical current price.

- CRITICAL: 24H Price Chart uses blocky bar chart format. Must be a candlestick chart (1m, 5m, 15m, 1h, 4h, 1D timeframes) like any real trading platform. Reference: lever-concept.png in control-plane/design-reference/ shows the correct candlestick chart format.

- Insurance Fund display shows $10,000.00 — verify this is correct formatting (was previously showing raw WAD value)

- SpaceX market showing 50.0¢/50.0% probability — verify oracle price is correct (was 88.0¢ earlier)

- LP APY shows 0.00% despite $60M TVL and active trading — check if APY calculation is wired to BorrowFeeEngine revenue

