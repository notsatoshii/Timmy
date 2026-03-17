Based on the QA report (score: 60/100) and critical blockers for the investor demo, here are the **LOCKED PRIORITIES**:

## **🔥 INVESTOR DEMO PRIORITIES (LOCKED)**

### **1. Fix Vault Tab Data Issues [CRITICAL] [FRONTEND]**
- [ ] 1. Debug useVaultMulticall returning undefined causing $NaN share price and $0 TVL in demo mode
- [ ] 2. Fix 413 RPC errors breaking vault data queries  
- [ ] 3. Verify vault tab shows real TVL ($60.5T detected by health check) and proper share price

### **2. Fix Position Values Display [CRITICAL] [FRONTEND]** 
- [ ] 1. Debug why Positions tab shows $0.00 for all position values in demo mode
- [ ] 2. Fix stub positions data to show actual position equity and PnL
- [ ] 3. Ensure position values update from real contract data, not hardcoded zeros

### **3. Verify MarketDetail Tab Functionality [CRITICAL] [FRONTEND]**
- [ ] 1. Test MarketDetail tab renders without crashes 
- [ ] 2. Verify market-specific data (probability charts, OI breakdown, rates) loads properly
- [ ] 3. Ensure navigation from Markets → MarketDetail → back to Markets works smoothly

### **4. Fix 24h Volume Calculation [MEDIUM] [DATA]**
- [ ] 1. Update volume calculation to show notional (collateral × leverage) instead of collateral only
- [ ] 2. Verify volume aggregation across all markets matches expected trading activity

### **5. ExecutionEngine Leverage Investigation [CRITICAL] [CONTRACTS]**
- [ ] 1. **INVESTIGATE ONLY** - Analyze why ExecutionEngine still uses old LeverageModel address (immutable)
- [ ] 2. Document impact on position opening failures and 1x leverage limitation
- [ ] 3. **DO NOT REDEPLOY** - Report findings for future deployment decision

**STATUS:** All tasks target the QA score improvement from 60 → 90+ for investor readiness. Focus on **data display** and **user experience** fixes only. No contract redeployments allowed per sprint lock.