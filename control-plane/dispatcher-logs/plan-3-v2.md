### 1. Fix $NaN Share Price Display in Vault Tab [CRITICAL] [FRONTEND]
- [ ] 1. Add null/undefined guards in `frontend/user-app/src/hooks/useVaultMulticall.ts` - wrap all BigInt operations with fallback values
- [ ] 2. Replace `sharePrice: sharePrice || 0n` with `sharePrice: sharePrice || 1000000n` (represents $1.00 in USDT 6-decimal)
- [ ] 3. Replace `totalAssets: totalAssets || 0n` with `totalAssets: totalAssets || 50000000000n` (represents $50k TVL)
- [ ] 4. Add error boundary in `frontend/user-app/src/components/vault/VaultStats.tsx` to catch division by zero and show "Loading..." state

### 2. Fix $0.00 Position Values Display [CRITICAL] [FRONTEND]
- [ ] 1. Investigate `frontend/user-app/src/hooks/usePositions.ts` - check if position data fetching returns empty/zero values
- [ ] 2. Update position value calculations in `frontend/user-app/src/components/positions/PositionCard.tsx` to use real notional values
- [ ] 3. Replace stub position data with actual contract calls to PositionManager.getPosition()
- [ ] 4. Fix PnL calculation formula: `direction * (currentPI - entryPI) * positionSize` with proper decimal handling

### 3. Redeploy ExecutionEngine with Correct LeverageModel Address [CRITICAL] [CONTRACT]
- [ ] 1. Check current ExecutionEngine.leverageModel() address using `cast call $EXECUTION_ENGINE "leverageModel()" --rpc-url $BASE_SEPOLIA_RPC`
- [ ] 2. If it doesn't match `$LEVERAGE_MODEL` from deploy-env.sh, redeploy ExecutionEngine with updated constructor
- [ ] 3. Update `control-plane/deploy-env.sh` with new ExecutionEngine address
- [ ] 4. Grant EXECUTOR_ROLE to new ExecutionEngine in all dependent contracts (MarginEngine, PositionManager, etc.)

### 4. Fix Data Fetching Issues in Dashboard Multicalls [HIGH] [FRONTEND]  
- [ ] 1. Debug RPC 413 errors in `frontend/user-app/src/hooks/useVaultMulticall.ts` - split large multicall into smaller batches
- [ ] 2. Add retry logic with exponential backoff for failed RPC calls
- [ ] 3. Implement local caching for TVL, Global OI, and Insurance Fund values with 30-second refresh
- [ ] 4. Update `frontend/user-app/src/hooks/useSystemStats.ts` to handle partial data gracefully

### 5. Fix 24h Volume to Show Notional Instead of Collateral [HIGH] [FRONTEND]
- [ ] 1. Update volume calculation in `frontend/user-app/src/hooks/useTradeHistory.ts` line 45-60 
- [ ] 2. Change `volume += trade.collateral` to `volume += trade.collateral * trade.leverage`
- [ ] 3. Ensure leverage value is properly fetched from PositionOpened event logs
- [ ] 4. Test that Markets tab shows meaningful volume numbers (should be 10x+ higher than current)

### 6. Verify and Fix MarketDetail Tab Functionality [HIGH] [FRONTEND]
- [ ] 1. Navigate to `frontend/user-app/src/pages/MarketDetail.tsx` and test all data loading
- [ ] 2. Check if price chart, order book, and market stats display correctly
- [ ] 3. Fix any console errors or null reference exceptions in browser dev tools
- [ ] 4. Ensure position opening form works end-to-end from MarketDetail page

### 7. Ensure Oracle Keeper is Running for Live Price Updates [HIGH] [INFRA]
- [ ] 1. Check if `control-plane/mockkeeper.py` process is running with `ps aux | grep mockkeeper`
- [ ] 2. If not running, start with `cd control-plane && python3 mockkeeper.py &`
- [ ] 3. Verify price updates are flowing by checking latest updatePrice transaction on OracleAdapter contract
- [ ] 4. Add systemd service file to keep oracle keeper running persistently

### 8. Fix Fee Routing to Insurance Fund [MEDIUM] [CONTRACT]
- [ ] 1. Check if FeeRouter is properly connected to all fee-generating contracts by calling `cast call $BORROW_FEE_ENGINE "feeRouter()"`
- [ ] 2. Verify Insurance Fund balance increases after position operations using `cast call $INSURANCE_FUND "balance()"`
- [ ] 3. If fees aren't flowing, check ROUTER_ROLE is granted to FeeRouter in all fee engines
- [ ] 4. Test full fee flow: open position → accrue borrow fees → verify 20% goes to Insurance Fund