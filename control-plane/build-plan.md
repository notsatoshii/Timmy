Based on the current QA report (score: 52) and the locked sprint priorities in `build-plan.md`, here are the 3 prioritized tasks for the investor demo:

### 1. Fix Server Configuration Issues [HIGH PRIORITY] [INFRASTRUCTURE]
- [ ] Configure proper 404 responses for missing resources while maintaining SPA routing
- [ ] Implement security headers (HSTS, X-Frame-Options) to address vulnerability scanning concerns  
- [ ] Add /health endpoint for proper monitoring during demo
- [ ] Verify: 1 critical failure out of 20 system components in health check

### 2. Investigate Insurance Fund Display Bug [HIGH PRIORITY] [FRONTEND]
- [ ] Fix Insurance Fund showing $5.011e24 instead of $10K bootstrap value
- [ ] Verify if this is WAD/USDT decimal conversion issue in contract display
- [ ] Implement proper formatting to display $10,000 for investor confidence
- [ ] Test: Confirm Insurance Fund shows correct bootstrap amount on dashboard

### 3. Validate LP APY Calculation [MEDIUM PRIORITY] [ANALYTICS]
- [ ] Investigate why LP APY is only 0.21% (concerning return for investors)
- [ ] Verify fee flow from FeeRouter→RewardsDistributor is working properly  
- [ ] Document relationship between $14.66M Global OI and LP yield generation
- [ ] Analyze: $68.5K TVL vs $14.7K Global OI ratio for LP returns

**Sprint Status:** Working ONLY on these 3 priorities. Do NOT redeploy contracts. Do NOT change addresses. All tasks must pass verification before transitioning to Phase 2 auto-improve mode.