Looking at the QA report (score: 60/100) and known issues, here are the prioritized tasks for the investor demo:

### 1. Verify MarketDetail Tab Functionality [CRITICAL] [FRONTEND]
- [ ] Test and verify MarketDetail tab displays correctly with real market data
- [ ] Ensure navigation, price charts, and market metadata render properly
- [ ] Document any blockers preventing investor demo readiness

### 2. Fix 24h Volume Calculation [CRITICAL] [FRONTEND] 
- [ ] Correct volume display to show notional value (collateral × leverage) instead of collateral only
- [ ] Verify calculation matches protocol logic: position_size = collateral × leverage
- [ ] Test with multiple positions at different leverage levels

### 3. Improve Loading States for Professional Demo [HIGH] [FRONTEND]
- [ ] Add loading spinners/skeleton screens for initial app load
- [ ] Implement proper error boundaries with user-friendly messages  
- [ ] Add meaningful content during JavaScript loading to prevent blank screen

### 4. Verify Oracle Price Updates [MEDIUM] [OPERATIONS]
- [ ] Check if mockkeeper.py oracle service is running and updating prices
- [ ] Ensure prices don't go stale during demo period
- [ ] Verify price feeds are realistic for investor presentation

### 5. Investigate Insurance Fund Fee Flow [MEDIUM] [CONTRACTS]
- [ ] Determine why Insurance Fund stuck at $10K bootstrap despite $60.5M TVL
- [ ] Verify FeeRouter is properly routing 20% of fees to InsuranceFund
- [ ] Check if fee accumulation requires manual trigger or should be automatic

**Current Status:** Frontend UP, contracts healthy ($60.5M TVL, 226 positions), but professional presentation needs improvement for investor demo.