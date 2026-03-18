Based on the QA report analysis, here are the prioritized tasks to improve the system before investor demo:

### 1. Fix Insurance Fund Display Bug [CRITICAL] [BACKEND]
- [ ] Insurance Fund shows corrupted value $5.011e24 instead of expected ~$10K bootstrap
- [ ] Check FeeRouter fee distribution and InsuranceFund balance calculations  
- [ ] Verify formatWad/formatUsdt conversion in frontend InsuranceFund display
- [ ] Target: Show correct $10K-$50K range based on actual fee accumulation

### 2. Verify Oracle Keeper Stability [HIGH] [INFRASTRUCTURE]  
- [ ] Check if mockkeeper.py is running and updating prices regularly
- [ ] Verify price feeds are fresh (not stale) across all active markets
- [ ] Test oracle price pipeline from Polymarket → OracleAdapter → PI updates
- [ ] Ensure positions can open/close with current price data

### 3. Investigate Low LP APY Issue [MEDIUM] [BACKEND]
- [ ] LP APY currently 0.21% - trace fee flow from trades → FeeRouter → RewardsDistributor  
- [ ] Check if borrow fees, transaction fees, and funding payments are reaching LP pool
- [ ] Verify RewardsDistributor is accumulating yield properly
- [ ] Target: APY should reflect actual trading activity (228 positions, $11.5M OI)

### 4. Add Production Monitoring [MEDIUM] [FRONTEND]
- [ ] Implement error boundary monitoring with alerts for investor demo
- [ ] Add basic user analytics to track position opens, trade volumes, errors
- [ ] Create health check endpoint for infrastructure monitoring  
- [ ] Add performance monitoring for wallet connection and trade execution flows

### 5. Polish UX for Investor Demo [LOW] [FRONTEND]
- [ ] Add loading states for all async operations (wallet connect, trades, data fetching)
- [ ] Improve error messaging with actionable feedback instead of generic failures
- [ ] Test complete user journey: connect wallet → deposit → open position → close position
- [ ] Verify all tabs render cleanly without $0.00 or $NaN display issues