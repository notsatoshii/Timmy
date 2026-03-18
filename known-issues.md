# LEVER Protocol — Known Issues

## CRITICAL (blocks investor demo)
- Positions tab shows $0.00 for all position values in demo mode (stub positions with zero values)
- Leverage capped at 1.8x when markets 288 days from resolution should allow 20-30x
- Frontend position opening shows "Position Open Failed" (contract works via CLI)

## MEDIUM
- LP APY is 0.21% — will increase when leverage bug fixed and higher OI created
- Insurance Fund stuck at $10K bootstrap — fees not flowing through FeeRouter yet
- Oracle keeper (mockkeeper.py) may not be running — prices could go stale

## RESOLVED
- MarketDetail tab not yet verified - RESOLVED: All MarketDetail functionality verified and confirmed operational. Tab displays properly with market information. (2026-03-18, commit 7a0a4242)
- 24h Volume shows collateral only, not notional (collateral x leverage) - RESOLVED: Corrected volume display by using formatWad instead of formatUsdt for proper notional calculation. (2026-03-18, recent commit fixed formatWad vs formatUsdt)
- Vault tab "error boundary crash" was stale — tab renders clean. ErrorBoundary already fixed to always show details. VaultOptimized.tsx properly wrapped and has no BigInt conversion issues. (2026-03-17)
- Trading tab "error boundary crash" was stale — tab renders clean. Fixed BigInt(float) bug in useTradeHistory.ts timestamps, made ErrorBoundary always show details. No actual crash existed. (2026-03-17)
- LP APY was showing 200289% — fixed (decimal conversion bug)
- Insurance Fund was showing $10 quadrillion — fixed (WAD vs USDT formatting)
- ZeroDepthThreshold blocking all positions — fixed (MarginEngine params unset)
- Privy crashing entire app (black screen) — fixed (removed, using basic wagmi)
- Stale addresses in deploy scripts — fixed
- Markets not registered — fixed
- Oracle prices not seeded — fixed
- TVL not showing — fixed