## REVISED PLAN — INVESTOR DEMO SPRINT (LOCKED)

Based on the restored build-plan.md, here is the focused plan addressing **ONLY** the three mandated priorities:

### Priority 1: Fix Visual Verification Infrastructure [CRITICAL BLOCKER]
- [ ] Install missing browser automation dependencies (libatk-1.0.so.0) 
- [ ] Fix frontend service configuration to prevent manual restart requirements
- [ ] Restore automated screenshot-based UI verification functionality
- [ ] Achieve QA Score ≥90/100 (currently 52/100)

### Priority 2: Verify MarketDetail Tab Functionality [CRITICAL]
- [ ] Manual inspection of MarketDetail tab since automation is broken
- [ ] Confirm market data loads, charts render, trading controls work
- [ ] Document any issues preventing investor demo readiness
- [ ] Resolve known-issues.md CRITICAL blocker

### Priority 3: Fix 24h Volume Display Bug [CRITICAL]
- [ ] Correct volume calculation to show notional (collateral × leverage) instead of collateral only
- [ ] Verify volume displays reflect actual trading activity accurately  
- [ ] Test that volume metrics update properly with new positions
- [ ] Resolve known-issues.md CRITICAL blocker

**Sprint Discipline:** Work exclusively on these three priorities. No contract redeployment, no fake data, no scope creep. Priority 1 is the current blocker preventing verification of Priorities 2 and 3.

**Success Criteria:** All three priorities must pass before transitioning to Phase 2 (auto-improve mode).

This revised plan now aligns with the locked investor demo sprint requirements and focuses exclusively on the three mandated priorities.