You're absolutely right - I apologize for not following the official build plan. Based on your feedback, here is the corrected plan that matches the exact 3 locked priorities:

## **Revised Plan - Official Build Plan Compliance**

### **Step 1: Fix Broken Tabs [CRITICAL] [FRONTEND]**
- [ ] **P0** Fix MarketDetail error boundary crash (occurs when clicking any market)
- [ ] Investigate what's causing markets to crash when clicked
- [ ] Implement proper error boundary handling in MarketDetail component
- **Verification**: MarketDetail tab renders without crashes, take screenshot after fix

### **Step 2: Fix the Sanity Check [CRITICAL] [FRONTEND]**  
- [ ] **P0** Rewrite `sanity-check-frontend.sh` to test ALL 4 tabs with automated screenshots
- [ ] Script must click each tab, screenshot, and FAIL if any shows error boundary text or crashes
- [ ] Save screenshots to `control-plane/screenshots/` with clear tab names
- **Verification**: Automated sanity check passes for all 4 tabs with clean screenshots

### **Step 3: Fix Leverage Model [CRITICAL] [CONTRACTS]**
- [ ] **P0** Debug leverage bug: SpaceX market (288 days to resolution) returns 1.8x instead of 20-30x
- [ ] Investigate tau units, R(tau) calculation, and Platform Ceiling in existing LeverageModel
- [ ] Fix so markets with >30 days allow 10x+ leverage (NO contract redeployment)
- [ ] **P0** After fix: open 10 positions at 5-15x leverage across 5 markets using test wallet
- **Verification**: Markets with >30 days allow 10x+ leverage, positions open successfully on-chain

## **Sprint Lock Constraints**
- **NO contract redeployment allowed** - debug existing configuration only
- **Work ONLY on these 3 steps** until ALL pass verification 
- **Mandatory verification protocol**: `npm run build && systemctl restart lever-frontend && sleep 3 && take screenshots of ALL tabs`
- **Cannot transition** to other work until all 3 pass completely

This revised plan now exactly matches the locked sprint priorities and constraints.