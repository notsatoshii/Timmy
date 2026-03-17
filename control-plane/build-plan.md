### 1. Diagnose Contract Data Fetching Root Cause [CRITICAL] [CONTRACT]
- [x] 1. Verify all contract addresses in `control-plane/deploy-env.sh` match actual deployed contracts on Base Sepolia
- [ ] 2. Test direct contract calls using cast/forge to identify which contracts are failing (TVL, Positions, Global OI, Insurance Fund, Max Leverage)
- [ ] 3. Check contract state initialization - ensure all required roles are granted and contracts are properly initialized
- [ ] 4. Debug RPC connection issues in `control-plane/dashboard.py` with detailed error logging

### 2. Fix Contract Address Configuration Mismatch [CRITICAL] [FRONTEND]
- [x] 1. Compare contract addresses in `frontend/user-app/src/config/contracts.ts` with `control-plane/deploy-env.sh`
- [ ] 2. Update frontend contract addresses to match deployed contracts if mismatched
- [ ] 3. Verify ABI files match deployed contract versions
- [ ] 4. Test contract connectivity from frontend using simple read calls

### 3. Fix Leverage Model Integration Root Cause [CRITICAL] [CONTRACT]
- [x] 1. Debug why LeverageModel caps at 1x instead of allowing 10x-30x positions by examining actual state variables
- [ ] 2. Verify LeverageModel constructor parameters match whitepaper specifications (BASE_MAX_LEVERAGE=30x, TVL_MATURITY=$50M)
- [ ] 3. Check if ExecutionEngine is calling LeverageModel correctly and using returned values properly
- [ ] 4. Deploy fixed LeverageModel with correct parameters if needed, then redeploy ExecutionEngine with correct address

### 4. Validate 10x+ Leverage Actually Works [CRITICAL] [TESTING]
- [x] 1. Test position opening at 1x, 5x, 10x, 20x, 30x leverage using direct contract calls via cast
- [ ] 2. Verify each leverage level returns expected collateral requirements and position sizes
- [ ] 3. Confirm ExecutionEngine.openPosition() succeeds for 10x+ positions with sufficient collateral
- [ ] 4. Test full user flow: deposit → approve → openPosition at 20x leverage → verify position state

### 5. Fix Dashboard Data Display with Proper Error Handling [CRITICAL] [INFRA]
- [x] 1. Add comprehensive error logging to `control-plane/dashboard.py` for each contract call
- [ ] 2. Implement fallback values when contract calls fail instead of returning empty strings
- [ ] 3. Add retry logic with exponential backoff for RPC failures
- [ ] 4. Verify dashboard shows actual contract values after contract fixes are deployed

### 6. Fix Vault Tab Display with Investor-Realistic Demo Values [CRITICAL] [FRONTEND]
- [x] 1. Fix `frontend/user-app/src/hooks/useVaultMulticall.ts` RPC errors and undefined returns
- [ ] 2. Implement demo mode with realistic values: TVL=$2.5M, Share Price=$1.05, APY=12.5%
- [ ] 3. Add proper loading states in `VaultTab.tsx` instead of showing $NaN
- [ ] 4. Ensure share price calculation uses correct WAD decimals and fallback values

### 7. Fix Positions Tab with Realistic Demo Data [CRITICAL] [FRONTEND]
- [x] 1. Update `frontend/user-app/src/hooks/usePositions.ts` to properly format WAD values from contracts
- [ ] 2. Generate realistic demo positions: $50K-$500K notional, various markets, meaningful PnL
- [ ] 3. Fix PnL calculations to use correct decimal scaling (WAD/USDT conversion)
- [ ] 4. Add error boundaries for undefined position data with meaningful fallback displays

### 8. End-to-End Integration Validation [CRITICAL] [TESTING]
- [x] 1. Run complete user flow after fixes: deposit $1000 → open 20x position → verify $20K notional displayed correctly
- [ ] 2. Test position opening across all leverage levels (1x through 30x) to ensure ExecutionEngine works
- [ ] 3. Validate frontend displays match actual contract state for all values (TVL, share price, positions, leverage)
- [ ] 4. Verify demo mode shows investor-realistic values that would pass institutional scrutiny

### 9. Fix 24h Volume to Show Notional Not Collateral [HIGH] [FRONTEND]
- [x] 1. Update volume calculation in `frontend/user-app/src/hooks/useTradeHistory.ts` line ~85
- [ ] 2. Change from `position.collateral` to `position.collateral * position.leverage` for notional value
- [ ] 3. Ensure proper decimal formatting shows meaningful volumes ($100K+ daily)
- [ ] 4. Verify volume aggregation across all markets shows combined notional trading activity

### 10. Update Page Title and Professional Polish [MEDIUM] [FRONTEND]
- [x] 1. Edit `frontend/user-app/index.html` title tag to "LEVER Protocol - Synthetic Perpetuals"
- [ ] 2. Update favicon.ico with LEVER branding
- [ ] 3. Add proper meta tags for description and social media previews
- [ ] 4. Ensure title updates dynamically based on current tab/page