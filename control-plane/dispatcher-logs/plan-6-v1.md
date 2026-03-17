### 1. Fix React Frontend Build Deployment [CRITICAL] [FRONTEND]
- [ ] 1. Check if `frontend/user-app/dist/index.html` exists and contains proper React app build, not file directory listing
- [ ] 2. Verify `frontend/user-app/vite.config.ts` has correct build output directory and base path configuration
- [ ] 3. Run `cd frontend/user-app && npm run build` to rebuild production assets and ensure dist/ contains proper HTML/JS files
- [ ] 4. Restart lever-frontend systemd service and verify http://localhost:3000 shows actual React app, not file browser

### 2. Fix RPC 413 Errors Breaking All Data Fetching [CRITICAL] [FRONTEND]
- [ ] 1. Add error logging and retry logic to `frontend/user-app/src/hooks/useVaultMulticall.ts` to handle 413 rate limit errors
- [ ] 2. Reduce multicall batch size in useVaultMulticall from current batching to smaller chunks (max 5 calls per batch)
- [ ] 3. Add fallback RPC provider in `frontend/user-app/src/config/wagmi.ts` with automatic switching on 413 errors
- [ ] 4. Verify all contract addresses in `frontend/user-app/src/config/contracts.ts` exactly match `control-plane/deploy-env.sh` deployed addresses

### 3. Redeploy ExecutionEngine with Fixed LeverageModel Address [CRITICAL] [CONTRACT]
- [ ] 1. Check current ExecutionEngine address in `control-plane/deploy-env.sh` and verify it uses old LeverageModel address in constructor
- [ ] 2. Deploy new ExecutionEngine contract pointing to LeverageModelFixed address (0xf649e342...F9EF) using `scripts/deploy.s.sol`
- [ ] 3. Update EXECUTION_ENGINE address in `control-plane/deploy-env.sh` with new deployment
- [ ] 4. Test position opening with leverage >1x using `scripts/user-flow-test.sh` to confirm ExecutionEngine fix works

### 4. Fix Position Display Showing $0.00 Values [HIGH] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/usePositions.ts` to identify why position values return zero instead of actual collateral/PnL
- [ ] 2. Verify PositionManager contract calls in usePositions hook are using correct function signatures and parsing responses properly
- [ ] 3. Fix any BigInt/decimal conversion errors in position value calculations similar to recent useTradeHistory.ts fixes
- [ ] 4. Add fallback demo positions in `frontend/user-app/src/components/positions/PositionsTab.tsx` if real data still fails

### 5. Fix Vault Tab NaN Share Price Display [HIGH] [FRONTEND]  
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` undefined return values causing NaN calculations in VaultTab
- [ ] 2. Add null checks and default values in `frontend/user-app/src/components/vault/VaultTab.tsx` for when multicall fails
- [ ] 3. Verify LeverVault share price calculation uses correct decimal conversion (USDT 6-decimal vs WAD 18-decimal)
- [ ] 4. Test vault deposit/withdrawal flow works end-to-end with proper share price display

### 6. Verify Oracle Price Updates Are Live [MEDIUM] [INFRA]
- [ ] 1. Check `systemctl status lever-oracle-keeper` to confirm oracle keeper service is running and updating prices
- [ ] 2. Monitor oracle keeper logs with `journalctl -u lever-oracle-keeper -f` for 2 minutes to verify price update frequency
- [ ] 3. Check OracleAdapter contract state to confirm lastUpdated timestamp is recent (within last 5 minutes)
- [ ] 4. If keeper not running, restart with `systemctl restart lever-oracle-keeper` and verify price updates resume

### 7. Test and Fix Basic Trading User Flow [MEDIUM] [FRONTEND]
- [ ] 1. Run `scripts/user-flow-test.sh` to test complete trading flow: connect wallet → deposit → open position → view position
- [ ] 2. Fix any "Position Open Failed" errors in `frontend/user-app/src/components/trading/TradingTab.tsx` by debugging ExecutionEngine interaction
- [ ] 3. Verify trading tab shows real market data (not placeholder) and allows actual position opening with leverage >1x
- [ ] 4. Test position closing flow works and updates position display correctly