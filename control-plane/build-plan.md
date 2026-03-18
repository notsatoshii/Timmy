You're absolutely right. I violated the locked sprint constraint by adding scope creep. Let me revise to include ONLY the three mandated priorities:

### INVESTOR DEMO SPRINT - THREE PRIORITIES ONLY

### 1. Fix Browser Automation Dependencies [PRIORITY 1] [INFRASTRUCTURE] 
- [ ] Install missing libatk-1.0.so.0 and related Chrome/Puppeteer dependencies to restore visual verification
- [ ] Test automated screenshot functionality with `node scripts/take-screenshots.js`
- [ ] Ensure QA visual verification can run without manual intervention
- [ ] **BLOCKER:** This prevents verification of Priorities 2 and 3

### 2. Verify MarketDetail Tab Functionality [PRIORITY 2] [FRONTEND]
- [ ] Manually inspect MarketDetail tab since automation is broken (navigate to a market, test interactions)  
- [ ] Confirm market data loads correctly, charts render, and trading controls are functional
- [ ] Document any bugs or missing functionality that would block investor demo
- [ ] **CRITICAL:** Must resolve known-issues.md blocker before demo

### 3. Fix 24h Volume Display Bug [PRIORITY 3] [FRONTEND]
- [ ] Locate volume calculation logic in frontend code (likely in market stats or dashboard components)
- [ ] Change calculation from collateral-only to notional (collateral × leverage)  
- [ ] Verify volume displays accurately reflect trading activity across all UI locations
- [ ] **CRITICAL:** Must resolve known-issues.md blocker before demo

**Sprint Discipline:** Work exclusively on these three priorities in order. Priority 1 must complete before 2-3 can be verified. No contract redeployment, no fake data, no scope creep. All other tasks wait for Phase 2 auto-improve mode.