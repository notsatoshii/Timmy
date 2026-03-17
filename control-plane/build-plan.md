Based on the QA report (score: 52) and locked sprint priorities in build-plan.md, here are the **3 CRITICAL TASKS** for investor demo readiness:

### 1. Fix Screenshot Verification System [CRITICAL] [INFRASTRUCTURE]
- [ ] Install missing browser dependencies (`libatk-1.0.so.0`) causing Puppeteer crashes in verification pipeline
- [ ] Debug screenshot automation hanging processes preventing visual QA validation  
- [ ] **SUCCESS CRITERIA**: `node scripts/take-screenshots.js` completes successfully with actual screenshots

### 2. Fix Vault Tab $NaN/$0 Display [CRITICAL] [FRONTEND] 
- [ ] Debug `useVaultMulticall` hook returning undefined, breaking vault data pipeline
- [ ] Resolve 413 RPC errors from Base Sepolia affecting TVL/share price fetching
- [ ] **SUCCESS CRITERIA**: Vault tab shows meaningful TVL and share price instead of $NaN/$0

### 3. Fix Position Values $0.00 Display [CRITICAL] [FRONTEND]
- [ ] Debug why all 213 positions show $0.00 values in demo mode instead of actual equity/PnL
- [ ] Fix PositionManager integration to properly calculate and display position values from contract data
- [ ] **SUCCESS CRITERIA**: Positions tab displays meaningful non-zero values for existing positions

**SPRINT LOCK ENFORCED:**
- ✅ Work ONLY on these 3 priorities until ALL pass completely  
- ✅ NO contract redeployment (ExecutionEngine leverage fix blocked until Phase 2)
- ✅ NO fake data - fix actual RPC/integration issues 
- ✅ Focus on frontend data pipeline and visual verification

**Gate to Phase 2:** Only when all 3 achieve 100% success → unlock auto-improve mode and remaining features.