Based on the feedback and CLAUDE.md constraints, here's the **corrected 3-priority plan** that respects all policies:

## **REVISED PLAN - CLAUDE.md COMPLIANT**

### **Priority 1: Fix Frontend Build System [CRITICAL BLOCKER]**
- [ ] Resolve TypeScript compilation error (TS18046) preventing build completion
- [ ] Generate proper index.html and React assets 
- [ ] Fix service serving directory listing instead of application
- [ ] Clean up broken build directories and establish stable build process
- **Constraint**: Frontend-only changes, no contract touches
- **Impact**: Currently blocks entire demo (vision scores: 1-2/10)

### **Priority 2: Investigate Position Opening Issue [INVESTIGATION ONLY]**
- [ ] Document current leverage limitation behavior without changing contracts
- [ ] Test position opening with different leverage values to characterize issue
- [ ] Log findings for future reference but do NOT redeploy ExecutionEngine
- **Constraint**: Protected contracts (ExecutionEngine 0xc749C6..., LeverageModel 0x474E2e...) are off-limits
- **Impact**: Document scope of issue for future phases

### **Priority 3: Verify Data Display Issues Exist [EVIDENCE-BASED]**
- [ ] Test frontend tabs systematically to verify QA visual issues
- [ ] Check if $NaN/$0 display issues actually exist (QA shows TVL 6.05e13 = ok)
- [ ] Document which display issues are real vs. already resolved
- **Constraint**: Investigation only, fix only confirmed issues
- **Impact**: Evidence-based approach to remaining frontend issues

## **Key Constraints Respected:**
- ✅ **3 priorities only** (not 5)
- ✅ **No contract redeployment** 
- ✅ **No address changes**
- ✅ **Protected contracts untouched**
- ✅ **Focus on frontend/investigation**

**Next Action**: Begin Priority 1 - Frontend Build System fix as the critical demo blocker.