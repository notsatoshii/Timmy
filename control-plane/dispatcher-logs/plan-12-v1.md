### 1. Fix Vault Tab $NaN Share Price and $0 TVL Display [CRITICAL] [FRONTEND]
- [ ] 1. Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` - investigate 413 RPC errors causing undefined returns
- [ ] 2. Add error handling and fallback logic in `frontend/user-app/src/components/VaultTab.tsx` to display actual vault state when multicall fails
- [ ] 3. Verify LeverVault contract calls are using correct addresses from `frontend/user-app/src/config/contracts.ts`
- [ ] 4. Test with direct contract reads if multicall continues failing

### 2. Fix All QA Data Checks Returning Empty Values [CRITICAL] [FRONTEND]
- [ ] 1. Investigate why `control-plane/qa-agent.py` data extraction is failing for TVL, Positions, Global OI, Insurance Fund, Max Leverage
- [ ] 2. Check if frontend hooks are properly connected to deployed contracts at addresses in `control-plane/deploy-env.sh`
- [ ] 3. Add debugging logs to identify where data flow breaks between contracts and frontend display
- [ ] 4. Ensure demo mode has proper fallback data when wallet not connected

### 3. Remove Fake Volume Data Per Build Plan [CRITICAL] [FRONTEND]
- [ ] 1. In `frontend/user-app/src/hooks/useVolumeCalculation.ts` - remove hardcoded `BigInt('12800000000')` fallback
- [ ] 2. In `frontend/user-app/src/components/ProtocolStats.tsx` - remove `DEMO_FALLBACK_VALUES.volume24h`
- [ ] 3. Display honest "$0.00" when no trading events found in 24h period
- [ ] 4. Fix volume calculation to use notional (collateral × leverage) not just collateral

### 4. Fix Position Values Showing $0.00 in Demo Mode [CRITICAL] [FRONTEND]
- [ ] 1. Update `frontend/user-app/src/components/PositionsTab.tsx` to display demo positions with proper calculated values
- [ ] 2. Fix position value calculation utilities in demo mode to show realistic P&L, equity, and collateral amounts
- [ ] 3. Ensure position display works both with and without wallet connection
- [ ] 4. Add fallback demo positions that reflect actual trading scenarios

### 5. Verify Oracle Keeper Status and Price Updates [HIGH] [INFRA]
- [ ] 1. Check if `control-plane/mockkeeper.py` systemd service is running: `systemctl status lever-oracle-keeper`
- [ ] 2. Verify recent price updates in OracleAdapter contract using `bash control-plane/health-check.sh`
- [ ] 3. Test price staleness detection (5min threshold) and ensure prices are updating every ~30 seconds
- [ ] 4. Restart oracle keeper service if needed and verify price flow to frontend

### 6. Investigate Position Opening Failures [HIGH] [CONTRACT]
- [ ] 1. Verify ExecutionEngine is using correct LeverageModel address (should be 0x474E2eE2911544a385eb017369e8516Ad6DcCAbd)
- [ ] 2. Test position opening with deployer wallet to confirm if issue is contract-level or frontend-level
- [ ] 3. Check MarginEngine parameters are properly set to avoid ZeroDepthThreshold errors
- [ ] 4. Document exact error messages and contract call traces for position opening attempts

### 7. Verify MarketDetail Tab Functionality [MEDIUM] [FRONTEND]
- [ ] 1. Test navigation to `/markets/[id]` route and ensure market data loads correctly
- [ ] 2. Verify chart display, market stats, and position opening form work on market detail pages
- [ ] 3. Check if market resolution status and time remaining display properly
- [ ] 4. Ensure market-specific leverage limits and OI caps are shown accurately

### 8. Fix Insurance Fund Fee Flow [MEDIUM] [CONTRACT]
- [ ] 1. Verify FeeRouter is properly distributing 20% of trading fees to InsuranceFund
- [ ] 2. Check if insurance fund balance updates beyond $10K bootstrap amount
- [ ] 3. Test fee routing by executing trades and monitoring insurance fund balance changes
- [ ] 4. Ensure insurance fund display in frontend reflects actual on-chain balance

### 9. Improve LP APY Calculation Accuracy [LOW] [FRONTEND]
- [ ] 1. Update `frontend/user-app/src/hooks/useAPYCalculation.ts` to account for actual trading volume and fees
- [ ] 2. Ensure APY calculation includes both trading fees and funding rate compensation to LPs
- [ ] 3. Display realistic APY based on current TVL and fee generation
- [ ] 4. Add APY calculation transparency with breakdown of fee sources