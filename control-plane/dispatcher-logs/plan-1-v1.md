### 1. Fix Vault $NaN Display and RPC 413 Errors [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultMulticall.tsx` - add error logging to identify which specific multicall is failing
- [ ] 2. Replace multicall with individual contract calls for LeverVault.totalAssets(), LeverVault.totalSupply(), and RewardsDistributor.currentYield() 
- [ ] 3. Add fallback handling for undefined values to display "Loading..." instead of $NaN
- [ ] 4. Test RPC connection limits - implement retry logic with exponential backoff for 413 rate limit errors

### 2. Fix Data Fetching Errors for All Dashboard Metrics [CRITICAL] [INFRA]
- [ ] 1. Debug `control-plane/dashboard.py` data collection functions for TVL, Global OI, Insurance Fund, Max Leverage
- [ ] 2. Add detailed error logging and exception handling to identify which contract calls are failing
- [ ] 3. Test direct contract calls using cast commands to verify contract state and accessibility
- [ ] 4. Implement data caching and retry mechanisms to handle intermittent RPC failures

### 3. Fix Position Opening Failures [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/components/trading/Trading.tsx` position opening flow
- [ ] 2. Check `ExecutionEngine.openPosition()` call parameters and ensure collateral/leverage calculations are correct
- [ ] 3. Add detailed error handling to display specific failure reasons instead of generic "Position Open Failed"
- [ ] 4. Test with minimum viable position (1x leverage) to verify basic functionality works

### 4. Redeploy ExecutionEngine with Correct LeverageModel Address [HIGH] [CONTRACT]
- [ ] 1. Update `contracts/ExecutionEngine.sol` constructor to use the new LeverageModel address (0xf649e342...F9EF)
- [ ] 2. Redeploy ExecutionEngine contract with proper role grants for ADMIN, KEEPER roles
- [ ] 3. Update `control-plane/deploy-env.sh` with new ExecutionEngine address
- [ ] 4. Grant necessary roles to ExecutionEngine in all dependent contracts (PositionManager, MarginEngine, OILimits)

### 5. Fix Position Values Showing $0.00 [HIGH] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/usePositions.tsx` to ensure position data fetching returns valid values
- [ ] 2. Check decimal scaling in position value calculations - ensure WAD (1e18) to USDT (1e6) conversion is correct
- [ ] 3. Replace stub demo positions with realistic test data that shows proper PnL calculations
- [ ] 4. Add loading states and error handling for undefined position data

### 6. Implement Working Demo Mode with Realistic Data [HIGH] [FRONTEND]
- [ ] 1. Create `frontend/user-app/src/data/demoData.ts` with realistic TVL ($2M), positions with actual PnL, and market data
- [ ] 2. Update `useIsDemoMode.tsx` to serve realistic demo data instead of empty/zero values
- [ ] 3. Ensure demo mode displays functional-looking leverage (7x-12x), proper market prices, and positive/negative PnL
- [ ] 4. Add demo mode indicator but make the platform look fully functional for investor demos

### 7. Fix Insurance Fund and Fee Flow [MEDIUM] [CONTRACT]
- [ ] 1. Debug `contracts/FeeRouter.sol` to ensure borrow fees and transaction fees are properly routing to InsuranceFund
- [ ] 2. Check if PositionManager and ExecutionEngine are calling FeeRouter.distributeFees() on position opens/closes
- [ ] 3. Verify InsuranceFund contract has proper access control to receive fee distributions
- [ ] 4. Test end-to-end fee flow with a position open/close cycle

### 8. Fix 24h Volume Calculation [MEDIUM] [FRONTEND]
- [ ] 1. Update volume calculation in `frontend/user-app/src/hooks/useMarketData.tsx` to multiply collateral by leverage for notional volume
- [ ] 2. Ensure volume aggregation includes both position opens and closes
- [ ] 3. Add proper time windowing for 24h calculation using block timestamps
- [ ] 4. Display both collateral volume and notional volume metrics for clarity