### 1. Fix Vault $NaN Share Price and $0 TVL Display [CRITICAL] [FRONTEND]
- [ ] 1. Modify `frontend/user-app/src/hooks/useVaultMulticall.ts` to split large multicall into smaller batches (max 5 calls each) to avoid 413 RPC errors
- [ ] 2. Add comprehensive error handling in useVaultMulticall to return fallback values: `{ sharePrice: 1000000n, totalSupply: 0n, totalAssets: 0n }` when multicall fails
- [ ] 3. Update `frontend/user-app/src/components/VaultTab.tsx` to check for undefined/null values before formatting, display "Loading..." instead of $NaN

### 2. Fix All Position Values Showing $0.00 [CRITICAL] [FRONTEND]
- [ ] 1. Inspect `frontend/user-app/src/hooks/usePositions.ts` to identify why position values return zero in demo mode
- [ ] 2. Check if position PnL calculation in `frontend/user-app/src/utils/positionCalculations.ts` handles BigInt conversions correctly
- [ ] 3. Add debugging console.log to trace position value flow from contract calls through formatting to display

### 3. Deploy New ExecutionEngine to Fix Position Opening [CRITICAL] [CONTRACT]
- [ ] 1. Update `contracts/ExecutionEngine.sol` constructor to use new LeverageModel address `0xf649e342...F9EF` instead of old address
- [ ] 2. Run `forge script script/deployments/DeployExecutionEngine.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast`
- [ ] 3. Update `control-plane/deploy-env.sh` with new ExecutionEngine address and run `source control-plane/deploy-env.sh`

### 4. Fix 24h Volume to Show Notional Instead of Collateral [HIGH] [FRONTEND]
- [ ] 1. Locate volume calculation in `frontend/user-app/src/hooks/useTradeHistory.ts` or similar hook
- [ ] 2. Modify calculation from `collateral` to `collateral * leverage` to show actual notional trading volume
- [ ] 3. Update volume display formatting to handle larger numbers appropriately

### 5. Restart Oracle Keeper to Ensure Live Price Updates [HIGH] [INFRA]
- [ ] 1. Check if `control-plane/mock_keeper.py` process is running with `ps aux | grep mock_keeper`
- [ ] 2. If not running, restart with `cd control-plane && python3 mock_keeper.py &` and verify price updates in dashboard
- [ ] 3. Ensure systemd service `lever-keeper` is enabled with `sudo systemctl enable lever-keeper && sudo systemctl start lever-keeper`

### 6. Update Frontend Contract Addresses After ExecutionEngine Deployment [HIGH] [FRONTEND]
- [ ] 1. After ExecutionEngine redeployment, update `frontend/user-app/src/config/contracts.ts` with new ExecutionEngine address
- [ ] 2. Regenerate contract ABIs with `cd frontend/user-app && npm run generate:abis`
- [ ] 3. Restart frontend service with `sudo systemctl restart lever-frontend` to apply new addresses

### 7. Add Position Opening Error Handling and User Feedback [MEDIUM] [FRONTEND]
- [ ] 1. Enhance error handling in `frontend/user-app/src/components/TradeForm.tsx` to display specific error reasons instead of generic "Position Open Failed"
- [ ] 2. Add loading states during position opening to show transaction is processing
- [ ] 3. Display success/failure toast notifications with transaction hash links to Base Sepolia explorer

### 8. Verify FeeRouter Integration to Fix Insurance Fund Growth [MEDIUM] [CONTRACT]
- [ ] 1. Check if FeeRouter is properly connected to other contracts by reading `contracts/FeeRouter.sol` state variables
- [ ] 2. Verify fee distribution is working by calling FeeRouter view functions in forge console
- [ ] 3. Test fee flow with small position opening/closing to confirm Insurance Fund receives 20% share