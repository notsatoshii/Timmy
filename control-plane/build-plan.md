Based on the current system state and the timeout feedback, here's the **REVISED PLAN** focused on the actual critical issues:

## **FOCUSED PLAN** — Two Critical Issues Only

**Current System Status:**
- ✅ Health Check: 20/20 passed  
- ⚠️ QA Score: 60/100 (limited by vision system, not app functionality)
- ✅ Frontend: UP and serving
- ✅ All contracts operational

---

### **Critical Issue #1: MarketDetail Tab Verification**
- [ ] **Manual browser test** of MarketDetail tab functionality
- [ ] **Verify position opening** works through the UI (end-to-end user flow)  
- [ ] **Document working state** in known-issues.md
- **Time estimate**: 15 minutes

### **Critical Issue #2: Fix 24h Volume Display**  
- [ ] **Locate volume calculation** in frontend code
- [ ] **Update calculation** to show notional value (collateral × leverage) instead of just collateral
- [ ] **Test with existing positions** to verify correct display
- **Time estimate**: 30 minutes

---

### **Why This Plan Addresses Timeout Issues:**
1. **Only 2 tasks** instead of broad system overhauls
2. **45 minutes total** instead of multi-hour debugging sessions
3. **Specific, testable outcomes** instead of vague "fix everything" 
4. **Builds on healthy foundation** (20/20 health checks) instead of assuming broken systems

### **What's NOT Included (and why):**
- ❌ LP APY optimization (medium priority, system working)
- ❌ Insurance Fund investigation (already well-funded at 5.011e24)
- ❌ Oracle monitoring (already confirmed fresh and running)
- ❌ Major contract redeployments (protected contracts per CLAUDE.md)

**Next Action:** Start with MarketDetail tab verification since it's faster and will immediately confirm if the frontend is demo-ready.