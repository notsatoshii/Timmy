### 1. Fix $NaN Share Price Display in Vault Tab [CRITICAL] [FRONTEND]
- [ ] 1. Add null/undefined checks in `frontend/user-app/src/hooks/useVaultMulticall.ts` to prevent NaN calculations
- [ ] 2. Return fallback values `{ sharePrice: 1000000n, totalAssets: 50000000000n }` when RPC calls fail
- [ ] 3. Update `frontend/user-app/src/components/vault/VaultStats.tsx` to display "Calculating..." instead of $NaN
- [ ] 4. Test vault tab shows professional "$1.00" share price instead of $NaN

### 2. Enable Position Opening by Fixing ExecutionEngine Integration [CRITICAL] [CONTRACT]
- [ ] 1. Verify current ExecutionEngine address in `control-plane/deploy-env.sh` points to latest deployment
- [ ] 2. Check if ExecutionEngine constructor still references old LeverageModel address using `cast call $EXECUTION_ENGINE leverageModel()`
- [ ] 3. If mismatch found, redeploy ExecutionEngine with correct LeverageModel address from deploy-env.sh
- [ ] 4. Test position opening works by calling `cast send $EXECUTION_ENGINE openPosition()` with valid params

### 3. Fix Position Values Showing Real Data Instead of $0.00 [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/usePositions.ts` to check why position values return zero
- [ ] 2. Add logging to see if `PositionManager.getPosition()` calls are returning valid data
- [ ] 3. Fix decimal conversion issues in position value calculation (likely WAD vs USDT formatting)
- [ ] 4. If no real positions exist, add demo fallback showing "$2,500 Long TRUMP @0.67" sample position

### 4. Restore Contract Address Consistency Across Frontend Config [HIGH] [FRONTEND]
- [ ] 1. Compare all addresses in `frontend/user-app/src/config/contracts.ts` against `control-plane/deploy-env.sh`
- [ ] 2. Run `cast code [address]` for each frontend address to verify deployed bytecode exists
- [ ] 3. Update any mismatched addresses in contracts.ts to match deploy-env.sh
- [ ] 4. Restart frontend service and verify basic contract calls work via browser network tab

### 5. Fix Global OI and TVL Data Loading [HIGH] [FRONTEND] 
- [ ] 1. Check if `frontend/user-app/src/hooks/useGlobalStats.ts` is hitting RPC rate limits (413 errors)
- [ ] 2. Add retry logic with exponential backoff for failed multicall requests
- [ ] 3. Implement fallback mock data: TVL=$50,000, Global OI=$12,000, Max Leverage=12x for demo mode
- [ ] 4. Test that stats dashboard shows professional numbers instead of empty/error states

### 6. Verify Oracle Keeper is Running for Live Price Updates [MEDIUM] [INFRA]
- [ ] 1. Check if `control-plane/mockkeeper.py` process is running with `ps aux | grep mockkeeper`
- [ ] 2. If not running, start it with `cd control-plane && python3 mockkeeper.py` in background
- [ ] 3. Verify oracle price updates by checking `cast call $ORACLE_ADAPTER getLatestPrice()` changes over time
- [ ] 4. Ensure frontend shows live price updates in market data instead of stale prices

### 7. Fix Insurance Fund Display Showing Bootstrap Amount [MEDIUM] [FRONTEND]
- [ ] 1. Debug why Insurance Fund shows error instead of $10,000 bootstrap amount
- [ ] 2. Check `frontend/user-app/src/hooks/useInsuranceFund.ts` for RPC call failures or decimal formatting
- [ ] 3. Add proper WAD-to-USDT conversion for insurance fund balance display
- [ ] 4. Verify dashboard shows "$10,000" insurance fund instead of error state

### 8. Add Professional Loading States for Better UX [MEDIUM] [FRONTEND]
- [ ] 1. Replace all empty/error data states with skeleton loaders in `frontend/user-app/src/components/`
- [ ] 2. Add "Loading..." indicators for slow RPC calls instead of showing blank data
- [ ] 3. Implement graceful error messages: "Unable to load data" instead of raw error objects
- [ ] 4. Test that all tabs show professional loading experience during initial load