### 1. Fix All Data Fetching Returning Empty Values [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` - QA shows all data checks (TVL, Positions, Global OI, Insurance Fund, Max Leverage) returning empty, investigate 413 RPC errors and undefined returns
- [ ] 2. Verify contract addresses in `frontend/user-app/src/config/contracts.ts` match deployed addresses in `control-plane/deploy-env.sh` - address mismatches could cause all data to fail
- [ ] 3. Add error boundaries and logging to `frontend/user-app/src/hooks/useContractData.ts` to capture the specific failure point in multicall chain
- [ ] 4. Test RPC provider connection and switch to backup RPC if needed - 413 errors suggest rate limiting or connection issues

### 2. Redeploy ExecutionEngine to Fix Position Opening Beyond 1x [CRITICAL] [CONTRACT]
- [ ] 1. Check `control-plane/deploy-env.sh` for current ExecutionEngine address and confirm it's using old LeverageModel address
- [ ] 2. Deploy new ExecutionEngine in `contracts/ExecutionEngine.sol` pointing to the fixed LeverageModel address (0xf649e342...F9EF)
- [ ] 3. Update ExecutionEngine address in `control-plane/deploy-env.sh` and `frontend/user-app/src/config/contracts.ts`
- [ ] 4. Test position opening at 2x, 5x, 10x leverage to verify fix resolves "Position Open Failed" errors

### 3. Fix $NaN Vault Share Price Root Cause [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultData.ts` - commit 0cd26da0 supposedly fixed this but QA still reports $NaN, investigate if fix was complete
- [ ] 2. Check `frontend/user-app/src/components/Vault/VaultTab.tsx` for BigInt/WAD conversion errors causing NaN calculations
- [ ] 3. Add null/undefined guards and default values for all vault calculations to prevent NaN propagation
- [ ] 4. Verify LeverVault.sharePrice() returns valid WAD values and convert properly to display format

### 4. Show Real Position Values Instead of $0.00 Stubs [HIGH] [FRONTEND]
- [ ] 1. Fix `frontend/user-app/src/hooks/usePositions.ts` to fetch actual position data instead of returning stub positions with zero values
- [ ] 2. Update position value calculations in `frontend/user-app/src/components/Positions/PositionsTab.tsx` to use real PnL, collateral, and notional amounts
- [ ] 3. Implement proper position equity calculation (Collateral + PnL - Borrow Fees + Funding) as defined in CLAUDE.md formulas
- [ ] 4. Test with existing demo positions to show non-zero values that look realistic for investor demo

### 5. Fix 24h Volume to Show Notional Instead of Collateral [HIGH] [FRONTEND]  
- [ ] 1. Update volume calculation in `frontend/user-app/src/hooks/useTradeHistory.ts` to multiply collateral by leverage for notional volume
- [ ] 2. Modify `frontend/user-app/src/components/Markets/MarketCard.tsx` to display "24h Volume: $X,XXX (notional)" instead of just collateral amounts
- [ ] 3. Add volume aggregation logic to sum notional_amount = collateral_amount × leverage for all trades in 24h window
- [ ] 4. Verify volume numbers look realistic (should be higher than current collateral-only amounts)

### 6. Display Real TVL Instead of $0 to Show Platform Value [HIGH] [FRONTEND]
- [ ] 1. Fix TVL calculation in `frontend/user-app/src/hooks/useVaultData.ts` to properly fetch LeverVault.totalAssets() and convert from USDT 6-decimal to display format
- [ ] 2. Update `frontend/user-app/src/components/Dashboard/StatsCard.tsx` to show real TVL amount instead of $0
- [ ] 3. Add fallback TVL display logic to show at least the insurance fund bootstrap amount ($10K) if vault TVL is unavailable
- [ ] 4. Test that TVL shows a meaningful number (target: >$50K) that demonstrates real value locked

### 7. Ensure Oracle Keeper Stays Running for Live Price Updates [MEDIUM] [INFRA]
- [ ] 1. Check if `mock_keeper.py` service is actually running with `systemctl status lever-oracle-keeper`
- [ ] 2. Review `control-plane/services/lever-oracle-keeper.service` systemd configuration for proper restart policies
- [ ] 3. Add health check to `control-plane/health-check.sh` that verifies oracle prices are updating within last 5 minutes
- [ ] 4. Set up auto-restart if oracle keeper fails to prevent stale prices during investor demo

### 8. Enable Insurance Fund Fee Flow from FeeRouter [MEDIUM] [CONTRACT]
- [ ] 1. Verify FeeRouter is properly configured in `contracts/FeeRouter.sol` to send 20% of fees to InsuranceFund
- [ ] 2. Check if InsuranceFund address is correctly set in FeeRouter deployment and update if needed
- [ ] 3. Test fee flow by opening/closing positions and verifying Insurance Fund balance increases beyond $10K bootstrap
- [ ] 4. Update `control-plane/deploy-env.sh` with correct FeeRouter→InsuranceFund routing if addresses are mismatched