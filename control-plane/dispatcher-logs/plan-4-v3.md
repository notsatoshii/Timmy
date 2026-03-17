### 1. Fix Fundamental Contract Connectivity Issue Causing All Data to Return Empty [CRITICAL] [FRONTEND]
- [ ] 1. Diagnose root cause of ALL data checks returning empty in `frontend/user-app/src/hooks/useContractData.ts` - verify contract addresses, RPC connection, and provider setup
- [ ] 2. Compare contract addresses in `frontend/user-app/src/config/contracts.ts` against deployed addresses in `control-plane/deploy-env.sh`
- [ ] 3. Add comprehensive error logging and connection status checks to identify whether issue is RPC, address mismatches, or contract state
- [ ] 4. Fix the underlying connectivity issue - this should resolve $NaN and $0 displays across the entire app AND potentially fix position opening failures

### 2. Fix Position Opening Failures by Redeploying ExecutionEngine [CRITICAL] [CONTRACT]
- [ ] 1. Check current ExecutionEngine address in `control-plane/deploy-env.sh` and verify it points to old LeverageModel
- [ ] 2. Deploy new ExecutionEngine pointing to fixed LeverageModel (0xf649e342...F9EF) in `scripts/deploy/06-execution-engine.js`
- [ ] 3. Update ExecutionEngine address in `control-plane/deploy-env.sh` and `frontend/user-app/src/config/contracts.ts`
- [ ] 4. Test position opening with `bash scripts/user-flow-test.sh` to verify fix (Note: may be resolved by Task #1 connectivity fix)

### 3. Fix Position Values Display with Real Contract Data [HIGH] [FRONTEND]
- [ ] 1. Replace stub position data in `frontend/user-app/src/hooks/usePositions.ts` with actual PositionManager contract calls
- [ ] 2. Update position PnL calculation in `frontend/user-app/src/components/positions/PositionCard.tsx` to use current PI from OracleAdapter
- [ ] 3. Fix notional value display to show position_size * current_price instead of just collateral
- [ ] 4. Add error boundaries in position components to handle contract call failures gracefully

### 4. Fix Insurance Fund Fee Flow Through FeeRouter [MEDIUM] [CONTRACT]
- [ ] 1. Verify FeeRouter is properly configured to send 20% of fees to InsuranceFund address
- [ ] 2. Check if ExecutionEngine is calling FeeRouter on position opens/closes
- [ ] 3. Test fee flow with a position open/close cycle and verify insurance fund balance increases
- [ ] 4. Update InsuranceFund to accept fee deposits from FeeRouter properly

### 5. Fix 24h Volume Display to Show Notional Instead of Collateral [MEDIUM] [FRONTEND]
- [ ] 1. Update volume calculation in `frontend/user-app/src/hooks/useMarketData.ts` to multiply collateral by leverage for notional volume
- [ ] 2. Modify `frontend/user-app/src/components/markets/MarketCard.tsx` volume display to use notional values
- [ ] 3. Add "Notional Volume" label to clarify what the metric represents
- [ ] 4. Ensure volume aggregation across all markets uses notional amounts

### 6. Improve LP APY Calculation and Display [LOW] [FRONTEND]
- [ ] 1. Update APY calculation in `frontend/user-app/src/hooks/useVaultData.ts` to use annualized fee revenue
- [ ] 2. Show both current APY and projected APY based on higher leverage usage
- [ ] 3. Add tooltip explaining APY will increase as more leveraged positions are opened
- [ ] 4. Display fee sources breakdown (borrow fees, trading fees, funding payments)