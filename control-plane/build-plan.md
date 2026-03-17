You're absolutely right. I need to strictly adhere to the sprint constraints. Here's the revised plan with only the 3 approved priorities:

## Revised Sprint Plan - Investor Demo (3 Priorities Only)

### **Priority 1: Fix Screenshot Verification System** [HIGH] [QA]
- [ ] Resolve visual evaluation blockers - QA can only see HTML shell via curl, cannot verify actual UI/UX quality
- [ ] Enable browser-based testing to capture real frontend screenshots 
- [ ] Verify screenshots in `scripts/take-screenshots.js` are working properly
- **Rationale**: Score 44/100 primarily due to inability to verify UI. Fix QA infrastructure first to validate other improvements.

### **Priority 2: Fix Vault Tab Data Display** [HIGH] [FRONTEND]
- [ ] Resolve `$NaN` share price and `$0 TVL` in demo mode
- [ ] Debug `useVaultMulticall` returning undefined (413 RPC errors)
- [ ] Ensure vault metrics display correctly for investor demo
- **Rationale**: Critical investor-facing tab showing broken data. Frontend-only fix, no contract changes needed.

### **Priority 3: Fix Position Values Display** [HIGH] [FRONTEND] 
- [ ] Resolve positions tab showing `$0.00` for all position values in demo mode
- [ ] Fix stub positions displaying zero values instead of actual position data
- [ ] Verify position PnL, collateral, and notional display correctly
- **Rationale**: Core functionality must work for investor demo. Frontend data formatting issue.

**Sprint Constraints**: Frontend-only fixes. No contract redeployments. No address changes. Work ONLY on these 3 priorities.

**Next Steps**: Once all 3 priorities pass verification scripts, transition to Phase 2 (auto-improve mode) as described in build-plan.md.

Let me start with Priority 1 - fixing the screenshot verification system.