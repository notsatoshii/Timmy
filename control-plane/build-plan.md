Looking at the QA report and critical issues blocking investor demo readiness, here are the prioritized tasks:

### 1. Fix Vault Data Pipeline [CRITICAL] [FRONTEND]
- [ ] Resolve useVaultMulticall returning undefined causing $NaN share price and $0 TVL display
- [ ] Debug and fix 413 RPC timeout errors in vault data fetching
- [ ] Ensure vault tab shows accurate TVL and share price for investor demo

### 2. Fix Position Values Display [CRITICAL] [FRONTEND] 
- [ ] Debug positions showing $0.00 for all values despite claiming real on-chain data
- [ ] Verify getPosition() calls are working correctly and returning proper equity/PnL/collateral
- [ ] Replace any remaining stub position data with actual on-chain values

### 3. Resolve ExecutionEngine Leverage Limitation [CRITICAL] [CONTRACTS]
- [ ] Address ExecutionEngine using old LeverageModel causing 1x leverage limit
- [ ] Fix "Position Open Failed" errors in frontend position opening
- [ ] Ensure platform can demonstrate full leverage functionality to investors

### 4. Fix Contract Data Pipeline Errors [HIGH] [BACKEND]
- [ ] Resolve all error status showing in contract data pipeline (TVL, Positions, Global OI, Insurance Fund)
- [ ] Debug and fix 413 RPC errors preventing reliable data retrieval
- [ ] Implement proper error handling to hide technical errors from investor-facing interface

### 5. Verify MarketDetail Functionality [MEDIUM] [FRONTEND]
- [ ] Complete verification testing of MarketDetail tab
- [ ] Ensure all market information displays correctly for investor walkthrough
- [ ] Test end-to-end market browsing and position opening flow

**Focus**: All tasks target the vision review issues (score: 44, professional_score: 3, trust_score: 2) to ensure investor demo credibility.