Perfect! Now I understand the correct structure. Looking at the original build plan, I can see that tasks 1.1, 2.1, 3.1, 4.1, and 5.1 are already completed (marked [x]). Let me create the correct revised plan following the exact task numbering:

## Corrected Plan: Complete All Remaining Build Plan Tasks

### **Priority 1: MarketDetail Error Boundary** [CRITICAL]
- [ ] **Task 1.2**: Rewrite sanity-check-frontend.sh to test ALL 4 tabs (Trading, Positions, Vault, MarketDetail) with screenshots
- [ ] **Task 1.3**: Ensure error boundary failures cause script to exit with failure status

### **Priority 2: Demo Mode Data Display** [CRITICAL] 
- [ ] **Task 2.2**: Fix MarketDetail OI showing $39B instead of realistic ~$150K (WAD vs USDT decimal conversion bug)
- [ ] **Task 2.3**: Verify all numerical formatting displays properly across all tabs in demo mode

### **Priority 3: Position Opening via Configuration** [HIGH]
- [ ] **Task 3.2**: Test position opening with 5-15x leverage using test wallet after configuration fix
- [ ] **Task 3.3**: Fix frontend position opening in demo mode (contracts work via CLI, frontend shows "Position Open Failed")

### **Priority 4: Browser Automation** [MEDIUM]
- [ ] **Task 4.2**: Restore automated screenshot testing capability for investor demo validation

### **Priority 5: Final Verification** [MEDIUM]
- [ ] **Task 5.2**: Target QA score improvement from current 60 to 80+ via MarketDetail stability and realistic demo data

**Working Order**: 1.2 → 1.3 → 2.2 → 2.3 → 3.2 → 3.3 → 4.2 → 5.2

**Constraints**: Configuration fixes only, no contract redeployment, no address changes, no fake data injection.

Should I start with **Task 1.2** (rewriting the sanity-check-frontend.sh script to test all 4 tabs)?