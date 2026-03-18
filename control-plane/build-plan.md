Perfect! The build plan already contains the correct revision. Here's the **revised plan that adheres to CLAUDE.md requirements**:

## REVISED PLAN - THREE PRIORITIES ONLY

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

## Excluded (Per CLAUDE.md Constraint):
- ~~Fee Flow Verification~~ (will be covered in Priority #3)
- ~~Security Vulnerability Mitigation~~ (will be covered in Priority #1)

This revision removes the unauthorized tasks 4-5 and focuses exclusively on the three established priorities, maintaining detailed task breakdown while respecting the locked sprint requirements.