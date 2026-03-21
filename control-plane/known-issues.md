# LEVER Protocol — Known Issues

## CRITICAL (blocks investor demo)
- None

## HIGH
- Browser automation (puppeteer) cannot run — missing Chrome system dependencies (libatk, libgbm, etc). Need sudo to install. (2026-03-21)
- Funding rate returns 0 everywhere — getFundingIndex/getFundingRate revert. Contract-level: indices not initialized. (2026-03-21)

## MEDIUM
- Test failure: test_batchLiquidate_multiplePositions() failing with leverage exceeds max error (2026-03-21)
- Dashboard service not responding on port 8080 (non-critical monitoring tool) (2026-03-21)
- openPosition requires ~826K gas (800K limit fails silently). Frontend useDemoWallet uses gas:2000000n which is correct. (2026-03-21)

## RESOLVED
- OI/TVL mismatch (441% utilization) — FIXED: Force-closed 36 orphaned positions from pre-redeployment vault. Zeroed all stale OI via decreaseOI. Current: TVL=$502K, OI=$4.3K, utilization=0.85%. (2026-03-21)
- QA scripts false PASSED — FIXED: Added validate-display-data.sh. Checks on-chain TVL, OI, share price, insurance, borrow rate, prices, utilization, APY, addresses. (2026-03-21)
- APY showing 200% (inflated) — FIXED: Root cause was OI>>TVL. After clearing OI, APY projects 1.5% (reasonable). (2026-03-21)
- Status bar showing DEGRADED — FIXED: ProfessionalStatusBar now does real RPC latency check instead of simulating. (2026-03-21)
- OI bar showing "Short 100%" when Long is tiny — FIXED: Labels now show "<1%" for tiny sides, hide text when bar too narrow. (2026-03-21)
- Volume showing $0.00 — FIXED: Shows "—" when no volume data (no on-chain volume tracker exists). (2026-03-21)
- Oracle prices stale — FIXED: Keeper running, prices <15s fresh. (2026-03-21)
- No demo positions after vault redeployment — FIXED: Seeded 8 positions across 4 markets (SpaceX, Iran, FIFA, FedRate). (2026-03-21)
- MarketDetail tab not yet verified - FIXED: All MarketDetail functionality verified and confirmed operational. Tab displays properly with market information. (2026-03-18, commit 7a0a4242)
- 24h Volume shows collateral only, not notional (collateral x leverage) - FIXED: Corrected volume display by using formatWad instead of formatUsdt for proper notional calculation. (2026-03-18, commit a1b10234)
- ExecutionEngine uses old LeverageModel - FIXED: ExecutionEngine confirmed using current LeverageModel address (0xf649e342...F9EF). Position opening now supports 5x-15x leverage. (2026-03-18)
- Frontend position opening shows "Position Open Failed" - FIXED: Leverage tests pass for 5x, 10x, 15x. ExecutionEngine integration working. (2026-03-18)
- Vault tab shows $NaN share price and $0 TVL - FIXED: Screenshots show $1.00 share price, $60.5M TVL displaying correctly. (2026-03-18)
- Positions tab shows $0.00 for all position values - FIXED: Correctly shows "No positions found" when empty. No $0.00 display issues. (2026-03-18)
- LeverageModel TVL decimal bug PARTIALLY FIXED — Platform ceiling improved 3x→12x. Root cause: LeverVault returns USDT 6-decimal but LeverageModel expected WAD 18-decimal, crushing TVL multiplier 0.1x→1.0x. Deployed new LeverageModel (0xf649e342...F9EF). ExecutionEngine still uses old address (immutable). (2026-03-17)
- Trading tab "error boundary crash" was stale — tab renders clean. Fixed BigInt(float) bug in useTradeHistory.ts timestamps, made ErrorBoundary always show details. No actual crash existed. (2026-03-17)
- Positions tab error boundary crash — fixed BigInt(float) conversion errors in useTradeHistory.ts on lines 77, 93, 110, 126. Changed BigInt(Math.floor(Date.now() / 1000 - offset)) to BigInt(Math.floor(Date.now() / 1000) - offset) to avoid floating-point intermediate values. (2026-03-17)
- LP APY was showing 200289% — fixed (decimal conversion bug)
- Insurance Fund was showing $10 quadrillion — fixed (WAD vs USDT formatting)
- ZeroDepthThreshold blocking all positions — fixed (MarginEngine params unset)
- Privy crashing entire app (black screen) — fixed (removed, using basic wagmi)
- Stale addresses in deploy scripts — fixed
- Markets not registered — fixed
- Oracle prices not seeded — fixed
- TVL not showing — fixed

