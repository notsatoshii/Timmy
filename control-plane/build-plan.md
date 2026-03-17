Based on the QA report showing a score of 60 with critical frontend failures, here are the prioritized tasks to fix the investor demo:

### 1. CRITICAL: Fix Frontend Server Configuration [CRITICAL] [FRONTEND]
- [ ] Frontend completely broken - shows file directory listing instead of LEVER Protocol application
- [ ] Fix 'serve' command configuration to properly serve React SPA at root path  
- [ ] Restart with 'npm start' or fix serve routing to load index.html at root
- [ ] Verify investors can access http://localhost:3000 and see actual trading interface

### 2. CRITICAL: Fix Demo Mode Data Display [CRITICAL] [FRONTEND]  
- [ ] Fix Vault tab showing $NaN share price and $0 TVL (useVaultMulticall returning undefined)
- [ ] Fix Positions tab showing $0.00 for all position values (stub positions with zero values)
- [ ] Handle 413 RPC errors gracefully with fallback data for investor demo
- [ ] Ensure all financial metrics display realistic demo values

### 3. CRITICAL: Fix Position Opening Functionality [CRITICAL] [CONTRACTS]
- [ ] ExecutionEngine uses old LeverageModel address - positions limited to 1x leverage
- [ ] Investigate ExecutionEngine redeploy requirement vs workaround options
- [ ] Fix "Position Open Failed" error blocking core trading functionality
- [ ] Verify position opening works at intended 12x leverage levels

### 4. HIGH: Professional Branding and Error Handling [HIGH] [FRONTEND] 
- [ ] Update document title from generic 'React App' to 'LEVER Protocol'
- [ ] Implement proper error handling and fallback pages for service failures
- [ ] Add professional loading states and error messages for investor presentation
- [ ] Verify MarketDetail tab functionality and routing

### 5. MEDIUM: Volume and Fee Flow Verification [MEDIUM] [DATA]
- [ ] Fix 24h Volume showing collateral only instead of notional (collateral × leverage)  
- [ ] Verify Insurance Fund fee flow through FeeRouter (currently stuck at $10K bootstrap)
- [ ] Confirm oracle keeper (mockkeeper.py) is running to prevent stale prices
- [ ] Test complete user flow from market browsing to position management

**Target**: Achieve QA score >85 with all critical visual and functional issues resolved for investor demo.