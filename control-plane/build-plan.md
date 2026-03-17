Looking at the QA report (score: 60) and critical issues blocking the investor demo, I'll prioritize the most urgent frontend fixes:

### 1. Fix Vault Tab Data Issues [CRITICAL] [FRONTEND]
- [ ] 1. Resolve $NaN share price and $0 TVL in vault tab - investigate useVaultMulticall returning undefined and 413 RPC errors. This completely breaks the LP experience for demo.

### 2. Fix Position Values Display [CRITICAL] [FRONTEND] 
- [ ] 2. Resolve positions showing $0.00 for all values in demo mode - debug stub positions data formatting and ensure position equity/PnL calculations display correctly.

### 3. Fix Volume Calculation [HIGH] [FRONTEND]
- [ ] 3. Update 24h volume to show notional (collateral × leverage) instead of just collateral amount - affects market statistics and trading metrics accuracy.

### 4. Verify MarketDetail Tab [HIGH] [FRONTEND]
- [ ] 4. Test and verify MarketDetail tab functionality works correctly for the demo - ensure market information, charts, and trading interface render properly.

### 5. Investigate Position Opening Limitation [MEDIUM] [SYSTEM]
- [x] 5. Document ExecutionEngine/LeverageModel mismatch causing 1x leverage limit and "Position Open Failed" errors - prepare workaround or escalation plan since contract redeployment is restricted.

**Note:** Focusing on frontend fixes first since contract redeployment is restricted per build plan. The ExecutionEngine limitation (#5) may require architectural discussion before proceeding.