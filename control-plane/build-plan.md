Based on the QA report and investigating the actual issues, here's the **CORRECTED PLAN** that addresses the real problems and respects the protected contracts policy:

## REVISED PLAN: Critical Frontend Build Failure

### **Priority 1: Fix Frontend Build System [CRITICAL]** 
**Evidence:** Frontend serving directory listing instead of React app (QA score: 52/100)

- [ ] **Frontend build directory missing compiled assets** - no index.html, no JS/CSS bundles
- [ ] **React build process completely broken** - `npm run build` likely failing or incomplete  
- [ ] **Service running but serving raw build folder** instead of compiled React application
- [ ] **Complete application failure** - investors cannot access any product functionality

**Actions:**
- [ ] Navigate to `/home/lever/lever-protocol/frontend/` and run `npm run build`
- [ ] Verify build process generates `build/index.html` and JS/CSS assets
- [ ] Test that localhost:3000 serves React app instead of directory listing
- [ ] Ensure all required dependencies are installed and build scripts work

### **Priority 2: Investigate Leverage Limitation Issue [INVESTIGATION ONLY]**
**Policy:** ExecutionEngine (0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D) is PROTECTED - no redeployment allowed

- [ ] **Document the leverage limitation issue** without touching protected contracts
- [ ] **Test current behavior** to understand if it's configuration vs contract issue
- [ ] **Log findings** for future investigation if needed
- [ ] **Verify integration** between ExecutionEngine and LeverageModel addresses

### **Priority 3: Verify Demo Mode Data Display [LOW]**
**Note:** QA report shows contract data is working (TVL: 6.05e13, Positions: 215, all "ok" status)

- [ ] **Verify actual data display issues exist** before fixing (no evidence of $NaN in QA report)
- [ ] **Test vault and positions tabs** once frontend is rebuilt
- [ ] **Only fix if issues are confirmed** after frontend build is working

---

## **What Changed from Original Plan:**

❌ **REMOVED:** ExecutionEngine redeployment (violates protected contracts policy)  
❌ **REMOVED:** Assumptions about $NaN/$0 display issues (not confirmed in QA report)  
✅ **FOCUSED:** Actual critical issue - frontend build failure blocking entire demo  
✅ **EVIDENCE-BASED:** All tasks now based on confirmed QA report findings  

**The frontend build failure is blocking everything else** - investors see a file directory instead of the trading application. This must be fixed first before any other issues can be assessed.