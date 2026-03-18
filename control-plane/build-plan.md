Perfect! Now I have the official plan. Let me create a corrected approach that follows the exact 3 priorities and constraints:

## **Corrected Plan: Following Official Build Plan**

### **Priority #1: Fix Frontend Build & Deployment [CRITICAL] [FRONTEND]**
- [ ] **1.1** Fix MarketDetail error boundary (crashes when clicking markets)  
- [ ] **1.2** Rewrite sanity-check-frontend.sh to click ALL 4 tabs, screenshot each, FAIL if any shows error boundary

**Status**: Trading, Vault, Positions tabs fixed. Only MarketDetail remains.

### **Priority #2: Fix Demo Mode Data Display [CRITICAL] [FRONTEND]**
- [ ] **2.1** Fix 24h Volume to show NOTIONAL (collateral × leverage), not collateral only
- [ ] **2.2** Fix MarketDetail OI displaying $39B instead of ~$150K (WAD vs USDT decimal bug)
- [ ] **2.3** Test complete user flow through all tabs in demo mode
- [ ] **2.4** Ensure all numerical values display properly formatted

**Status**: Vault tab fixed (TVL $60.5M, Share Price $1.00, APY 0.2%). Volume and OI display remain.

### **Priority #3: Fix Position Opening Functionality [HIGH] [CONFIGURATION]**
- [ ] **3.1** Fix leverage bug via **configuration fixes**: SpaceX shows 1.8x max instead of 20-30x (decimal format mismatch per official plan)
- [ ] **3.2** Open 10 positions at 5-15x leverage using test wallet after fix
- [ ] **3.3** Fix frontend position opening in demo mode (contract works via CLI)
- [ ] **3.4** Verify APY updates with new higher-leverage OI

**Status**: Root cause identified as decimal format mismatch. Fix through configuration, NOT redeployment.

## **Key Constraints Followed:**
- ✅ No contract redeployments  
- ✅ Work within existing deployed addresses
- ✅ Focus on configuration and frontend fixes
- ✅ Respect PROTECTED contracts list

## **Verification Protocol:**
```bash
cd frontend/user-app && npm run build
systemctl restart lever-frontend  
sleep 3
bash scripts/sanity-check-frontend.sh
```

**Target Outcome**: QA score improvement via MarketDetail stability + realistic leverage values (10x+ instead of 1.8x) + proper demo mode data display.

Ready to proceed with Priority #1 (MarketDetail error boundary fix)?