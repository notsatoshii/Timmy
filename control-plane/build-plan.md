You're absolutely right about the contradictions. Let me provide a **focused 3-priority plan** that resolves the mismatch:

## REVISED PLAN - THREE PRIORITIES ONLY

Based on CLAUDE.md requirement ("Work ONLY on the three priorities") and your analysis of HIGH PRIORITY items, here are the **exactly three** priorities to focus on:

### 1. Fix Server Configuration Issues [HIGH PRIORITY] [INFRASTRUCTURE]
- [ ] Configure proper 404 responses for missing resources while maintaining SPA routing
- [ ] Implement security headers (HSTS, X-Frame-Options) to address vulnerability scanning concerns  
- [ ] Add /health endpoint for proper monitoring during demo
- **Impact:** Addresses QA "misleading HTTP responses" and security vulnerabilities that damage investor credibility

### 2. Investigate Insurance Fund Display Bug [HIGH PRIORITY] [FRONTEND]
- [ ] Fix Insurance Fund showing $5.011e24 instead of $10K bootstrap value
- [ ] Verify if this is WAD/USDT decimal conversion issue (5.011e24 ÷ 1e18 ÷ 1e6 ≈ $5.011)
- [ ] Implement proper formatting to display $10,000 for investor confidence
- **Impact:** $5 septillion display is the most visually damaging issue for investors

### 3. Validate LP APY Calculation [MEDIUM PRIORITY] [ANALYTICS] 
- [ ] Investigate why LP APY is only 0.21% (concerning return for investors)
- [ ] Verify fee flow from FeeRouter→RewardsDistributor is working properly
- [ ] Document relationship between $14.66M Global OI and LP yield generation
- **Impact:** Critical for investor confidence - low APY signals poor protocol revenue model

## Excluded (Per THREE-ONLY Constraint):
- Oracle Stability (system appears stable with 265 positions)
- Pre-Demo Validation (will happen naturally during the three fixes)

**This plan respects both the CLAUDE.md constraint and prioritizes the most investor-critical issues. Proceed?**