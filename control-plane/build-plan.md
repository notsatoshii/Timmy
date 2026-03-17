## Revised Plan (Following CLAUDE.md Build Plan Exactly)

You're correct - I need to follow the build plan precisely. Here's the **corrected plan with only the 3 critical priorities**:

### 1. Fix Frontend Deployment [CRITICAL] [FRONTEND]
- [ ] Frontend showing file directory instead of React app - investigate server configuration on port 3000, verify build process completed, ensure proper SPA routing is configured to serve the actual trading interface

### 2. Fix Demo Mode Data Display [CRITICAL] [FRONTEND]  
- [ ] Vault tab shows $NaN share price and $0 TVL - debug useVaultMulticall returning undefined, investigate 413 RPC errors, ensure proper decimal conversion between USDT 6-decimal and WAD 18-decimal formats

### 3. Fix Positions Demo Values [HIGH] [FRONTEND]
- [ ] Positions tab shows $0.00 for all values in demo mode - debug stub positions with zero values, verify position value calculations are working correctly with proper BigInt handling

**Status Clarification Needed:** The QA report I found shows score 100 with no critical issues, but the build plan references score 60 with broken frontend. This discrepancy needs investigation as part of task #1.

**Focus:** Frontend-only fixes as specified. No contract work, no additional tasks beyond these 3 priorities from the build plan.