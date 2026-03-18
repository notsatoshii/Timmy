## REVISED PLAN - Adherence to Locked Sprint Priorities

You're absolutely right. Here's the corrected plan that strictly follows the three locked priorities in `/control-plane/build-plan.md`:

### **Priority 1: Complete Manual Verification Checklist** [CRITICAL] [FRONTEND]
- [ ] 1. Test Markets tab - verify market data loads (not blank)
- [ ] 2. Test Trading tab - confirm position interface is functional  
- [ ] 3. Test Vault tab - validate deposit form and vault info display
- [ ] 4. Test Positions tab - ensure positions table shows correctly
- [ ] 5. Browser compatibility check (no console errors)
- [ ] 6. Mobile responsive design verification
- [ ] 7. Document verification results

**Success Criteria**: All 7 manual verification items pass

### **Priority 2: Fix Browser Automation Dependencies** [CRITICAL] [INFRASTRUCTURE]
- [ ] 1. Install missing Puppeteer dependency (`libatk-1.0.so.0`)
- [ ] 2. Verify headless Chrome functionality
- [ ] 3. Test automated screenshot generation via `take-screenshots.js`
- [ ] 4. Confirm visual regression testing works

**Success Criteria**: Puppeteer-based visual testing fully operational

### **Priority 3: Investor Demo Polish** [CRITICAL] [DEMO]
- [ ] 1. Verify real market data is displaying (not fabricated)
- [ ] 2. Test complete user journey: view markets → open position → check vault
- [ ] 3. Ensure all numerical displays are formatted properly
- [ ] 4. Confirm no placeholder text or development artifacts visible

**Success Criteria**: Demo runs smoothly with no technical hiccups

### **After All Three Priorities Pass**
- Transition to Phase 2 (auto-improve mode) per build plan
- Document any remaining issues for future phases

This revised plan focuses exclusively on the locked priorities. Should I proceed with Priority 1 manual verification?