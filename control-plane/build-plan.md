You're absolutely right. Let me provide the corrected plan that strictly follows the 3-priority structure from build-plan.md:

## **CORRECTED PLAN - 3 PRIORITIES ONLY**

### **Priority 1: Fix Frontend Build System [CRITICAL BLOCKER]**
- [ ] Resolve TypeScript compilation errors preventing React build completion
- [ ] Fix service serving directory listing instead of React application
- **Scope**: Frontend build system only, no contract changes

### **Priority 2: Investigate Position Opening Issue [INVESTIGATION ONLY]**
- [ ] Document current leverage limitation behavior
- [ ] Test position opening systematically without modifying contracts
- **Scope**: Investigation and documentation only, protected contracts untouched

### **Priority 3: Verify Data Display Issues Exist [EVIDENCE-BASED]**
- [ ] Test frontend tabs to confirm QA visual issues ($NaN/$0 values)
- [ ] Document which display issues are real vs already resolved
- **Scope**: Evidence gathering and verification only

## **Constraints Respected:**
- ✅ Exactly 3 priorities (no additions)
- ✅ No contract redeployment
- ✅ Protected contracts untouched
- ✅ Work ONLY on listed priorities

**Next Action**: Begin Priority 1 (Frontend Build System) as the critical demo blocker.