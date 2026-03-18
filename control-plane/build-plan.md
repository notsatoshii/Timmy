Based on your feedback and the QA report showing 60/100 with 5 visual verification issues, here's the revised plan that addresses the specific concerns while staying within the locked sprint priorities:

## **REVISED INVESTOR DEMO SPRINT PLAN** 
*Addressing QA Score 60/100 & 5 Visual Issues*

### **Priority 1: Frontend Quality & Visual Verification** [CRITICAL]
**Target: Fix all 5 visual issues to boost QA score**

- [ ] 1. **React App Verification** - Fix any component crashes or rendering issues
- [ ] 2. **UI/UX Quality** - Review and polish visual inconsistencies, spacing, alignment
- [ ] 3. **Error Handling** - Implement proper error boundaries and user-friendly error messages
- [ ] 4. **Wallet Connection Testing** - Test MetaMask integration across different states (connected/disconnected/switching)
- [ ] 5. **Mobile Responsiveness** - Verify layouts work on mobile devices, fix responsive issues
- [ ] 6. **Manual Tab Testing**:
  - Markets tab (verify data loads, not blank)
  - Trading tab (position interface functional)
  - Vault tab (deposit form + info display)
  - Positions tab (table displays correctly)
- [ ] 7. **Browser Compatibility** - Test Chrome/Firefox/Safari, fix console errors

**Success Criteria**: All visual issues resolved, manual tests pass

### **Priority 2: Infrastructure & Automation** [CRITICAL] 
**Target: Fix browser automation for reliable testing**

- [ ] 1. **Puppeteer Dependencies** - Install missing `libatk-1.0.so.0`
- [ ] 2. **Headless Chrome** - Verify browser automation works
- [ ] 3. **Screenshot Testing** - Fix `take-screenshots.js` script
- [ ] 4. **Health Check Endpoint** - Implement `/api/health` for system monitoring
- [ ] 5. **Demo Mode** - Create consistent demo data for investor presentations

**Success Criteria**: Visual testing operational, health monitoring active

### **Priority 3: User Journey & Demo Polish** [CRITICAL]
**Target: Smooth investor demo experience**

- [ ] 1. **End-to-End Flow** - Test: view markets → open position → check vault → view positions
- [ ] 2. **Real Data Verification** - Ensure market data is live (not fabricated)
- [ ] 3. **Numerical Formatting** - Proper currency, percentage, and decimal displays
- [ ] 4. **Clean Demo Environment** - Remove dev artifacts, placeholder text
- [ ] 5. **User Flow Testing** - Run `bash scripts/user-flow-test.sh` successfully

**Success Criteria**: Demo runs without technical hiccups, professional appearance

### **Quality Gates**
After each priority completion:
- Run `bash control-plane/health-check.sh` (must pass)
- Run `node scripts/take-screenshots.js` (must work)
- Manual browser testing (must be smooth)

### **Target Outcome**
- QA score improves from 60/100 to 85/100+
- All 5 visual issues resolved
- Investor-ready demo environment
- Transition to Phase 2 auto-improve mode

**Should I proceed with Priority 1 frontend quality fixes?**