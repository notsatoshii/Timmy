Based on the actual build plan and QA report evidence, here's the **revised plan** that complies with sprint constraints:

## **REVISED PLAN: Three Locked Priorities Only**

### **Priority 1: Fix QA Agent Data Extraction** [CRITICAL] [AUTOMATION]
- [ ] **Evidence**: QA report shows `data_checks: []` (empty array) while frontend is UP
- [ ] **Task**: Debug why QA agent can extract contract data but not frontend display values 
- [ ] **Impact**: Investors need to see metrics being captured for confidence

### **Priority 2: Fix MarketDetail Error Boundary** [CRITICAL] [FRONTEND]  
- [ ] **Evidence**: Build plan states "MarketDetail crashes when clicking markets"
- [ ] **Task**: Debug crash in MarketDetail component blocking investor walkthrough
- [ ] **Impact**: Core navigation flow must work for demo

### **Priority 3: Fix Frontend Position Opening** [CRITICAL] [FRONTEND]
- [ ] **Evidence**: Build plan states "Trading component shows errors in demo mode"  
- [ ] **Task**: Debug position opening failures in demo trading interface
- [ ] **Impact**: Trading simulation must work for investor demo

## **Sprint Constraints** ✅
- Frontend debugging only
- No contract redeployments 
- No address changes
- No fake data injection

## **Success Criteria**
All three priorities pass verification scripts: `health-check.sh`, `take-screenshots.js`, `user-flow-test.sh`

**Ready to start with Priority 1 (QA data extraction)** since that has the clearest evidence in the current QA report. Proceed?