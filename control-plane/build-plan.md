Based on the current QA status (60/100) and known issues, here are the prioritized tasks for the investor demo:

### 1. Verify MarketDetail Tab Functionality [CRITICAL] [FRONTEND]
- [ ] Complete end-to-end testing of MarketDetail tab navigation and display
- [ ] Ensure realistic position/market data renders without errors  
- [ ] Take verification screenshots to confirm demo readiness
- [ ] Document any remaining display issues for quick fixes

### 2. Fix 24h Volume Display (Notional vs Collateral) [CRITICAL] [FRONTEND] 
- [ ] Update volume calculation to show notional value (collateral × leverage)
- [ ] Verify volume displays consistently across all tabs
- [ ] Ensure realistic demo-appropriate volume figures
- [ ] Test edge cases (zero volume, high leverage positions)

### 3. Address Visual Demo Issues [HIGH] [FRONTEND]
- [ ] Reduce prominence of "Demo Mode" and testnet indicators for investor presentation
- [ ] Add sample realistic user balances for demo flow (no fake data, use test accounts)
- [ ] Implement clean demo state that shows product maturity
- [ ] Verify read-only mode banner doesn't overshadow functionality

### 4. Insurance Fund Status Investigation [MEDIUM] [BACKEND]
- [ ] Investigate if $5.011e24 display is WAD formatting issue vs actual stuck bootstrap
- [ ] Verify FeeRouter fee flow to Insurance Fund without redeploying contracts
- [ ] Document whether 0.017% capitalization ratio is acceptable for demo
- [ ] Check if manual fee injection is needed for demo presentation

### 5. Oracle Keeper Health Monitoring [LOW] [INFRASTRUCTURE]
- [ ] Verify mockkeeper.py is running and maintaining fresh price feeds
- [ ] Monitor price staleness during demo preparation window  
- [ ] Ensure backup oracle activation if needed for demo stability
- [ ] Document oracle status for investor technical questions

**Focus Order:** Tasks 1-2 are critical blockers, Task 3 addresses investor perception, Tasks 4-5 are monitoring/investigation only.