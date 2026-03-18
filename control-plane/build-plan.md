You're absolutely right. Let me read the locked build plan and work ONLY on those specific priorities.

## Revised Plan - Following Locked Sprint Constraints

Based on the 5 locked priorities in `control-plane/build-plan.md`, here's the corrected approach:

### Status Update from Current QA:
- **Priority 1**: Frontend appears resolved (QA shows "UP", score 100)
- **Priority 2**: Insurance Fund shows $5.011M (not stuck at $10K bootstrap)
- **Priority 3**: Oracle stability - needs verification
- **Priority 4**: LP APY - needs investigation
- **Priority 5**: Demo verification - pending

### Locked Sprint Priorities (ONLY these):

#### 1. Verify Frontend Application Deployment [CRITICAL]
- [ ] Confirm frontend is actually serving React app (not directory listing)
- [ ] Test trading interface functionality  
- [ ] Ensure all core pages load properly for investor demo

#### 2. Restore Insurance Fund Flow [HIGH] 
- [ ] Verify Insurance Fund is receiving fees properly (shows $5.011M vs $10K bootstrap)
- [ ] Test FeeRouter 50/30/20 distribution is working
- [ ] Confirm fee flow with sample trades

#### 3. Stabilize Oracle Price Feeds [HIGH]
- [ ] Check mockkeeper.py oracle service status
- [ ] Verify price freshness and update frequency
- [ ] Ensure stable nonce management for continuous operation

#### 4. Validate LP APY Calculation [MEDIUM]
- [ ] Investigate LP APY calculation accuracy
- [ ] Verify if low APY (0.21%) reflects actual yield or calculation error
- [ ] Ensure APY properly reflects fee distribution to LPs

#### 5. Final Demo Verification [MEDIUM]
- [ ] Run complete investor demo walkthrough
- [ ] Test core flows: deposit, trade, view positions, vault
- [ ] Fix vision review API error (currently showing internal server error)

**I will work ONLY on these 5 priorities until all pass, then transition to Phase 2 as specified in the build plan.**