Based on reading the actual build-plan.md file, I can see the 3 locked priorities. Let me create a plan that works ONLY on these specific priorities:

## **INVESTOR DEMO SPRINT - 3 LOCKED PRIORITIES**
*From `/home/lever/lever-protocol/control-plane/build-plan.md`*

### **Priority 1: Frontend Quality & Visual Verification** [CRITICAL]
**Target: Fix all 5 visual issues to boost QA score from 60/100**

**Tasks:**
- Fix React App rendering/component crashes
- Resolve UI/UX visual inconsistencies  
- Implement error boundaries and user-friendly error messages
- Test and fix wallet connection (MetaMask integration)
- Verify mobile responsiveness and fix layout issues
- Manual tab testing (Markets, Trading, Vault, Positions)
- Browser compatibility testing (Chrome/Firefox/Safari)

**Success Criteria**: All visual issues resolved, manual tests pass

### **Priority 2: Infrastructure & Automation** [CRITICAL] 
**Target: Fix browser automation for reliable testing**

**Tasks:**
- Install missing `libatk-1.0.so.0` dependency
- Fix Puppeteer/headless Chrome automation
- Repair `take-screenshots.js` script
- Implement `/api/health` endpoint for monitoring
- Create consistent demo data for investor presentations

**Success Criteria**: Visual testing operational, health monitoring active

### **Priority 3: User Journey & Demo Polish** [CRITICAL]
**Target: Smooth investor demo experience**

**Tasks:**
- Test complete end-to-end flow (view markets → open position → check vault → view positions)
- Verify all market data is live (not fabricated)
- Fix numerical formatting (currency, percentages, decimals)
- Remove dev artifacts and placeholder text
- Ensure `bash scripts/user-flow-test.sh` passes

**Success Criteria**: Demo runs without technical hiccups, professional appearance

### **Quality Gates (After Each Priority)**
- Run `bash control-plane/health-check.sh` (must pass)
- Run `node scripts/take-screenshots.js` (must work) 
- Manual browser testing (must be smooth)

**Target Outcome:** QA score 60/100 → 85/100+, then transition to Phase 2 auto-improve mode.

Should I proceed with Priority 1 (Frontend Quality & Visual Verification)?