### 1. Diagnose Root Cause of Failed Contract Deployments [CRITICAL] [CONTRACT]
- [ ] 1. Audit all 5 recent failed fix commits to identify systematic deployment issues using `git log --oneline -5` and `git show [commit]` for each
- [ ] 2. Verify current contract addresses in `control-plane/deploy-env.sh` match actual deployed contracts using `cast code [address]` for each contract
- [ ] 3. Check if ADMIN_ROLE, KEEPER_ROLE grants were actually applied using `cast call [contract] hasRole(0x[ADMIN_ROLE_HASH], [deployer_address])` for ExecutionEngine, LeverageModel, PositionManager
- [ ] 4. Document exact deployment failure pattern and create rollback plan before attempting new fixes

### 2. Fix ExecutionEngine and Contract Configuration [CRITICAL] [CONTRACT]
- [ ] 1. Verify LeverageModel address in ExecutionEngine constructor matches deployed LeverageModelFixed using `cast call ExecutionEngine leverageModel()` vs `$LEVERAGE_MODEL` from deploy-env.sh
- [ ] 2. If addresses don't match, redeploy ExecutionEngine with correct constructor params: `forge script script/DeployExecutionEngine.s.sol --rpc-url base-sepolia --broadcast --verify`
- [ ] 3. Grant specific roles to new ExecutionEngine: ADMIN_ROLE to deployer, KEEPER_ROLE to deployer, POSITION_MANAGER_ROLE to PositionManager using exact cast commands with role hashes
- [ ] 4. Update `control-plane/deploy-env.sh` with new ExecutionEngine address and source it in all subsequent commands

### 3. Enable Position Opening Functionality [CRITICAL] [CONTRACT]
- [ ] 1. Test position opening immediately after ExecutionEngine fix using `cast send ExecutionEngine openPosition(marketId, direction, collateralAmount, leverage)` with realistic params (marketId=1, direction=1, collateral=1000e6, leverage=5)
- [ ] 2. If position opening fails, debug specific error using `cast call ExecutionEngine openPosition()` (view version) and check revert reasons
- [ ] 3. Verify MarginEngine, OILimits, PositionManager all have proper roles granted to ExecutionEngine using `cast call [contract] hasRole([ROLE_HASH], [EXECUTION_ENGINE_ADDRESS])`
- [ ] 4. Test complete position lifecycle: open → check position data → close → verify balances using sequential cast commands

### 4. Fix Data Display Issues (TVL, Positions) [CRITICAL] [FRONTEND]
- [ ] 1. After contracts are verified working, debug RPC 413 errors in `frontend/user-app/src/hooks/useVaultMulticall.ts` by adding try-catch logging and testing direct contract calls using `cast call LeverVault totalAssets()`
- [ ] 2. Fix $NaN TVL display in `frontend/user-app/src/components/Vault/VaultStats.tsx` by adding null checks and fallback to "Loading..." instead of showing NaN calculations
- [ ] 3. Fix $0.00 position values in `frontend/user-app/src/components/Positions/PositionRow.tsx` by verifying decimal conversion from WAD (1e18) to display values and adding error states for failed contract reads
- [ ] 4. Test complete data flow: contract call → hook → component → display using browser dev tools and verify numbers match cast command outputs

### 5. Verify All Contract Interconnections [HIGH] [CONTRACT]
- [ ] 1. Create comprehensive role verification script that checks all 16 contracts have proper roles granted to each other using matrix of `cast call [contract] hasRole([role], [other_contract])`
- [ ] 2. Test cross-contract data flow: OracleAdapter → MarketRegistry → ExecutionEngine → PositionManager using sequence of cast calls to verify each step
- [ ] 3. Verify fee routing from ExecutionEngine through FeeRouter to InsuranceFund by opening test position and checking InsuranceFund balance increase
- [ ] 4. Run complete user flow test: deposit to vault → check TVL increase → open position → check position data → close position → withdraw from vault

### 6. Fix Volume Calculation to Show Notional Instead of Collateral [MEDIUM] [FRONTEND]
- [ ] 1. Update `frontend/user-app/src/hooks/useMarketStats.ts` volume calculation from `sum(collateral)` to `sum(collateral × leverage)` for proper notional volume
- [ ] 2. Change display label in `frontend/user-app/src/components/Markets/MarketCard.tsx` from "24h Volume" to "24h Volume (Notional)" with tooltip explaining difference
- [ ] 3. Ensure position size calculations use notional values in trading interface components
- [ ] 4. Test volume calculation by opening test positions with different leverage and verifying displayed volume = sum of (collateral × leverage)

### 7. Implement Comprehensive Testing and Rollback Strategy [MEDIUM] [INFRA]
- [ ] 1. Create `scripts/verify-deployment.sh` that runs all cast commands from steps 1-5 and outputs pass/fail for each contract interaction
- [ ] 2. Modify `control-plane/health-check.sh` to include contract role verification and cross-contract call tests, fail if any contract interaction errors
- [ ] 3. Create rollback procedure in case new ExecutionEngine deployment fails: document previous working addresses and restoration commands
- [ ] 4. Add Oracle health check by verifying `control-plane/mockkeeper.py` is running and prices are updating within last 10 minutes using cast timestamp checks

### 8. Stabilize Demo Environment for Investor Presentation [LOW] [INFRA]
- [ ] 1. After all fixes verified working, create demo data script that opens 3-5 sample positions with realistic PnL values using different leverage levels
- [ ] 2. Fund test wallet with sufficient USDT and ETH for smooth demo flow without transaction failures
- [ ] 3. Verify dashboard displays professional numbers: TVL >$10K, positions with varied PnL, insurance fund growing from fees
- [ ] 4. Create demo script checklist: check all numbers display correctly → test position opening → test position closing → verify fee flows