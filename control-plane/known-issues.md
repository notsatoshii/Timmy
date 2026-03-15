# LEVER Protocol — Known Issues Tracker

## CRITICAL
- [x] **OracleAdapter source validation was dead code** — FIXED 2026-03-15

## MEDIUM
- [ ] **OracleAdapter role assignments** — freezeMarket/unfreezeMarket/updateSmoothingParams use KEEPER not ADMIN
- [ ] **OracleAdapter missing auto-freeze on staleness**
- [ ] **ExecutionEngine is bookkeeping-only** — no token transfers for PnL settlement. Needs settlement layer wiring.
- [ ] **Root's /root/lever-protocol copy** — should be deleted after confirming /home/lever is canonical

## LOW
- [ ] **OracleAdapter consistency tolerance** — 5% vs spec 2%
- [ ] **OracleAdapter volatility EMA** — lookback ~10 vs spec ~20
- [ ] **OracleAdapter convergence enforcement** — not implemented (spec says SHOULD)

## FIXED (MarketRegistry — 2026-03-15)
- [x] **5 role misassignments** — activateMarket/setLive were KEEPER (spec: MARKET_MANAGER), setPendingResolution/resolveMarket were KEEPER/MARKET_MANAGER (spec: ORACLE), voidMarket was MARKET_MANAGER (spec: ADMIN)
- [x] **resolveMarket accepted any outcome** — no validation that outcome is 0 or 1. Could store garbage.
- [x] **setLive allowed re-setting** — overwrote liveStartTime silently. Spec says revert if already live.
- [x] **activateMarket emitted MarketLive** — misleading event. Now emits MarketActivated.

## FIXED (AccountManager — 2026-03-15)
- [x] **debitPnL reverted on insufficient balance** — spec says cap at balance, return bad debt. Was blocking liquidation/settlement of underwater positions. Now returns badDebt amount for InsuranceFund routing.

## AUDIT PROGRESS
- [x] FixedPointMath — PASS
- [x] RiskCurves — PASS
- [x] ProbabilityIndex — PASS
- [x] OracleAdapter — ISSUES FOUND (see above)
- [x] MarketRegistry — ISSUES FOUND & FIXED (see above)
- [x] AccountManager — ISSUE FOUND & FIXED (see above)
- [ ] PositionManager through SettlementEngine — pending
