Looking at the current state with QA score 100 but critical demo blockers identified, I'll prioritize the most impactful frontend fixes that can be completed without contract redeployment:

### 1. Fix Vault Tab $NaN Share Price and $0 TVL Display [CRITICAL] [FRONTEND]
- [ ] Debug useVaultMulticall returning undefined causing $NaN share price
- [ ] Investigate 413 RPC errors blocking vault data loading
- [ ] Ensure vault TVL displays correctly in demo mode
- [ ] Test vault tab functionality end-to-end

### 2. Fix Positions Tab $0.00 Values in Demo Mode [CRITICAL] [FRONTEND]  
- [ ] Debug stub positions showing zero values instead of actual position data
- [ ] Fix position value calculations and display formatting
- [ ] Verify position PnL, collateral, and size display correctly
- [ ] Test positions tab with real trading data

### 3. Fix 24h Volume to Show Notional Not Collateral [HIGH] [FRONTEND]
- [ ] Update volume calculation to multiply collateral × leverage for true notional volume
- [ ] Verify volume aggregation across all positions and markets
- [ ] Test volume display accuracy with various leverage levels
- [ ] Ensure volume updates in real-time

### 4. Verify and Test MarketDetail Tab Functionality [MEDIUM] [FRONTEND]
- [ ] Complete end-to-end testing of MarketDetail tab
- [ ] Verify all market data displays correctly (price, volume, OI)
- [ ] Test market-specific trading functionality
- [ ] Document any issues found for future fixing

### 5. Investigate Oracle Keeper Status [MEDIUM] [BACKEND]
- [ ] Check if mockkeeper.py is running and updating prices
- [ ] Verify price feed freshness and update frequency  
- [ ] Ensure oracle data flows correctly to frontend
- [ ] Test price updates with mock market movements

**Priority Focus:** Tasks 1-3 are critical demo blockers. Task 1 (Vault tab) is highest priority as it affects core LP functionality display. All tasks avoid contract redeployment per current sprint constraints.