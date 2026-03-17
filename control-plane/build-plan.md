Perfect! Now I understand the exact 3 priorities. Based on the verification report showing Puppeteer issues and the known-issues.md showing the critical blockers, here's the **REVISED PLAN** that strictly follows the constraints:

## REVISED PLAN - INVESTOR DEMO SPRINT (LOCKED)

### 1. Fix Screenshot Verification [CRITICAL] [FRONTEND]
- [ ] Resolve Puppeteer dependency issue: missing `libatk-1.0.so.0` (Chrome dependency)
- [ ] Install required system packages for automated browser testing
- [ ] Implement 30-second timeout to prevent hanging processes
- [ ] **SUCCESS CRITERIA**: `node scripts/take-screenshots.js` completes successfully with actual screenshots

### 2. Fix Vault Tab Data Display [CRITICAL] [FRONTEND] 
- [ ] Debug `useVaultMulticall` returning undefined causing $NaN share price and $0 TVL
- [ ] Address 413 RPC errors from Base Sepolia endpoints
- [ ] Verify LeverVault address matches deployed contract (0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921)
- [ ] **SUCCESS CRITERIA**: Vault tab displays meaningful TVL and share price numbers (no $NaN/$0)

### 3. Fix Position Values Display [CRITICAL] [FRONTEND]
- [ ] Debug why demo mode shows $0.00 for all position values in Positions tab
- [ ] Verify PositionManager address in frontend config (0x25ba54a7b2fBac753B601Da05e3661F2E959510b)
- [ ] Fix stub positions to display actual calculated values
- [ ] **SUCCESS CRITERIA**: Positions tab shows meaningful non-zero values for existing positions

**Constraints Strictly Followed:**
- ✅ Work ONLY on these 3 priorities until ALL pass
- ✅ No contract redeployment (all protected contracts untouched)
- ✅ No additional tasks beyond the approved 3 priorities
- ✅ Frontend-only fixes as specified

**Completion Gate:** Only when all 3 pass completely → transition to Phase 2 (auto-improve mode)