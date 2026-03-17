Based on the current build plan and QA report showing a score of 60/100, here are the **3 CRITICAL TASKS** for the locked investor demo sprint:

### 1. Fix Screenshot Verification System [CRITICAL] [INFRASTRUCTURE]
- [ ] Install missing browser dependencies (`libatk-1.0.so.0`) causing Puppeteer crashes
- [ ] Debug and fix screenshot automation hanging processes preventing visual verification
- [ ] **SUCCESS CRITERIA**: `node scripts/take-screenshots.js` completes successfully with actual screenshots for investor demo readiness

### 2. Fix Vault Tab $NaN/$0 Display [CRITICAL] [FRONTEND] 
- [ ] Debug `useVaultMulticall` returning undefined causing vault data pipeline failure
- [ ] Resolve 413 RPC errors from Base Sepolia affecting vault TVL/share price fetching
- [ ] **SUCCESS CRITERIA**: Vault tab displays meaningful TVL and share price (currently shows $NaN and $0)

### 3. Fix Position Values $0.00 Display [CRITICAL] [FRONTEND]
- [ ] Debug why demo mode shows $0.00 for all 213 position values in Positions tab  
- [ ] Fix PositionManager integration to calculate and display actual position equity/PnL
- [ ] **SUCCESS CRITERIA**: Positions tab shows meaningful non-zero values for existing positions

**SPRINT CONSTRAINTS (ENFORCED):**
- ✅ Work ONLY on these 3 priorities until ALL pass completely
- ✅ NO contract redeployment (all protected contracts remain untouched)  
- ✅ NO fake/fabricated data - fix actual data pipeline issues
- ✅ Focus on frontend integration and RPC connectivity issues

**Completion Gate:** Only when all 3 priorities achieve 100% pass rate → transition to Phase 2 auto-improve mode

**Current Blockers:** Oracle price freshness + visual verification broken = investor demo compromised