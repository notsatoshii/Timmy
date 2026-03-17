Looking at the feedback about Claude timeout, I need to streamline this plan to focus on the absolute minimum viable demo requirements with more specific, time-boxed actions.

## REVISED PLAN - INVESTOR DEMO (Timeout-Optimized)

### PHASE 1: Critical Blockers (2-3 hours max)

**1A. Fix Screenshot Verification [60 min]**
- [ ] Run `node scripts/take-screenshots.js` and capture specific error
- [ ] Check if browser/puppeteer process is hanging (timeout after 30 sec)
- [ ] Add fallback: manual screenshot + basic UI load test if automation fails
- [ ] GOAL: Confirm UI loads without blank screens

**1B. Fix Vault Display [45 min]** 
- [ ] Check `config/contracts.ts` - verify LeverVault address matches deployed contract
- [ ] Add console.log to useVaultMulticall to see exact undefined response
- [ ] If RPC issues persist, add mock vault data for demo mode only
- [ ] GOAL: Show meaningful TVL/share price numbers

**1C. Fix Position Values [45 min]**
- [ ] Verify PositionManager contract address in frontend config
- [ ] Check if demo mode is calling wrong contract methods
- [ ] Add fallback to display position count + basic data if values fail
- [ ] GOAL: Show positions exist with non-zero values

### PHASE 2: Demo Polish (1 hour max)

**2A. Trading Flow Smoke Test [30 min]**
- [ ] Test one market open position flow in demo mode
- [ ] If "Position Open Failed" persists, document but don't fix (post-demo)
- [ ] Ensure error states don't crash the UI
- [ ] GOAL: UI functions without crashes during demo

**2B. Final Verification [30 min]**
- [ ] Run health check: `bash control-plane/health-check.sh`
- [ ] Manual test: All 3 tabs load and display data
- [ ] Document any remaining issues for post-demo fixes
- [ ] GOAL: Functional demo with known limitations documented

### DEFERRED (Post-Demo)
- Security scanning investigation
- 24h Volume calculation fixes
- ExecutionEngine/LeverageModel mismatch analysis
- Complex RPC optimization

**Success Criteria for Investor Demo:**
1. ✅ Trading interface loads and renders
2. ✅ Vault tab shows meaningful TVL/metrics  
3. ✅ Positions tab displays existing positions
4. ✅ No blank screens or UI crashes during demo
5. ✅ Can navigate between all tabs smoothly

**Total Time Budget: 4 hours maximum**
**Fallback Strategy: If technical fixes fail, prepare manual demo with screenshots of working state**

This revised plan prioritizes speed and demo viability over perfect functionality, addressing the timeout constraint while ensuring investor demo success.