### 1. Fix React Frontend Build to Show Actual App Interface [CRITICAL] [FRONTEND]
- [ ] 1. Check if `frontend/user-app/dist/index.html` exists and verify its content is not a file directory listing
- [ ] 2. Run `cd frontend/user-app && rm -rf dist && npm run build` to force clean rebuild of React production assets
- [ ] 3. Verify `dist/index.html` contains proper React app bundle references, not file browser HTML
- [ ] 4. Restart `sudo systemctl restart lever-frontend` and confirm http://localhost:3000 shows trading interface, not file directory

### 2. Fix $NaN Vault Data and $0 TVL Display [CRITICAL] [FRONTEND] 
- [ ] 1. Add error handling in `frontend/user-app/src/hooks/useVaultMulticall.ts` to return fallback values when multicall fails
- [ ] 2. Reduce RPC batch size in useVaultMulticall from current batching to max 3 calls per batch to avoid 413 errors
- [ ] 3. Add null/undefined checks in `frontend/user-app/src/components/VaultTab.tsx` before formatting values as currency
- [ ] 4. Test vault tab shows real values like "$1,000" instead of "$NaN"

### 3. Deploy New ExecutionEngine to Fix Position Opening [CRITICAL] [CONTRACT]
- [ ] 1. Update `contracts/ExecutionEngine.sol` constructor to use new LeverageModel address `0xf649e342...F9EF` 
- [ ] 2. Run `cd contracts && forge script script/deploy/DeployExecutionEngine.s.sol --broadcast --rpc-url $BASE_SEPOLIA_RPC`
- [ ] 3. Update `control-plane/deploy-env.sh` with new ExecutionEngine address
- [ ] 4. Update `frontend/user-app/src/config/contracts.ts` with new ExecutionEngine address to enable >1x position opening

### 4. Fix Position Values Showing $0.00 in Demo Mode [HIGH] [FRONTEND]
- [ ] 1. Update stub position data in `frontend/user-app/src/hooks/usePositions.ts` to use realistic values (notional: 1000, collateral: 100, PnL: 50)
- [ ] 2. Fix decimal formatting in position display components to handle 6-decimal USDT vs 18-decimal WAD conversion
- [ ] 3. Add error boundaries around position value calculations to prevent $0.00 fallbacks
- [ ] 4. Test positions tab shows "$1,000" notional, "$100" collateral instead of "$0.00"

### 5. Fix 24h Volume to Show Notional Instead of Collateral [MEDIUM] [FRONTEND]
- [ ] 1. Update volume calculation in `frontend/user-app/src/hooks/useMarketData.ts` to multiply collateral by leverage for notional value
- [ ] 2. Change volume display formula from `sum(collateral)` to `sum(collateral * leverage)` in market stats
- [ ] 3. Add unit test to verify volume calculation includes leverage multiplier
- [ ] 4. Verify markets tab shows higher volume numbers reflecting true notional trading activity

### 6. Add Fallback RPC Provider for 413 Rate Limit Resilience [MEDIUM] [FRONTEND]
- [ ] 1. Add secondary RPC endpoint in `frontend/user-app/src/config/wagmi.ts` with automatic failover on 413 errors
- [ ] 2. Implement exponential backoff retry logic in RPC client configuration
- [ ] 3. Add RPC health monitoring to switch providers when primary fails with rate limits
- [ ] 4. Test that app continues working when primary RPC returns 413 errors

### 7. Fix Insurance Fund Fee Flow to Show Growth [LOW] [CONTRACT]
- [ ] 1. Verify `FeeRouter.sol` is properly routing 20% of fees to InsuranceFund contract address
- [ ] 2. Check if InsuranceFund balance increases after trade executions by calling `getBalance()` before/after trades
- [ ] 3. Add event logging in FeeRouter to track fee distribution amounts to LP/Protocol/Insurance
- [ ] 4. Run test trade sequence and verify Insurance Fund grows beyond $10K bootstrap amount