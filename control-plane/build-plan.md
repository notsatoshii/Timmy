Looking at the QA score (60) and critical issues blocking the investor demo, here are the prioritized tasks:

### 1. Fix Vault Tab $NaN Display [CRITICAL] [FRONTEND]
- [ ] 1. Investigate useVaultMulticall returning undefined and 413 RPC errors causing $NaN share price and $0 TVL display in Vault tab

### 2. Redeploy ExecutionEngine with New LeverageModel [CRITICAL] [CONTRACT]
- [x] 2. Deploy new ExecutionEngine pointing to updated LeverageModel (0xf649e342...F9EF) to fix 1x leverage limitation blocking position opening

### 3. Fix Position Values Display [CRITICAL] [FRONTEND]  
- [ ] 3. Debug and fix $0.00 position values in demo mode - positions tab showing zero values for all metrics despite 215 active positions

### 4. Fix Volume Calculation [HIGH] [FRONTEND]
- [ ] 4. Update 24h Volume calculation to show notional value (collateral × leverage) instead of collateral only

### 5. Verify MarketDetail Tab [MEDIUM] [FRONTEND]
- [ ] 5. Test and verify MarketDetail tab functionality to ensure no critical issues before investor demo

**Target**: Achieve QA score >80 and resolve all CRITICAL blockers for investor demo readiness. Focus on fixing the three core issues: vault display, position opening, and position values.