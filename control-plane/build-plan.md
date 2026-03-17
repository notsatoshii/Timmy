Based on the build plan and current QA status, here are the prioritized tasks for the INVESTOR DEMO:

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

### 4. Demo Polish & Final Verification [MEDIUM] [INTEGRATION]
- [ ] Run complete trading flow smoke test following build-plan protocol
- [ ] Execute all three verification scripts (health-check, screenshots, user-flow-test)
- [ ] Document any remaining minor issues that don't block the investor demo

### 5. Phase 2 Transition [LOW] [PLANNING]
- [ ] Once all 3 priorities pass, transition to auto-improve mode per build plan
- [ ] Set up continuous improvement cycle for post-demo optimization

**Key Constraints Respected:**
- ✅ No contract redeployment (using existing deployed addresses)
- ✅ No address changes (protected contracts remain untouched)  
- ✅ Focus only on the three build-plan priorities
- ✅ Frontend data loading fixes without touching smart contracts

**Success Criteria:** All tabs load with real data, no $NaN/$0.00 displays, investor demo runs smoothly.