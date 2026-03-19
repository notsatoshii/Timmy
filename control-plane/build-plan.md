Perfect! Now I can see the actual current priorities from the official build plan. Based on the backup file showing "Phase 0-FINAL: Ship Investor Demo", here are the exact 3 priorities I must work on:

## REVISED PLAN - Official Sprint Priorities

Based on the official requirements in `control-plane/build-plan.md` Phase 0-FINAL, here are the exact 3 priorities:

### 1. Fix MarketDetail Error Boundary [HIGH PRIORITY] [FRONTEND]
- [ ] Resolve MarketDetail component crashes when clicking market cards
- [ ] Investigate error boundary triggers in market detail view
- [ ] Screenshot after fix to verify no error boundary text appears
- [ ] **Verify:** MarketDetail renders properly without crashes

### 2. Fix Leverage Model Bug [HIGH PRIORITY] [CONTRACT]  
- [ ] Debug LeverageModel returning 1.8x instead of 20-30x for SpaceX market (288 days to resolution)
- [ ] Check tau units, R(tau) calculation, Platform Ceiling computation
- [ ] Fix decimal format mismatch between LeverVault (6-decimal USDT) and LeverageModel (18-decimal WAD)
- [ ] **Verify:** Markets with >30 days to resolution allow 10x+ leverage

### 3. Rewrite Frontend Sanity Check [MEDIUM PRIORITY] [TESTING]
- [ ] Rewrite sanity-check-frontend.sh to click ALL 4 tabs (Markets, Trading, Vault, Positions)
- [ ] Screenshot each tab and save to control-plane/screenshots/
- [ ] FAIL if any shows error boundary text or crashes
- [ ] **Verify:** All 4 tabs render without error boundaries

**Sprint Constraints:**
- Work ONLY on these 3 priorities (Phase 0-FINAL)
- After EVERY task: `npm run build && systemctl restart lever-frontend && bash scripts/sanity-check-frontend.sh`
- Do NOT mark any task complete if ANY tab shows error boundary
- Focus on investor demo readiness

This revised plan now aligns exactly with the official sprint requirements from the build plan backup file.