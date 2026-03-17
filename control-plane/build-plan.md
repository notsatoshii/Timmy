Perfect! Now I can see the actual **three critical priorities** from the official build plan. Here's the **corrected plan** that strictly follows the locked sprint:

## Revised Plan - Official Build Plan Compliance

### **Step 1: Fix Broken Tabs [CRITICAL] [FRONTEND]**
- [ ] **P0** Fix MarketDetail error boundary (shown when clicking a market). Screenshot after.
- **Verification**: MarketDetail tab renders without crashes, error boundary shows details properly

### **Step 2: Fix the Sanity Check [CRITICAL] [FRONTEND]**  
- [ ] **P0** Rewrite sanity-check-frontend.sh: must click ALL 4 tabs, screenshot each, FAIL if any shows error boundary text or crashes. Save screenshots to control-plane/screenshots/ with tab name.
- **Verification**: Automated sanity check passes for all 4 tabs with clean screenshots

### **Step 3: Fix Leverage Model [CRITICAL] [CONTRACTS]**
- [ ] **P0** Leverage bug: SpaceX resolves Dec 2026 (288 days). Max leverage should be 20-30x but returns 1.8x. Debug LeverageModel — check tau units, R(tau) calculation, Platform Ceiling. Fix so markets with >30 days to resolution allow 10x+ leverage.
- [ ] **P0** After leverage fix: open 10 positions at 5-15x leverage across 5 markets using test wallet. Verify on-chain.
- **Verification**: Markets with >30 days allow 10x+ leverage, positions open successfully

## Sprint Lock Rules
- **NO contract redeployment** - Debug existing LeverageModel configuration instead
- **Work ONLY on these 3 steps** until ALL pass verification 
- **Run mandatory verification** after each step: `npm run build && systemctl restart lever-frontend && sleep 3 && take screenshots of ALL tabs`
- **Transition to Phase 2** only after all three steps pass completely

This plan now correctly aligns with the locked sprint priorities and respects the contract redeployment constraints.