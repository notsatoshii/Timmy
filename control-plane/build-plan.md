Now I understand! Based on the QA report showing a **36/100 score** with 8 critical visual issues, I need to revise the build plan to prioritize the most severe demo-blocking problems first.

## **REVISED PLAN** (Based on QA Score 36/100)

### **IMMEDIATE PRIORITY: Demo-Blocking Visual Issues** 

**Task 1.2A** [CRITICAL]: Fix $39B decimal conversion bug in MarketDetail
- Root cause: WAD vs USDT formatting error showing $39B instead of realistic ~$150K 
- Target: Realistic OI displays (~$150K range)

**Task 1.3A** [CRITICAL]: Restore frontend position opening 
- Issue: CLI works but frontend fails with "Position Open Failed"
- Test: 5-15x leverage position opening in demo mode

**Task 1.4A** [CRITICAL]: Fix MarketDetail error boundary crashes
- Root cause: Error boundaries failing and causing tab crashes
- Target: Stable navigation across all 4 tabs

### **SECONDARY PRIORITY: Validation Infrastructure**

**Task 2.1B** [HIGH]: Fix browser automation dependencies  
- Issue: Missing libatk preventing screenshot validation
- Target: Automated investor demo verification working

**Task 2.2B** [HIGH]: Rewrite sanity-check-frontend.sh for all 4 tabs
- Current: 3/4 tabs failing sanity checks  
- Target: All tabs (Trading, Positions, Vault, MarketDetail) passing with screenshots

### **FINAL VERIFICATION**

**Task 3.1C** [MEDIUM]: Complete QA score improvement
- Current: 36/100 → Target: 80+
- Focus: Realistic data display, stable navigation, working position opening

**Revised Working Order:** 1.2A → 1.3A → 1.4A → 2.1B → 2.2B → 3.1C

**Success Criteria:** All 8 visual issues resolved, functional investor demo, QA score >80

Should I **start with Task 1.2A** (fixing the $39B decimal conversion bug)?