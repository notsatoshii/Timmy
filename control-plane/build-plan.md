Based on the feedback and the official build-plan.md, here's my **revised plan** that properly aligns with the locked sprint requirements:

## **REVISED PLAN - INVESTOR DEMO SPRINT (LOCKED)**

### **Task 1 [CRITICAL]**: Verify MarketDetail Tab Functionality [FRONTEND]
- [ ] **HIGHEST PRIORITY**: Test MarketDetail tab renders properly with real market data for investor demo
- [ ] Take screenshots to confirm proper rendering and data display
- [ ] Verify tab navigation, position details, and market information display correctly  
- [ ] Ensure all market data (price, volume, positions) loads correctly without crashes

### **Task 2 [CRITICAL]**: Fix 24h Volume Display Bug [FRONTEND]
- [ ] **HIGHEST PRIORITY**: Verify recent commit `a1b10234` actually fixed volume calculation
- [ ] Confirm volume shows notional (collateral × leverage) instead of collateral only
- [ ] Take screenshots showing proper volume numbers for investor metrics
- [ ] Document verification results of this critical blocking issue

### **Task 3 [HIGH]**: Browser-Based UI/UX Verification [FRONTEND]  
- [ ] **HIGH PRIORITY**: Run comprehensive testing with `node scripts/take-screenshots.js`
- [ ] Install missing browser dependencies (`libatk-1.0.so.0`) to enable screenshot system
- [ ] Test core trading flows end-to-end with real wallet interactions
- [ ] Verify professional visual design quality and wallet connectivity flows

### **Task 4 [HIGH]**: Oracle Keeper System Check [INFRASTRUCTURE]
- [ ] **HIGH PRIORITY**: Verify `mockkeeper.py` is running and updating prices correctly
- [ ] Check for stale price issues that could break demo trading functionality
- [ ] Ensure price feeds updating in real-time for investor demonstration
- [ ] Test oracle data flow through the system during live trading scenarios

### **Task 5 [MEDIUM]**: LP APY Investigation [DATA]
- [ ] **MEDIUM PRIORITY**: Analyze why LP APY is only 0.21% despite $60.5M TVL
- [ ] Verify if APY will improve when leverage usage increases
- [ ] Document expected APY ranges for potential investor questions
- [ ] Check FeeRouter → RewardsDistributor flow is working properly

**Focus**: Complete tasks 1-2 (CRITICAL) immediately, then 3-4 (HIGH priority), finally 5 (MEDIUM). No contract redeployments needed - purely frontend verification, infrastructure checks, and data analysis as specified in the official build-plan.md.