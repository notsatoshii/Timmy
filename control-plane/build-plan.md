Based on the QA report (score 44/100) and known critical issues blocking the investor demo, here are the prioritized tasks:

### 1. **Fix Frontend Deployment [CRITICAL] [DEMO]**
- [ ] Frontend serving directory listing instead of React app at localhost:3000
- [ ] Fix React build/serve configuration to display actual trading platform
- [ ] Verify professional UI loads with LEVER branding and trading interface
- [ ] Test all tabs render properly (Trading, Positions, Vault, Markets)

### 2. **Complete MarketDetail Tab [CRITICAL] [DEMO]** 
- [ ] Implement and verify MarketDetail tab functionality (known critical blocker)
- [ ] Ensure market-specific data displays correctly for investor evaluation
- [ ] Test market navigation and data accuracy in detail views

### 3. **Fix 24h Volume Display [CRITICAL] [DATA]**
- [ ] Update volume calculation from collateral-only to notional (collateral × leverage) 
- [ ] Correct trading metrics for investor-facing dashboard
- [ ] Verify volume displays align with expected trading activity levels

### 4. **Verify Oracle Price Updates [MEDIUM] [INFRA]**
- [ ] Check mockkeeper.py oracle service status to prevent stale prices
- [ ] Ensure live price feeds for investor demo markets  
- [ ] Test price update frequency and market responsiveness

### 5. **Insurance Fund Flow Verification [MEDIUM] [FINANCE]**
- [ ] Investigate why Insurance Fund stuck at $10K bootstrap value
- [ ] Verify FeeRouter properly directing 20% fees to Insurance Fund
- [ ] Ensure fee distribution visible to investors

**Priority**: Fix frontend deployment first (investor demo blocker), then MarketDetail tab and volume display. All must pass before Phase 2 transition.