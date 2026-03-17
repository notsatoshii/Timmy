Based on the build plan requirements, here's the **CORRECTED** plan that follows the locked sprint scope:

## **REVISED PLAN - INVESTOR DEMO SPRINT**

### 1. Fix Screenshot Verification System [CRITICAL] [INFRASTRUCTURE]
- [ ] Resolve Puppeteer dependency issue: install missing `libatk-1.0.so.0` and Chrome dependencies
- [ ] Fix automated browser testing pipeline to prevent hanging processes  
- [ ] **SUCCESS CRITERIA**: `node scripts/take-screenshots.js` completes successfully with actual screenshots

### 2. Fix Vault Tab Data Display [CRITICAL] [FRONTEND]
- [ ] Debug `useVaultMulticall` returning undefined causing $NaN share price and $0 TVL display
- [ ] Address 413 RPC errors from Base Sepolia endpoints affecting vault data fetching
- [ ] Verify LeverVault contract integration matches deployed address (0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921)
- [ ] **SUCCESS CRITERIA**: Vault tab displays meaningful TVL and share price (no $NaN/$0 values)

### 3. Fix Position Values Display [CRITICAL] [FRONTEND] 
- [ ] Debug why demo mode shows $0.00 for all position values in Positions tab
- [ ] Fix PositionManager integration to display calculated position equity and PnL
- [ ] Verify frontend contract addresses match deployed PositionManager (0x25ba54a7b2fBac753B601Da05e3661F2E959510b)
- [ ] **SUCCESS CRITERIA**: Positions tab shows meaningful non-zero values for 212 existing positions

## **Sprint Constraints (ENFORCED):**
- ✅ Work ONLY on these 3 priorities until ALL pass completely
- ✅ NO contract redeployment (all protected contracts must remain untouched)
- ✅ NO fake/fabricated data - fix actual data pipeline issues
- ✅ Focus on frontend integration and RPC connectivity issues

**Completion Gate:** Only when all 3 priorities pass → transition to Phase 2 auto-improve mode

This revised plan removes the forbidden ExecutionEngine deployment, prioritizes screenshot verification first as required, eliminates scope creep, and focuses solely on frontend data pipeline fixes.