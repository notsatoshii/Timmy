Perfect! Now I can see the actual current priorities from the official build plan. You're absolutely right - I need to follow the locked Phase 0-FINAL requirements, not make my own assessment. Here's the corrected plan:

## REVISED PLAN - Official Sprint Priorities (Phase 0-FINAL)

### 1. Fix MarketDetail Error Boundary [HIGH PRIORITY] [FRONTEND]
- [ ] Resolve MarketDetail component crashes when clicking market cards
- [ ] Investigate error boundary triggers in market detail view
- [ ] Test that MarketDetail renders without crashes
- [ ] **Success criteria:** MarketDetail renders properly without error boundaries

### 2. Fix Leverage Model Bug [HIGH PRIORITY] [CONTRACT]  
- [ ] Debug LeverageModel returning 1.8x instead of 20-30x for SpaceX market (288 days to resolution)
- [ ] Check tau units, R(tau) calculation, Platform Ceiling computation
- [ ] Fix decimal/calculation issues causing low leverage caps
- [ ] **Success criteria:** Markets with >30 days allow 10x+ leverage

### 3. Rewrite Frontend Sanity Check [MEDIUM PRIORITY] [TESTING]
- [ ] Rewrite `sanity-check-frontend.sh` to click ALL 4 tabs (Markets, Trading, Vault, Positions)
- [ ] Screenshot each tab and save to control-plane/screenshots/
- [ ] FAIL script if any tab shows error boundary text or crashes
- [ ] **Success criteria:** All 4 tabs render without error boundaries

**Sprint Constraints:**
- Work ONLY on these 3 priorities until ALL pass
- Do NOT work on JavaScript bundle 404 or Insurance Fund issues yet  
- After every task: `npm run build && systemctl restart lever-frontend && bash scripts/sanity-check-frontend.sh`
- Do NOT mark any task complete if ANY tab shows error boundary
- Focus on investor demo readiness

Thank you for the correction - this plan now aligns exactly with the official Phase 0-FINAL locked priorities from the build plan.