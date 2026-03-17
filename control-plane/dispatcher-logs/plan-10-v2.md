### 1. Fix Homepage Not Loading - Shows File Directory Instead of Trading Platform [CRITICAL] [FRONTEND]
- [ ] 1. Check `frontend/user-app/dist/` directory to ensure React build files exist and index.html is present
- [ ] 2. Verify `frontend/user-app/vite.config.ts` has correct build output configuration pointing to `dist/`
- [ ] 3. Inspect frontend service configuration - check if it's serving from wrong directory (showing file listing instead of React app)
- [ ] 4. Run `cd frontend/user-app && npm run build` to regenerate production build and restart frontend service

### 2. Fix All Dashboard Stats Showing Error/Empty Values [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` - add console.log to identify why RPC calls return undefined and cause 413 errors
- [ ] 2. Modify `useVaultMulticall.ts` to implement exponential backoff retry logic for failed RPC calls with 3 retry attempts
- [ ] 3. Add fallback demo values when RPC fails: TVL=$50,000, Global OI=$30,000, Insurance Fund=$10,000, Max Leverage=12x
- [ ] 4. Update BigInt formatting functions to handle undefined/null values gracefully without throwing NaN errors

### 3. Investigate and Fix Position Opening Failure [CRITICAL] [FRONTEND]
- [ ] 1. Verify `frontend/user-app/src/config/contracts.ts` has correct ExecutionEngine address (should be 0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D from protected contracts)
- [ ] 2. Debug position opening flow in browser console - check if frontend is calling correct ExecutionEngine functions and passing proper parameters
- [ ] 3. Test ExecutionEngine contract directly via forge scripts to verify it's working correctly with current LeverageModel address
- [ ] 4. Investigate if position opening failure is due to insufficient allowances, wrong market IDs, or incorrect function call parameters in frontend

### 4. Fix Position Values Showing $0.00 in Demo Mode [CRITICAL] [FRONTEND]
- [ ] 1. Modify `frontend/user-app/src/hooks/usePositions.ts` to return meaningful demo positions when no wallet connected: sample positions with entry_pi=0.6, current_pi=0.65, notional=1000, leverage=5x
- [ ] 2. Update `frontend/user-app/src/utils/positionCalculations.ts` calculatePnL function to handle demo position data correctly with realistic PnL values
- [ ] 3. Ensure position equity, unrealized PnL, and position size calculations use demo values instead of returning zero
- [ ] 4. Add demo position data with different market types (election, sports) and both long/short positions

### 5. Fix 24h Volume Showing Collateral Instead of Notional [MEDIUM] [FRONTEND]
- [ ] 1. Locate volume calculation in `frontend/user-app/src/hooks/useStats.ts` or similar stats hook
- [ ] 2. Modify volume calculation to multiply collateral by leverage: `volume = collateral * leverage` instead of just collateral
- [ ] 3. Update any trade history hooks to calculate notional volume correctly for both real and demo data
- [ ] 4. Ensure volume formatting handles larger numbers appropriately (K, M suffixes)

### 6. Improve Demo Mode User Experience [MEDIUM] [FRONTEND]
- [ ] 1. Add prominent "DEMO MODE" indicator to top of all pages when no wallet is connected
- [ ] 2. Create realistic demo market data in `frontend/user-app/src/data/demoData.ts` with live-looking prices that update periodically
- [ ] 3. Implement demo mode toggle in header to switch between demo and wallet-connected states for testing
- [ ] 4. Add tooltips explaining demo mode functionality and encouraging wallet connection for real trading

### 7. Add Comprehensive Error Handling for RPC Failures [HIGH] [FRONTEND]
- [ ] 1. Create `frontend/user-app/src/utils/rpcErrorHandler.ts` with standardized error handling for all contract calls
- [ ] 2. Implement circuit breaker pattern to temporarily use cached/demo data when RPC calls consistently fail
- [ ] 3. Add user-friendly error messages when blockchain data is unavailable instead of showing $NaN
- [ ] 4. Log RPC errors to console with timestamps for debugging while maintaining user experience

### 8. Optimize Frontend Performance and Loading [MEDIUM] [FRONTEND]
- [ ] 1. Check `frontend/user-app/src/App.tsx` for unnecessary re-renders and optimize React component structure
- [ ] 2. Implement loading states in all data hooks to show spinners instead of empty/error states while data loads
- [ ] 3. Add React.memo to expensive components and useMemo for heavy calculations
- [ ] 4. Reduce RPC call frequency by implementing smart caching with 30-second refresh intervals for stats