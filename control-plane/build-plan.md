Based on the QA report showing a broken frontend (score 60, trust score 1) and critical demo blockers, here are the prioritized tasks:

### 1. Fix Frontend Deployment [CRITICAL] [FRONTEND]
- [ ] 1. Frontend showing file directory instead of React app - investigate server configuration on port 3000, verify build process completed, ensure proper SPA routing is configured to serve the actual trading interface

### 2. Fix Demo Mode Data Display [CRITICAL] [FRONTEND]  
- [ ] 2. Vault tab shows $NaN share price and $0 TVL - debug useVaultMulticall returning undefined, investigate 413 RPC errors, ensure proper decimal conversion between USDT 6-decimal and WAD 18-decimal formats

### 3. Fix Positions Demo Values [HIGH] [FRONTEND]
- [ ] 3. Positions tab shows $0.00 for all values in demo mode - debug stub positions with zero values, verify position value calculations are working correctly with proper BigInt handling

### 4. Verify MarketDetail Functionality [HIGH] [FRONTEND]
- [ ] 4. MarketDetail tab verification - test all market detail page functionality, ensure proper data loading and display, confirm no error boundary crashes

### 5. Address ExecutionEngine/LeverageModel Mismatch [HIGH] [CONTRACTS]
- [x] 5. Document ExecutionEngine limitation (uses old LeverageModel address, positions limited to 1x leverage) - investigate workarounds since redeployment is blocked, or plan for post-demo fix

**Note**: Focusing on frontend fixes first since the visual issues are completely blocking the demo experience. Contract functionality appears stable based on QA checks.