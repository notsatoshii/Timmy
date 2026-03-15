# LEVER Protocol — Master Build Plan
# Agent reads this, picks top incomplete task, executes, updates status.
# Eric can reorder. Agent never reorders — only marks complete.
# Last updated: 2026-03-15 (synced with test-phase.log results)

## Phase 1: Stabilize
- [x] **P0** Fix OracleAdapter source validation — DONE 2026-03-15
- [x] **P0** Commit all uncommitted changes — DONE 2026-03-15
- [x] **P1** Full compile check — CLEAN 2026-03-15
- [x] **P1** Full test suite pass — DONE 2026-03-15 08:13 UTC
- [ ] **P1** Consolidate repo copies (delete /root/lever-protocol, /home/lever is canonical)
- [ ] **P1** Disable root's auto-backup cron (it conflicts with lever's pushes)

## Phase 1.5: Math Verifications (COMPLETE)
- [x] RiskCurves — exact match
- [x] LeverageModel — exact match
- [x] ExecutionEngine — exact match (1 wei rounding, acceptable)
- [x] FundingRateEngine — exact match, zero-sum confirmed
- [x] BorrowFeeEngine — exact match
- [x] MarginEngine equity — exact match (1440 = 1000 + 1000 - 200 - 360)

## Phase 2: Spec Audit (all contracts)
- [x] FixedPointMath — PASS
- [x] RiskCurves — PASS
- [x] ProbabilityIndex — PASS
- [x] OracleAdapter — ISSUES FOUND (logged in known-issues.md)
- [x] **P0** MarketRegistry — audit against spec — ISSUES FOUND & FIXED 2026-03-15
- [x] **P0** AccountManager — audit against spec — ISSUES FOUND & FIXED 2026-03-15
- [x] **P0** PositionManager — audit against spec — PASS 2026-03-15
- [x] **P0** LeverageModel — audit against spec — PASS 2026-03-15
- [x] **P0** OILimits — audit against spec — PASS 2026-03-15
- [x] **P0** ExecutionEngine — audit against spec — OI ORDERING BUG FIXED 2026-03-15
- [x] **P0** MarginEngine — audit against spec — PASS (deviations noted) 2026-03-15
- [ ] **P1** BorrowFeeEngine — audit against spec
- [ ] **P1** FundingRateEngine — audit against spec
- [ ] **P1** FeeRouter — audit against spec
- [ ] **P1** LeverVault — audit against spec
- [ ] **P1** RewardsDistributor — audit against spec
- [ ] **P1** InsuranceFund — audit against spec
- [ ] **P1** LiquidationEngine — audit against spec
- [ ] **P1** SettlementEngine — audit against spec

## Phase 3: Integration Testing
NOTE: Test files already exist in test/integration/. Verify they pass, don't rewrite.
- [x] **P0** Full position lifecycle (PositionLifecycle.t.sol) — PASSED 2026-03-15 08:35 UTC
- [ ] **P0** Verify LiquidationFlow.t.sol + LiquidationExecution.t.sol pass (test-phase hung here — never completed)
- [ ] **P0** Verify SettlementFlow.t.sol + SettlementExecution.t.sol pass
- [ ] **P1** Verify MultiMarket.t.sol passes
- [ ] **P1** Verify NearResolution.t.sol passes (edge cases near 0/100)
- [ ] **P1** Verify WithdrawalQueue.t.sol passes (LP 80% utilization gate)
- [ ] **P1** Verify InsuranceBadDebt.t.sol passes
- [ ] **P1** Verify FeeFlow.t.sol passes
- [ ] **P1** Verify TrancheLedger.t.sol passes
- [ ] **P0** Fix ExecutionEngine token transfer gap — bookkeeping only, no USDT moves on PnL settlement

## Phase 4: Deployment Prep
- [ ] Deployment scripts (Foundry, ordered by dependency)
- [ ] Constructor parameter configs (testnet values)
- [ ] Role assignment script
- [ ] Verification script (BaseScan)
- [ ] Post-deployment smoke test

## Phase 5: Testnet
- [ ] Deploy to Base Sepolia
- [ ] Seed bots (trading, LP, oracle)
- [ ] Monitor 48 hours

## Phase 6: Frontend
- [ ] React dashboard (markets, trading, vault, positions)
- [ ] Connect to Base Sepolia contracts
- [ ] Core UI flows

## Completion Log
[2026-03-15] OracleAdapter source validation fix — c75c5c9
[2026-03-15] All math verifications passed — exact match across 6 engines
[2026-03-15] Full lifecycle integration — 13/13 steps, zero mocks
[2026-03-15] Build plan synced with actual test-phase.log results
[2026-03-15] MarketRegistry spec audit — 9 issues found, all fixed. Roles, outcome validation, already-live guard, event naming.
[2026-03-15] AccountManager spec audit — 1 HIGH fixed (debitPnL now caps at balance, returns bad debt).
[2026-03-15] PositionManager, LeverageModel, OILimits — all PASS, no fixes needed.
[2026-03-15] ExecutionEngine spec audit — OI ordering bug fixed (trade was double-counted in imbalance_delta).
[2026-03-15] MarginEngine spec audit — PASS with noted deviations (IM rate-based, pending resolution MM not implemented).
