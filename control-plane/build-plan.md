You're absolutely right. I apologize for the misaligned approach. Let me follow the existing build plan priorities and complete the remaining checklist items:

## Revised Focus: Complete Existing Build Plan Priorities

Based on `/home/lever/lever-protocol/control-plane/build-plan.md`, here are the specific **remaining tasks** to complete:

### **Priority 1: MarketDetail Error Boundary** [CRITICAL]
- [ ] **Task 1.2**: Rewrite sanity-check-frontend.sh to test ALL 4 tabs (Trading, Positions, Vault, MarketDetail) with screenshots
- [ ] **Task 1.3**: Ensure error boundary failures cause script to exit with failure status

### **Priority 2: Demo Mode Data Display** [CRITICAL] 
- [ ] **Task 2.2**: Fix MarketDetail OI showing $39B instead of realistic ~$150K (WAD vs USDT decimal conversion bug)
- [ ] **Task 2.3**: Verify all numerical formatting displays properly in demo mode across all tabs

### **Priority 3: Position Opening via Configuration** [HIGH]
- [ ] **Task 3.2**: Test position opening with 5-15x leverage using test wallet after configuration fix
- [ ] **Task 3.3**: Fix frontend position opening in demo mode (contracts work via CLI, frontend shows "Position Open Failed")

### **Priority 4: Browser Automation** [MEDIUM]
- [ ] **Task 4.2**: Restore automated screenshot testing capability for investor demo validation

### **Priority 5: Final Verification** [MEDIUM]
- [ ] **Task 5.2**: Target QA score improvement from current 60 to 80+ via MarketDetail stability and realistic demo data

**Approach**: Work through these tasks in priority order, using **configuration fixes only** (no contract redeployment), then run verification scripts to achieve 80+ QA score for investor demo readiness.

Should I start with Task 1.2 (rewriting the sanity check script)?