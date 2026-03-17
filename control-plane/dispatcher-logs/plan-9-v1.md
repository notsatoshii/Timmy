### 1. Fix All Dashboard Stats Showing Empty/Error Values [CRITICAL] [FRONTEND]
- [ ] 1. Inspect `frontend/user-app/src/hooks/useVaultMulticall.ts` and add comprehensive error handling with fallback values when RPC calls fail
- [ ] 2. Check `frontend/user-app/src/hooks/useStats.ts` or similar stats hook to ensure TVL, Global OI, Insurance Fund, and Max Leverage are retrieved correctly
- [ ] 3. Add fallback demo values when contracts return undefined: TVL=$50K, Global OI=$30K, Insurance Fund=$10K, Max Leverage=12x
- [ ] 4. Update any formatting functions to handle BigInt conversion errors gracefully

### 2. Fix Position Values Displaying $0.00 in Demo Mode [CRITICAL] [FRONTEND]  
- [ ] 1. Modify `frontend/user-app/src/utils/positionCalculations.ts` to ensure PnL calculations handle demo positions correctly with non-zero entry prices
- [ ] 2. Update `frontend/user-app/src/hooks/usePositions.ts` to provide meaningful demo position data when no wallet is connected (sample positions with realistic values)
- [ ] 3. Add console logging in position value calculation flow to trace where values become zero
- [ ] 4. Ensure BigInt arithmetic in position equity calculation doesn't overflow or underflow to zero

### 3. Verify ExecutionEngine Integration with New LeverageModel [CRITICAL] [CONTRACT]
- [ ] 1. Check `control-plane/deploy-env.sh` to confirm ExecutionEngine address matches the recently deployed one (0x353DbFFD7f936A0bb4390339f33bf2e3AB3C4e9D)
- [ ] 2. Test position opening via `scripts/user-flow-test.sh` to verify the ExecutionEngine can access the new LeverageModel at 0xf649e342...F9EF  
- [ ] 3. If position opening still fails, inspect ExecutionEngine logs or contract state to identify the specific error cause
- [ ] 4. Ensure all frontend contract addresses in `frontend/user-app/src/config/contracts.ts` point to the correct ExecutionEngine

### 4. Fix Vault Share Price Showing $NaN [HIGH] [FRONTEND]
- [ ] 1. Update `frontend/user-app/src/components/VaultTab.tsx` to add null/undefined checks before calling formatUnits on sharePrice
- [ ] 2. Modify useVaultMulticall to return sensible defaults when multicall fails: sharePrice=1e6 (representing $1.00), totalAssets from last successful call
- [ ] 3. Add loading states and error boundaries specifically for vault data to prevent $NaN from appearing
- [ ] 4. Test vault tab displays "Loading..." or demo values instead of $NaN when RPC calls timeout

### 5. Fix 24h Volume Calculation to Show Notional Instead of Collateral [MEDIUM] [FRONTEND]
- [ ] 1. Locate where 24h volume is calculated (likely in `frontend/user-app/src/hooks/useTradeHistory.ts` or similar)
- [ ] 2. Modify volume calculation to multiply collateral by leverage: `volume = sum(trade.collateral * trade.leverage)` instead of `sum(trade.collateral)`
- [ ] 3. Update any volume display components to ensure the formatted values represent notional trading volume
- [ ] 4. Add unit tests for volume calculation to verify notional vs collateral distinction

### 6. Add Comprehensive Error Handling for RPC 413 Errors [HIGH] [FRONTEND]
- [ ] 1. Create a utility function `frontend/user-app/src/utils/batchMulticall.ts` that splits large multicalls into batches of 3-5 calls each
- [ ] 2. Update all hooks using multicall (useVaultMulticall, usePositions, useStats) to use the batching utility
- [ ] 3. Implement exponential backoff retry logic for failed RPC calls with 413 status codes
- [ ] 4. Add circuit breaker pattern to fall back to demo/cached data when RPC consistently fails

### 7. Verify Oracle Keeper Is Running and Updating Prices [MEDIUM] [INFRA] 
- [ ] 1. Check if `mockkeeper.py` systemd service is active: `systemctl status lever-oracle-keeper`
- [ ] 2. Verify price updates are flowing by checking recent price history in OracleAdapter contract
- [ ] 3. If keeper is down, restart using the installation script at `/tmp/install-oracle-keeper-root.sh`
- [ ] 4. Add monitoring to `control-plane/health-check.sh` to detect stale prices (>5 minutes old)

### 8. Ensure Insurance Fund Growth from Fee Flow [LOW] [CONTRACT]
- [ ] 1. Verify FeeRouter is properly configured and routing 20% of fees to InsuranceFund contract
- [ ] 2. Check recent transactions to confirm fee distribution is working when positions are opened/closed
- [ ] 3. If fees aren't flowing, investigate FeeRouter configuration or permissions
- [ ] 4. Add logging to track fee routing in `scripts/user-flow-test.sh`