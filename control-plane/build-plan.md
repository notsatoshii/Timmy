Based on the QA report (score: 52/100) and critical blockers, here are the prioritized tasks for the investor demo:

### 1. Fix Frontend Visual Verification [CRITICAL] [FRONTEND]
- [ ] 1. Verify React app actually loads in browser (QA shows only HTML shell visible)
- [ ] 2. Take proper screenshots of trading interface, markets, and LP tabs
- [ ] 3. Test that core UI components render without JavaScript errors or crashes

### 2. Resolve RPC Data Issues [CRITICAL] [FRONTEND] 
- [ ] 1. Fix Vault tab showing $NaN share price and $0 TVL (useVaultMulticall RPC 413 errors)
- [ ] 2. Fix Positions tab displaying $0.00 for all position values (replace stub data with real values)  
- [ ] 3. Ensure proper USDT decimal handling (6-decimal) vs WAD conversion (18-decimal)

### 3. Enable Position Opening [CRITICAL] [CONTRACTS]
- [ ] 1. Redeploy ExecutionEngine with new LeverageModel address (0xf649e342...F9EF) 
- [ ] 2. Test position opening flow end-to-end to resolve "Position Open Failed" errors
- [ ] 3. Verify leverage limits now work beyond 1x (LeverageModel fix should enable 12x platform ceiling)

### 4. Polish Demo Data Display [HIGH] [FRONTEND]
- [ ] 1. Fix 24h Volume to show notional (collateral × leverage) instead of collateral only
- [ ] 2. Add professional loading states and error messages for better UX
- [ ] 3. Verify all market statistics display real data vs placeholder content

### 5. Verify System Health [HIGH] [OPERATIONS]
- [ ] 1. Confirm oracle keeper (mockkeeper.py) is running to prevent stale prices
- [ ] 2. Test complete user journey: connect wallet → view markets → open position → check portfolio
- [ ] 3. Validate responsive design works on mobile for investor presentation

**Current Blockers:** Frontend visibility (can't verify React loads), RPC errors causing $NaN display, ExecutionEngine using outdated LeverageModel address.