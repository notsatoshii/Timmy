Based on the QA report (score: 68) and known issues, here are the prioritized tasks for investor demo readiness:

### 1. Fix Server Configuration Issues [HIGH PRIORITY] [INFRASTRUCTURE]
- [ ] Configure proper 404 responses for missing resources while maintaining SPA routing
- [ ] Implement security monitoring to detect vulnerability scanning attempts  
- [ ] Add proper HTTP security headers (HSTS, X-Frame-Options, etc.)
- [ ] Add /health endpoint for proper status monitoring
- **Rationale:** Visual issues showing "misleading HTTP responses" and "vulnerability scanning detected" could damage investor confidence

### 2. Investigate Insurance Fund Display Bug [HIGH PRIORITY] [FRONTEND]  
- [ ] Verify Insurance Fund balance showing $5.011e24 (likely decimal formatting error)
- [ ] Check if this is display issue vs actual contract state
- [ ] Fix formatting to show proper $10K bootstrap value
- **Rationale:** Massive incorrect value ($5 septillion) would confuse investors and suggest system instability

### 3. Validate LP APY Calculation [MEDIUM PRIORITY] [ANALYTICS]
- [ ] Investigate why LP APY is only 0.21% (concerning for investors)
- [ ] Verify fee flow through FeeRouter to RewardsDistributor
- [ ] Confirm relationship between OI levels and LP yield generation
- **Rationale:** Low APY could signal protocol isn't generating sufficient revenue

### 4. Ensure Oracle Stability [MEDIUM PRIORITY] [INFRASTRUCTURE] 
- [ ] Verify mockkeeper.py service is running and stable
- [ ] Monitor price feed updates every 15s as expected
- [ ] Add alerts if price feeds go stale during demo period
- **Rationale:** Price staleness would break core trading functionality during demo

### 5. Pre-Demo System Validation [MEDIUM PRIORITY] [QA]
- [ ] Run complete user flow test with all verification scripts
- [ ] Test position opening across different leverage levels (5x-15x)
- [ ] Verify all tab functionality works smoothly
- [ ] Document demo script/talking points for smooth presentation
- **Rationale:** Ensure no surprises during live investor presentation

**Current Status:** System functional with 265 active positions and $68.5M TVL, but presentation quality issues need immediate attention before investor demo.