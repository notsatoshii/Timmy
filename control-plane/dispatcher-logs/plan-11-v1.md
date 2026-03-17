### 1. Fix $NaN Share Price and TVL Values in Vault Tab [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` to identify why 413 RPC errors cause undefined returns
- [ ] 2. Add exponential backoff retry logic for failed RPC calls with 3 retry attempts
- [ ] 3. Implement fallback demo values when RPC fails: sharePrice=$1.00, TVL=$50,000, totalShares=50000
- [ ] 4. Add error boundary around vault display components to catch BigInt conversion errors

### 2. Fix Position Opening "Position Open Failed" Error [CRITICAL] [FRONTEND]
- [ ] 1. Investigate `frontend/user-app/src/components/Trading/PositionForm.tsx` to identify exact failure point in position opening flow
- [ ] 2. Check if ExecutionEngine contract calls are reverting due to leverage limitations or other validation failures
- [ ] 3. Add detailed error logging to capture revert reasons from ExecutionEngine.openPosition() calls
- [ ] 4. Implement user-friendly error messages instead of generic "Position Open Failed"

### 3. Fix All Dashboard Data Checks Showing Error Status [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/usePositionMulticall.ts` and `useMarketMulticall.ts` for RPC failures
- [ ] 2. Add proper error handling and null checks to prevent empty string values in data checks
- [ ] 3. Implement retry mechanisms for failed multicall batches that cause undefined returns
- [ ] 4. Add fallback values for demo mode when contract calls fail: Global OI=$25,000, Max Leverage=12x

### 4. Investigate ExecutionEngine vs LeverageModel Version Mismatch [HIGH] [CONTRACT]
- [ ] 1. Read ExecutionEngine contract at 0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D to verify which LeverageModel address it references
- [ ] 2. Compare with deployed LeverageModel at 0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ed to confirm version mismatch
- [ ] 3. Check if ExecutionEngine has updateLeverageModel() function or if immutable deployment requires different solution
- [ ] 4. Document findings and recommend approach without violating PROTECTED CONTRACTS rule

### 5. Fix 24h Volume Display to Show Notional Instead of Collateral [HIGH] [FRONTEND]
- [ ] 1. Modify `frontend/user-app/src/hooks/useTradeHistory.ts` volume calculation to multiply collateral by leverage
- [ ] 2. Update `frontend/user-app/src/components/Markets/MarketCard.tsx` to display notional volume (collateral × leverage)
- [ ] 3. Add proper formatting for larger notional amounts (K, M suffixes)
- [ ] 4. Verify calculation accuracy across different leverage levels in demo data

### 6. Fix Insurance Fund Growth to Flow Through FeeRouter [MEDIUM] [CONTRACT]
- [ ] 1. Verify FeeRouter integration by checking if trading fees are properly routed to InsuranceFund
- [ ] 2. Test fee distribution mechanism: 50% LP, 30% Protocol, 20% Insurance split
- [ ] 3. Check if ExecutionEngine and LiquidationEngine are calling FeeRouter.distributeFees() on transactions
- [ ] 4. Add logging to track fee flow from trades to InsuranceFund balance increases

### 7. Verify Oracle Keeper Service Status [MEDIUM] [INFRA]
- [ ] 1. Check if `lever-oracle-keeper` systemd service is running with `systemctl status lever-oracle-keeper`
- [ ] 2. Verify price updates in `control-plane/dispatcher-logs/` are recent (within 5 minutes)
- [ ] 3. Test mockkeeper.py manually to ensure price feeds are updating OracleAdapter
- [ ] 4. Install systemd service using `/tmp/install-oracle-keeper-root.sh` if not running

### 8. Add Proper Error Boundaries for BigInt Conversion Errors [LOW] [FRONTEND]
- [ ] 1. Review `frontend/user-app/src/hooks/useTradeHistory.ts` for remaining BigInt(float) conversion issues
- [ ] 2. Add Math.floor() wrapping around all timestamp calculations before BigInt conversion
- [ ] 3. Implement comprehensive error catching in usePositionMulticall and useVaultMulticall hooks
- [ ] 4. Add user-friendly error messages when contract calls fail instead of showing raw errors