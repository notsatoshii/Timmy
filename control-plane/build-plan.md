# LEVER Protocol — Master Build Plan
# Agent reads this, picks top incomplete task, executes, updates status.
# Eric can reorder. Agent never reorders — only marks complete.
# Last updated: 2026-03-15

## Phase 1: Stabilize (CURRENT)
- [ ] **P0** Fix OracleAdapter source validation (dead code — pushPrice ignores _sources[msg.sender].isActive)
- [ ] **P0** Commit all uncommitted changes (foundry.toml via_ir, RiskCurves fix)
- [ ] **P1** Consolidate repo copies (/root vs /home/lever — sync to /home/lever as canonical)
- [ ] **P1** Verify full test suite passes clean (forge test --summary, log results)
- [ ] **P1** Fix CLAUDE.md USDC references on root's copy (or delete after consolidation)

## Phase 2: Spec Audit (all contracts)
- [x] FixedPointMath — PASS
- [x] RiskCurves — PASS
- [x] ProbabilityIndex — PASS
- [x] OracleAdapter — ISSUES FOUND (logged)
- [ ] **P0** MarketRegistry — audit against spec
- [ ] **P0** AccountManager — audit against spec
- [ ] **P0** PositionManager — audit against spec
- [ ] **P0** LeverageModel — audit against spec
- [ ] **P0** OILimits — audit against spec
- [ ] **P0** ExecutionEngine — audit against spec
- [ ] **P0** MarginEngine — audit against spec
- [ ] **P1** BorrowFeeEngine — audit against spec
- [ ] **P1** FundingRateEngine — audit against spec
- [ ] **P1** FeeRouter — audit against spec
- [ ] **P1** LeverVault — audit against spec
- [ ] **P1** RewardsDistributor — audit against spec
- [ ] **P1** InsuranceFund — audit against spec
- [ ] **P1** LiquidationEngine — audit against spec
- [ ] **P1** SettlementEngine — audit against spec

## Phase 3: Integration Testing
- [ ] **P0** Full position lifecycle: open -> accrue fees -> close
- [ ] **P0** Liquidation flow: undercollateralized -> liquidate -> insurance fund
- [ ] **P0** Settlement flow: market resolves -> positions settle -> payouts
- [ ] **P1** Multi-market stress test
- [ ] **P1** Edge cases: max leverage, zero liquidity, oracle failure, 0/100 probability
- [ ] **P1** LP flow: deposit -> earn yield -> withdraw (80% utilization gate)

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
