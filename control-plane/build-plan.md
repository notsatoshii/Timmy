Based on the QA report and constraints, here's the corrected plan focusing on **frontend-only fixes** and infrastructure:

## Revised Investor Demo Priorities

### 1. Install Browser Dependencies [CRITICAL] [INFRASTRUCTURE]
- [ ] Install missing browser dependencies to enable screenshot functionality 
- [ ] Fix "Cannot verify UI rendering - browser dependencies missing for screenshots"
- [ ] Enable visual verification script to capture UI state for investor demo
- [ ] Generate screenshots showing working frontend tabs

### 2. Fix Frontend RPC/Contract Integration [CRITICAL] [FRONTEND]
- [ ] Debug why frontend relies on demo fallback values ($50K TVL, $30K OI) when contract calls fail
- [ ] Investigate any 413 RPC errors in browser console
- [ ] Ensure frontend displays real contract data (TVL: $60.5K, 215 positions) instead of fallbacks
- [ ] Fix any multicall failures causing undefined returns

### 3. Fix Position Values Display [CRITICAL] [FRONTEND] 
- [ ] Debug why positions tab shows $0.00 for all position values in demo mode
- [ ] Ensure position PnL, collateral, and equity use real PositionManager data
- [ ] Verify position calculations work with existing contracts (no redeployment needed)
- [ ] Replace any stub position data with actual contract state

### 4. Volume Calculation Fix [MEDIUM] [FRONTEND]
- [ ] Update 24h Volume to show notional (collateral × leverage) instead of collateral only
- [ ] Verify volume calculations display proper trading activity scale
- [ ] Test volume metrics across all trading interfaces

### 5. Complete UI Verification [MEDIUM] [FRONTEND]
- [ ] Test wallet connection flows
- [ ] Verify markets populate with real prediction market data
- [ ] Confirm no console errors or broken components
- [ ] Test complete user flows without contract changes

**Key Constraints Followed:**
- ✅ No contract redeployment (ExecutionEngine is protected)
- ✅ No address changes (contract addresses stay fixed)  
- ✅ Frontend-only fixes using existing working contracts
- ✅ Focus on display issues not contract functionality

The contracts show healthy metrics (60.5K TVL, 215 positions), so the issues are frontend integration and visual verification, not contract problems.