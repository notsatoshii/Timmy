Based on the build plan and QA score of 52 (critical for investor demo), here are the prioritized tasks:

### 1. Fix Oracle Price Feed Pipeline [CRITICAL] [ORACLE]
- [ ] Debug mockkeeper.py service that's failing to push live price updates
- [ ] Verify OracleAdapter contract can receive and process external feeds  
- [ ] Restore real-time PI calculations from stale price data
- [ ] Test price propagation through entire trading system

### 2. Restore Vault Data Display [CRITICAL] [FRONTEND] 
- [ ] Fix useVaultMulticall hook returning undefined (causing $NaN display)
- [ ] Debug 413 RPC errors from Base Sepolia blocking data fetching
- [ ] Restore TVL and share price display from current $0/$NaN state
- [ ] Verify vault metrics render correctly for investor demonstration

### 3. Fix Position Value Calculations [CRITICAL] [FRONTEND]
- [ ] Debug why all 213 positions display $0.00 instead of actual equity/PnL
- [ ] Verify position data pipeline from PositionManager contract
- [ ] Restore meaningful P&L display for existing leveraged positions  
- [ ] Test position value updates integrate with live price data

### 4. Enable Position Opening Without Redeployment [HIGH] [BACKEND]
- [ ] Debug "Position Open Failed" errors within contract protection constraints
- [ ] Verify ExecutionEngine can access updated LeverageModel via calls (not redeploy)
- [ ] Test leverage calculations work beyond current 1x limitation
- [ ] Ensure frontend position opening flow demonstrates core functionality

### 5. Restore Screenshot Verification System [MEDIUM] [DEVOPS]
- [ ] Install missing libatk dependencies for headless Chrome browser
- [ ] Fix automated visual verification pipeline for ongoing QA  
- [ ] Ensure screenshot reports generate for demo verification
- [ ] Test verification gates work for continuous integration

**Critical Path**: Tasks 1-3 are demo-blockers making system appear non-functional. Task 4 enables core trading demonstration. Task 5 maintains quality assurance pipeline.