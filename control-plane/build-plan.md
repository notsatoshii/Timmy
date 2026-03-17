Perfect! Now I can see the actual three priorities. Let me revise my plan to align with the existing build-plan.md:

## REVISED PLAN - INVESTOR DEMO (Following build-plan.md)

### PHASE 1: Critical Blockers (Following the 3 Priorities)

**Priority 1: Fix Screenshot Verification [60 min]**
- [ ] Run `node scripts/take-screenshots.js` and capture specific error
- [ ] Check if browser/puppeteer process is hanging (timeout after 30 sec)  
- [ ] Add fallback: manual screenshot + basic UI load test if automation fails
- [ ] **GOAL**: Confirm UI loads without blank screens

**Priority 2: Fix Vault Display [45 min]**
- [ ] Check `config/contracts.ts` - verify LeverVault address matches deployed contract (0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921)
- [ ] Add console.log to useVaultMulticall to see exact undefined response
- [ ] If RPC issues persist, add mock vault data for demo mode only
- [ ] **GOAL**: Show meaningful TVL/share price numbers

**Priority 3: Fix Position Values [45 min]**  
- [ ] Verify PositionManager contract address in frontend config (should be 0x25ba54a7b2fBac753B601Da05e3661F2E959510b)
- [ ] Check if demo mode is calling wrong contract methods
- [ ] Add fallback to display position count + basic data if values fail
- [ ] **GOAL**: Show positions exist with non-zero values

### PHASE 2: Demo Polish (1 hour max)
- Trading flow smoke test + final verification as outlined in build-plan.md

### Key Constraints Respected:
- ✅ **NO CONTRACT REDEPLOYMENT** - Working only with existing deployed contracts
- ✅ **NO ADDRESS CHANGES** - Using protected contract addresses as-is  
- ✅ **THREE PRIORITIES ONLY** - Following build-plan.md structure exactly
- ✅ **FRONTEND FOCUS** - Addressing data loading issues without touching contracts

**Success Criteria**: All 3 tabs load and display data, no blank screens during investor demo, total time budget 4 hours maximum.

This plan now correctly follows the build-plan.md priorities and respects the deployment constraints from CLAUDE.md.