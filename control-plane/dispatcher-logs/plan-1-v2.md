### 1. Eliminate $NaN and $0.00 Displays (Investor Trust Killers) [CRITICAL] [FRONTEND]
- [ ] 1. Fix vault $NaN share price in `frontend/user-app/src/hooks/useVaultMulticall.tsx` by replacing multicall with individual contract calls and adding proper error handling
- [ ] 2. Fix position values showing $0.00 in `frontend/user-app/src/hooks/usePositions.tsx` with correct WAD (1e18) to USDT (1e6) decimal scaling
- [ ] 3. Add loading states and fallback values ("Loading..." instead of $NaN, "---" instead of $0.00) for all undefined financial displays
- [ ] 4. Implement RPC retry logic with exponential backoff to handle 413 rate limit errors that cause data fetching failures

### 2. Restore Position Opening Functionality (Core Platform Capability) [CRITICAL] [CONTRACT]
- [ ] 1. Redeploy ExecutionEngine with correct LeverageModel address (0xf649e342...F9EF) to fix root cause of position opening failures
- [ ] 2. Grant all necessary roles (ADMIN, KEEPER) to new ExecutionEngine in dependent contracts (PositionManager, MarginEngine, OILimits)
- [ ] 3. Update `control-plane/deploy-env.sh` with new ExecutionEngine address and verify role grants with cast commands
- [ ] 4. Test position opening with 1x leverage first, then verify 7x-12x leverage works for demo scenarios

### 3. Implement Investor-Ready Demo Mode with Realistic Data [CRITICAL] [FRONTEND]
- [ ] 1. Create `frontend/user-app/src/data/demoData.ts` with professional metrics: TVL ($2.5M), realistic positions with actual PnL (+/- $500-5000)
- [ ] 2. Replace stub data in `useIsDemoMode.tsx` with functional-looking leverage (7x-12x), live-looking market prices, and believable trading activity
- [ ] 3. Add realistic 24h volume ($50K-200K notional) and active position counts (15-30 positions) to show platform traction
- [ ] 4. Ensure demo mode feels fully functional for investor presentations while maintaining demo mode indicator

### 4. Fix All Dashboard Data Fetching (System Health Visibility) [HIGH] [INFRA]
- [ ] 1. Debug and fix dashboard.py data collection for TVL, Global OI, Insurance Fund, Max Leverage (all currently showing empty values)
- [ ] 2. Add comprehensive error logging to identify which specific contract calls are failing in the data pipeline
- [ ] 3. Implement direct contract verification using cast commands to validate contract state accessibility
- [ ] 4. Add data caching and retry mechanisms to handle intermittent RPC connection issues

### 5. Enhance Position Management for Professional Appearance [HIGH] [FRONTEND]
- [ ] 1. Debug position data fetching in `Trading.tsx` to display specific failure reasons instead of generic "Position Open Failed" messages
- [ ] 2. Add proper collateral and leverage calculation validation before ExecutionEngine calls
- [ ] 3. Implement smooth loading states and progress indicators for position operations
- [ ] 4. Add position history and PnL tracking to demonstrate platform sophistication

### 6. Verify Fee Flow and Insurance Fund Operations [MEDIUM] [CONTRACT]
- [ ] 1. Test FeeRouter.distributeFees() calls from PositionManager and ExecutionEngine on position opens/closes
- [ ] 2. Verify InsuranceFund is receiving proper fee distributions (20% of transaction and borrow fees)
- [ ] 3. Add fee flow monitoring to dashboard to show platform revenue generation
- [ ] 4. Document fee flow for investor transparency (50% LP / 30% Protocol / 20% Insurance split)

### 7. Polish Financial Metrics Display [MEDIUM] [FRONTEND]
- [ ] 1. Fix 24h volume calculation to multiply collateral by leverage for accurate notional volume reporting
- [ ] 2. Add both collateral volume and notional volume metrics for comprehensive platform activity view
- [ ] 3. Implement proper time windowing for 24h calculations using block timestamps
- [ ] 4. Add volume trending indicators to show platform growth trajectory

### 8. System Resilience and Monitoring [LOW] [INFRA]
- [ ] 1. Implement health monitoring for all critical contract interactions
- [ ] 2. Add automated alerts for RPC connection issues and contract call failures
- [ ] 3. Create automated recovery procedures for common failure modes
- [ ] 4. Document troubleshooting procedures for rapid issue resolution