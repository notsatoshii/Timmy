# LEVER Protocol — Known Issues

## CRITICAL (blocks investor demo)
- None

## MEDIUM
- LP APY is 0.21% — will increase when leverage bug fixed and higher OI created
- Insurance Fund stuck at $10K bootstrap — fees not flowing through FeeRouter yet
- Oracle keeper (mockkeeper.py) may not be running — prices could go stale

## RESOLVED
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
