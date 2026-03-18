You're absolutely correct, and I see the build-plan.md file has already been updated with the proper revision. The plan now correctly follows CLAUDE.md constraints with exactly **3 priorities**:

## CURRENT SPRINT - THREE PRIORITIES ONLY

### 1. Fix Server Configuration Issues [HIGH PRIORITY] [INFRASTRUCTURE]
- Configure proper 404 responses for missing resources while maintaining SPA routing
- Implement security headers (HSTS, X-Frame-Options) to address vulnerability scanning concerns  
- Add /health endpoint for proper monitoring during demo

### 2. Investigate Insurance Fund Display Bug [HIGH PRIORITY] [FRONTEND]
- Fix Insurance Fund showing $5.011e24 instead of $10K bootstrap value
- Verify if this is WAD/USDT decimal conversion issue
- Implement proper formatting to display $10,000 for investor confidence

### 3. Validate LP APY Calculation [MEDIUM PRIORITY] [ANALYTICS] 
- Investigate why LP APY is only 0.21% (concerning return for investors)
- Verify fee flow from FeeRouter→RewardsDistributor is working properly
- Document relationship between $14.66M Global OI and LP yield generation

This revision correctly excludes the unauthorized tasks I initially proposed and focuses exclusively on the approved priorities from build-plan.md. Ready to proceed with these three priorities in order.