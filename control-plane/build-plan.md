Based on the QA report (52/100 score) and critical blockers for the investor demo, here are the prioritized tasks:

### 1. Verify MarketDetail Tab Functionality [CRITICAL] [FRONTEND]
- [ ] Test and verify MarketDetail tab is working correctly for investor demo
- [ ] Take screenshots to confirm proper rendering and data display
- [ ] Ensure all market data (price, volume, positions) loads correctly

### 2. Fix 24h Volume Display Bug [CRITICAL] [FRONTEND] 
- [ ] Correct volume calculation to show notional (collateral × leverage) instead of just collateral
- [ ] This is blocking accurate metrics display for investors
- [ ] Verify fix with screenshots showing proper volume numbers

### 3. Browser-Based UI/UX Verification [HIGH] [FRONTEND]
- [ ] Run comprehensive browser testing with `node scripts/take-screenshots.js`
- [ ] Test core trading flows end-to-end with real wallet interactions
- [ ] Verify professional visual design quality that investors will see
- [ ] Test wallet connectivity and transaction signing flows

### 4. Oracle Keeper System Check [HIGH] [INFRASTRUCTURE]
- [ ] Verify mockkeeper.py is running and updating prices correctly
- [ ] Check for stale price issues that could break demo trading
- [ ] Ensure price feeds are updating in real-time for investor demonstration

### 5. LP APY Investigation [MEDIUM] [DATA]
- [ ] Analyze why LP APY is only 0.21% despite $60.5M TVL
- [ ] Verify if this will improve when leverage usage increases
- [ ] Document expected APY ranges for investor questions

**Focus:** These tasks target the visual issues flagging "Cannot verify actual user interface quality" and the two critical blockers. No contract redeployments needed - purely frontend verification and bug fixes.