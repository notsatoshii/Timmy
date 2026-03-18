Looking at the QA score of 60 and the visual issues indicating static HTML instead of a functioning React app, here are the prioritized tasks:

### 1. Fix React App Loading [CRITICAL] [FRONTEND]
- [ ] 1. Investigate why QA is seeing static HTML instead of the live React application - score dropped to 60 due to inability to verify actual functionality
- [ ] 2. Ensure frontend service is properly running and accessible at port 3000
- [ ] 3. Test wallet connectivity and smart contract integration flows
- [ ] 4. Verify trading interface loads with real market data and positions

### 2. Verify Oracle Price Feeds [HIGH] [BACKEND]  
- [ ] 1. Confirm mockkeeper.py oracle service is running and updating prices
- [ ] 2. Check that prices.json is being updated regularly (currently shows as modified)
- [ ] 3. Test that frontend displays live price updates, not stale data
- [ ] 4. Ensure price staleness doesn't break trading during investor demo

### 3. Test End-to-End Trading Flow [HIGH] [INTEGRATION]
- [ ] 1. Open actual leveraged positions (5x, 10x, 15x) and verify they display correctly
- [ ] 2. Test position management (partial closes, full closes) 
- [ ] 3. Confirm real-time PnL updates and margin calculations
- [ ] 4. Verify all trading features work with live wallet connections

### 4. Fix Fee Flow Issues [MEDIUM] [BACKEND]
- [ ] 1. Debug why Insurance Fund stuck at $10K bootstrap instead of receiving 20% fee share
- [ ] 2. Investigate LP APY calculation showing only 0.21% 
- [ ] 3. Verify FeeRouter is properly distributing fees (50/30/20 split)
- [ ] 4. Test that trading activity increases Insurance Fund balance

### 5. Professional Demo Polish [MEDIUM] [FRONTEND]
- [ ] 1. Ensure all tabs (Trading, Positions, Markets, Vault) display professional data
- [ ] 2. Verify no $NaN, $0.00, or error boundary crashes visible
- [ ] 3. Test responsive design and clean UI presentation
- [ ] 4. Confirm key metrics (TVL $68.5M, 263 positions) display prominently

**Focus**: The React app loading issue is blocking proper QA verification. Once fixed, the score should improve significantly as actual functionality can be tested.