# LEVER Protocol — Known Issues

## CRITICAL (blocks investor demo)
- Vault tab shows $NaN share price and $0 TVL in demo mode (useVaultMulticall returns undefined, 413 RPC errors)
- Positions tab shows $0.00 for all position values in demo mode (stub positions with zero values)
- MarketDetail tab not yet verified
- Leverage capped at 1.8x when markets 288 days from resolution should allow 20-30x
- Frontend position opening shows "Position Open Failed" (contract works via CLI)
- 24h Volume shows collateral only, not notional (collateral x leverage)

## MEDIUM
- LP APY is 0.21% — will increase when leverage bug fixed and higher OI created
- Insurance Fund stuck at $10K bootstrap — fees not flowing through FeeRouter yet
- Oracle keeper (mockkeeper.py) may not be running — prices could go stale

## RESOLVED
- Trading tab "error boundary crash" was stale — tab renders clean. Fixed BigInt(float) bug in useTradeHistory.ts timestamps, made ErrorBoundary always show details. No actual crash existed. (2026-03-17)
- LP APY was showing 200289% — fixed (decimal conversion bug)
- Insurance Fund was showing $10 quadrillion — fixed (WAD vs USDT formatting)
- ZeroDepthThreshold blocking all positions — fixed (MarginEngine params unset)
- Privy crashing entire app (black screen) — fixed (removed, using basic wagmi)
- Stale addresses in deploy scripts — fixed
- Markets not registered — fixed
- Oracle prices not seeded — fixed
- TVL not showing — fixed
