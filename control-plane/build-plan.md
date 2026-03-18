Based on the QA report showing a score of 60 with critical frontend service configuration issues, here are the prioritized tasks:

### 1. Fix Frontend Service Port Configuration [CRITICAL] [FRONTEND]
- [ ] Resolve systemd service binding to port 3000 instead of 39671
- [ ] Stop development server (react-app-rewired) running alongside production 
- [ ] Ensure lever-frontend service properly starts on intended port for investor demo

### 2. Resolve Service Deployment Conflicts [HIGH] [DEVOPS]  
- [ ] Kill conflicting development processes causing port conflicts
- [ ] Fix systemd service configuration for stable port binding
- [ ] Implement proper production deployment separation from dev environment

### 3. Investigate Insurance Fund Bootstrap Issue [MEDIUM] [CONTRACTS]
- [ ] Verify why Insurance Fund remains at $10K bootstrap level
- [ ] Check if fees are properly flowing through FeeRouter to InsuranceFund  
- [ ] Confirm fee distribution pipeline is operational (50/30/20 split)

### 4. Verify Oracle Keeper Stability [MEDIUM] [ORACLE]
- [ ] Confirm mockkeeper.py is running and updating prices
- [ ] Check for stale price data in OracleAdapter
- [ ] Ensure price pipeline remains active for live demo

### 5. Monitor System Health for Demo Readiness [LOW] [QA]
- [ ] Track LP APY improvement as leverage utilization increases
- [ ] Verify all tabs render correctly after port fixes
- [ ] Confirm 234 positions and $60.5M TVL display properly in frontend

**Priority Focus**: Frontend service configuration is blocking professional demo appearance - tackle tasks 1-2 immediately.