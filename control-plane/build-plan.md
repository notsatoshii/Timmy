You're absolutely right. Let me create a plan that follows the exact 3 locked priorities without breaking them down into separate tasks. Based on the QA report and verification protocols, here is the corrected approach:

## **INVESTOR DEMO SPRINT - 3 LOCKED PRIORITIES**
*Target: QA score 60/100 → 85/100+*

### **Priority 1: Frontend Quality & Visual Verification** [CRITICAL]
**Work on ALL visual issues identified in QA report as a single priority:**

- Fix React app crashes and UI inconsistencies (QA score 60→85 target)
- Complete manual tab testing across Markets, Trading, Vault, Positions
- Verify wallet connection flow and error handling  
- Test mobile responsiveness and cross-browser compatibility
- Run `node scripts/tab-sanity.js` for mandatory tab validation
- Ensure all visual issues from QA report are resolved

**Success Criteria**: All 5 visual issues fixed, manual tests pass, professional appearance

---

### **Priority 2: Infrastructure & Automation** [CRITICAL]
**Fix browser automation and monitoring infrastructure as single priority:**

- Install missing `libatk-1.0.so.0` dependency for headless Chrome
- Repair `take-screenshots.js` script to work with current frontend
- Implement `/api/health` endpoint for real-time monitoring display
- Ensure `node scripts/visual-verify.js` passes consistently
- Fix Puppeteer automation for investor demo screenshots

**Success Criteria**: Screenshot automation functional, health monitoring active

---

### **Priority 3: User Journey & Demo Polish** [CRITICAL]  
**End-to-end demo readiness as single priority:**

- Test complete user flow: view markets → open position → check vault → view positions
- Verify all displayed data is live (not fabricated per build constraints)
- Fix numerical formatting issues (currency, percentages, decimals)  
- Remove any dev artifacts or placeholder text
- Ensure `bash scripts/user-flow-test.sh` passes without issues

**Success Criteria**: Smooth investor demo, professional polish, all verification scripts pass

---

### **Mandatory Verification After Each Priority**
- `bash control-plane/preflight.sh` before starting
- `bash control-plane/health-check.sh` (must pass)
- `node scripts/visual-verify.js` (for frontend changes)
- `bash scripts/user-flow-test.sh` (for contract interactions)

Should I proceed with **Priority 1: Frontend Quality & Visual Verification**?