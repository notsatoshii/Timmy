### 1. Fix Vault Data Display ($NaN TVL and Share Price) [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` - add error logging for 413 RPC errors and undefined returns
- [ ] 2. Check `frontend/user-app/src/components/Vault/VaultStats.tsx` for proper error handling when vault data is undefined
- [ ] 3. Verify LeverVault contract address in `frontend/user-app/src/config/contracts.ts` matches `control-plane/deploy-env.sh`
- [ ] 4. Add fallback values for TVL and share price when RPC calls fail to prevent $NaN display

### 2. Redeploy ExecutionEngine with Updated LeverageModel Address [CRITICAL] [CONTRACT]
- [ ] 1. Update `contracts/ExecutionEngine.sol` constructor to use new LeverageModel address from `control-plane/deploy-env.sh`
- [ ] 2. Run `forge script script/DeployExecutionEngine.s.sol --rpc-url base-sepolia --broadcast` to redeploy
- [ ] 3. Update `control-plane/deploy-env.sh` with new ExecutionEngine address
- [ ] 4. Grant all required roles (KEEPER, ADMIN) to new ExecutionEngine contract using cast commands

### 3. Fix Position Values Showing $0.00 [CRITICAL] [FRONTEND]
- [ ] 1. Check `frontend/user-app/src/hooks/usePositions.ts` for proper decimal scaling when fetching position data
- [ ] 2. Update `frontend/user-app/src/components/Positions/PositionRow.tsx` to handle undefined/zero position values with proper error states
- [ ] 3. Verify PositionManager contract connectivity in `frontend/user-app/src/config/contracts.ts`
- [ ] 4. Add demo position data with realistic PnL values if contract calls fail

### 4. Fix Contract Data Fetching (TVL, OI, Insurance Fund) [CRITICAL] [FRONTEND]
- [ ] 1. Debug `control-plane/dashboard.py` data collection functions with detailed RPC error logging
- [ ] 2. Test direct contract calls using `cast call` commands for LeverVault.totalAssets(), OILimits.globalOI(), InsuranceFund.balance()
- [ ] 3. Check if contracts are properly initialized by verifying required roles are granted using `cast call [CONTRACT] hasRole(ADMIN_ROLE, [DEPLOYER])`
- [ ] 4. Update frontend hooks to handle contract read failures gracefully with error boundaries

### 5. Fix Volume Calculation to Show Notional Instead of Collateral [HIGH] [FRONTEND]
- [ ] 1. Update volume calculation in `frontend/user-app/src/hooks/useMarketStats.ts` to multiply collateral × leverage for proper notional volume
- [ ] 2. Modify `frontend/user-app/src/components/Markets/MarketCard.tsx` to display "24h Volume (Notional)" instead of collateral amounts
- [ ] 3. Ensure position size calculations use notional values throughout the trading interface
- [ ] 4. Add tooltips explaining the difference between collateral and notional volume

### 6. Enable Position Opening Functionality [HIGH] [CONTRACT]
- [ ] 1. Verify new ExecutionEngine has proper access to updated LeverageModel by testing `cast call [EXECUTION_ENGINE] leverageModel()` returns correct address
- [ ] 2. Test position opening with `cast send ExecutionEngine openPosition()` using proper parameters for 5x-10x leverage
- [ ] 3. Check MarginEngine parameters are properly set by calling `cast call MarginEngine getInitialMarginRate()` 
- [ ] 4. Grant KEEPER role to deployer wallet for ExecutionEngine if position opening still fails

### 7. Fix Insurance Fund Display and Fee Flow [MEDIUM] [CONTRACT]
- [ ] 1. Check FeeRouter configuration to ensure fees are properly flowing to InsuranceFund using `cast call FeeRouter insuranceFundShare()`
- [ ] 2. Verify InsuranceFund has RECEIVER role from FeeRouter by calling `cast call FeeRouter hasRole()`
- [ ] 3. Test fee flow by opening a position and checking if InsuranceFund balance increases beyond $10K bootstrap
- [ ] 4. Update dashboard display to show proper InsuranceFund balance in USDT format not WAD

### 8. Improve Oracle Price Stability [MEDIUM] [INFRA]
- [ ] 1. Check if `control-plane/mockkeeper.py` is running with `ps aux | grep mockkeeper`
- [ ] 2. Restart oracle keeper if stopped: `python3 control-plane/mockkeeper.py` in background
- [ ] 3. Verify oracle prices are updating by checking latest price timestamps in OracleAdapter contract
- [ ] 4. Add oracle health monitoring to `control-plane/health-check.sh` script