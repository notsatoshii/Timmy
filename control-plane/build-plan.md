You're absolutely right. Let me create a corrected plan that follows the exact priorities from build-plan.md and respects all constraints:

## CORRECTED PLAN - INVESTOR DEMO SPRINT (LOCKED)

### 1. Fix Screenshot Verification [CRITICAL] [FRONTEND]
- [ ] Run `node scripts/take-screenshots.js` and capture the specific error causing verification failures
- [ ] Diagnose if browser/puppeteer process is hanging (implement 30-second timeout)
- [ ] Add fallback: manual screenshot capture + basic UI load test if automation fails
- [ ] **GOAL**: Confirm all UI tabs load without blank screens for investor demo

### 2. Fix Vault Tab Data Display [CRITICAL] [FRONTEND] 
- [ ] Verify LeverVault address in `config/contracts.ts` matches deployed contract (0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921)
- [ ] Add debug logging to `useVaultMulticall` to identify why it returns undefined (RPC 413 errors)
- [ ] Implement graceful fallback for vault data when RPC calls fail
- [ ] **GOAL**: Show meaningful TVL and share price numbers instead of $NaN and $0

### 3. Fix Position Values Display [CRITICAL] [FRONTEND]
- [ ] Verify PositionManager address in frontend config (should be 0x25ba54a7b2fBac753B601Da05e3661F2E959510b)
- [ ] Debug why demo mode shows $0.00 for all position values
- [ ] Add fallback to display position count and basic data when value calculation fails
- [ ] **GOAL**: Show existing positions with meaningful non-zero values

**Key Constraints Respected:**
- ✅ Work ONLY on these 3 priorities until all pass
- ✅ No contract redeployment (protected contracts untouched)
- ✅ No address changes 
- ✅ Frontend-only fixes
- ✅ No additional tasks beyond the 3 priorities

**Success Criteria:** All tabs load with real data, no $NaN/$0.00 displays, investor demo runs smoothly. Then transition to Phase 2 auto-improve mode.