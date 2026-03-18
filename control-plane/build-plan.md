Based on the build-plan.md and current QA status, here are the 3 prioritized tasks for the investor demo:

### 1. **Frontend Interface Verification [CRITICAL] [DEMO]**
- [ ] Test actual frontend at localhost:3000 in browser (QA shows 100 score but need visual confirmation)
- [ ] Verify all investor-facing features render and function properly 
- [ ] Validate trading interface loads with real market data and positions display correctly

### 2. **MarketDetail Tab Implementation [CRITICAL] [DEMO]**
- [ ] Complete MarketDetail tab verification and testing (known critical issue)
- [ ] Ensure market-specific data displays correctly for investor evaluation
- [ ] Test navigation and data accuracy within market detail views

### 3. **24h Volume Display Fix [CRITICAL] [DATA]**
- [ ] Fix 24h Volume to show notional value (collateral × leverage) instead of collateral only
- [ ] Verify volume calculations align with investor expectations for trading metrics
- [ ] Update frontend components to display proper trading volume metrics

**Status**: QA reports 100/100 score but critical issues remain. Focus on these 3 demo blockers before Phase 2 transition.