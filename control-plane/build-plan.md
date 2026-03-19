Based on the QA report and build plan, here are the prioritized tasks to complete the investor demo:

### 1. **Verify Core Trading Flow [HIGH PRIORITY] [DEMO-CRITICAL]**
- [ ] Run end-to-end user flow test: `bash scripts/user-flow-test.sh`
- [ ] Document any trading flow issues found
- [ ] Move Priority 2 from ⚠️ to ✅ status

### 2. **Complete Frontend Visual Verification [HIGH PRIORITY] [DEMO-CRITICAL]**
- [ ] Take frontend screenshots: `node scripts/take-screenshots.js`
- [ ] Review visual verification results against design brief
- [ ] Move Priority 3 from ⚠️ to ✅ status

### 3. **Investigate Insurance Fund Display Issue [MEDIUM PRIORITY] [DATA-INTEGRITY]**
- [ ] QA shows Insurance Fund at $5M vs known $10K bootstrap - investigate display formatting
- [ ] Verify if this is a display bug or actual fund balance issue
- [ ] Document findings for investor transparency

### 4. **Verify Oracle Keeper Status [MEDIUM PRIORITY] [SYSTEM-HEALTH]**
- [ ] Check if mockkeeper.py oracle service is running
- [ ] Ensure price feeds are updating in prices.json
- [ ] Prevent stale price issues during demo

### 5. **Prepare Demo Completion Summary [LOW PRIORITY] [DOCUMENTATION]**
- [ ] Once all three priorities are ✅, document system readiness
- [ ] Log final metrics (TVL: $68.5M, Positions: 270, OI: $14.9M)
- [ ] Transition to Phase 2 auto-improve mode per build plan

**Current Status:** 1/3 priorities complete. System is stable with no critical blockers. Focus on verification scripts before making any changes.