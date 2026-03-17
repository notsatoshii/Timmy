### 1. Fix RPC 413 Errors Blocking All Data Fetching [CRITICAL] [FRONTEND]
- [ ] 1. Investigate `frontend/user-app/src/hooks/useVaultMulticall.ts` RPC 413 errors - add retry logic and error logging to identify if it's rate limiting or wrong contract calls
- [ ] 2. Verify all contract addresses in `frontend/user-app/src/config/contracts.ts` match `control-plane/deploy-env.sh` - mismatched addresses cause multicall failures returning undefined
- [ ] 3. Add fallback RPC provider in `frontend/user-app/src/config/wagmi.ts` and implement automatic switching on 413 errors
- [ ] 4. Test multicall batching size - reduce batch size in useVaultMulticall if hitting RPC limits

### 2. Redeploy ExecutionEngine with New LeverageModel Address [CRITICAL] [CONTRACT]
- [ ] 1. Check current ExecutionEngine address in `control-plane/deploy-env.sh` and confirm it references old LeverageModel address in constructor
- [ ] 2. Deploy new ExecutionEngine pointing to LeverageModelFixed address (0xf649e342...F9EF) using `scripts/deploy-execution-engine.js`
- [ ] 3. Update ExecutionEngine address in `control-plane/deploy-env.sh` and `frontend/user-app/src/config/contracts.ts`
- [ ] 4. Verify position opening now works beyond 1x leverage using test script

### 3. Fix $NaN Share Price Display in Vault Tab [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultData.ts` sharePrice calculation - likely dividing by zero when totalSupply or totalAssets is undefined
- [ ] 2. Add null checks and fallback values in `frontend/user-app/src/components/VaultTab.tsx` to display "Loading..." instead of $NaN
- [ ] 3. Verify LeverVault.totalAssets() and LeverVault.totalSupply() are returning valid WAD values not undefined
- [ ] 4. Fix decimal conversion in sharePrice display to handle USDT (6 decimal) to WAD (18 decimal) properly

### 4. Fix Position Opening "Position Open Failed" Error [CRITICAL] [FRONTEND]
- [ ] 1. Check error handling in `frontend/user-app/src/hooks/useExecutionEngine.ts` openPosition function - capture specific revert reason
- [ ] 2. Add detailed error logging to `frontend/user-app/src/components/TradingTab.tsx` position opening flow to identify if it's ExecutionEngine limit or frontend bug
- [ ] 3. Verify MarginEngine parameters are properly set (not causing ZeroDepthThreshold errors) using health check script
- [ ] 4. Test position opening with minimal values (1 USDT, 1.1x leverage) to isolate the failure point

### 5. Fix 24h Volume Showing Collateral Instead of Notional [HIGH] [FRONTEND]
- [ ] 1. Update volume calculation in `frontend/user-app/src/hooks/useMarketData.ts` to multiply collateral by leverage: `volume = collateral * leverage`
- [ ] 2. Verify trade history events in `frontend/user-app/src/hooks/useTradeHistory.ts` are capturing both collateral and leverage values correctly
- [ ] 3. Update volume display formatting in `frontend/user-app/src/components/MarketCard.tsx` to show notional volume not just collateral
- [ ] 4. Add unit tests for volume calculation edge cases (1x leverage should equal collateral)

### 6. Add Comprehensive Error Boundaries for Data Loading [HIGH] [FRONTEND]
- [ ] 1. Wrap all data hooks in `frontend/user-app/src/components/App.tsx` with error boundaries that show specific error messages instead of generic failures
- [ ] 2. Add loading states in `frontend/user-app/src/hooks/useContractData.ts` to distinguish between "loading" and "failed to load" states
- [ ] 3. Implement retry buttons in `frontend/user-app/src/components/ErrorBoundary.tsx` for failed data fetches
- [ ] 4. Add network status indicator showing RPC connection health

### 7. Verify Oracle Keeper Service Health [MEDIUM] [INFRA]
- [ ] 1. Check `systemctl status lever-oracle-keeper` service status and restart if needed
- [ ] 2. Verify `scripts/mock_keeper.py` is updating prices in last 5 minutes using health check logs
- [ ] 3. Test price updates are flowing through OracleAdapter to frontend by checking recent price history
- [ ] 4. Add monitoring alert in `control-plane/health-check.sh` for stale prices (>10 minutes old)

### 8. Fix Insurance Fund Fee Flow from FeeRouter [MEDIUM] [CONTRACT]
- [ ] 1. Debug FeeRouter fee distribution in `contracts/FeeRouter.sol` - verify 20% is actually flowing to InsuranceFund on position opens/closes
- [ ] 2. Check if FeeRouter needs to be called manually or automatically triggers on ExecutionEngine transactions
- [ ] 3. Test fee flow using small position open/close cycle and verify InsuranceFund balance increases
- [ ] 4. Add InsuranceFund balance monitoring to `control-plane/health-check.sh`