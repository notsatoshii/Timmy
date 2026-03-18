Based on the official build-plan.md backup, here is the **corrected plan** focusing strictly on the 3 official priorities:

# **Revised Plan: Official Build Plan Priorities Only**

## **Priority #1: Fix Frontend Build & Deployment [CRITICAL] [FRONTEND]**

**Remaining tasks from Phase 0-FINAL Step 1 & 2:**
- [ ] **1.1** Fix MarketDetail error boundary (crashes when clicking markets)
- [ ] **1.2** Rewrite sanity-check-frontend.sh to click ALL 4 tabs, screenshot each, FAIL if any shows error boundary or crashes

**Completed:** Trading tab, Vault tab, and Positions tab error boundaries all fixed.

## **Priority #2: Fix Demo Mode Data Display [CRITICAL] [FRONTEND]**

**Remaining tasks from Phase 0-FINAL Step 4 & 4b:**
- [ ] **2.1** Fix 24h Volume to show NOTIONAL (collateral × leverage), not collateral only
- [ ] **2.2** Fix MarketDetail OI displaying $39B instead of ~$150K (WAD vs USDT decimal bug)
- [ ] **2.3** Test complete user flow through all tabs in demo mode
- [ ] **2.4** Ensure all numerical values display properly formatted (verify no remaining NaN/zero issues)

**Completed:** Vault tab data display fixed (TVL $60.5M, Share Price $1.00, APY 0.2%).

## **Priority #3: Fix Position Opening Functionality [HIGH] [CONTRACT]**

**Remaining tasks from Phase 0-FINAL Step 3 & 4:**
- [ ] **3.1** Fix leverage bug: SpaceX shows 1.8x max instead of 20-30x (debug LeverageModel tau units, R(tau) calculation, Platform Ceiling)
- [ ] **3.2** After leverage fix: open 10 positions at 5-15x leverage using test wallet and verify on-chain
- [ ] **3.3** Fix frontend position opening in demo mode (contract works via CLI but UI shows error)
- [ ] **3.4** Verify APY updates correctly with new higher-leverage OI

**Completed:** Position opening backend mechanism working, leverage limitation root cause identified (decimal format mismatch).

---

**Mandatory verification after each task:**
```bash
cd frontend/user-app && npm run build
systemctl restart lever-frontend
sleep 3
bash scripts/sanity-check-frontend.sh
```

**Current Status:** QA score improvement blocked until MarketDetail tab stops crashing and leverage model returns realistic values (10x+ instead of 1.8x).

**Constraints:** No contract redeployments. Work within existing deployed addresses. Focus on configuration and frontend fixes per CLAUDE.md protected contracts list.