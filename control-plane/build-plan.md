Based on the QA report showing the Insurance Fund as "5011000000005000000000000 [5.011e24]" and your feedback, here's the **CORRECTED PLAN** focusing exclusively on the 3 locked sprint priorities:

## REVISED PLAN - LOCKED SPRINT (3 PRIORITIES ONLY)

### 1. Fix Insurance Fund Display Bug [CRITICAL] [FRONTEND]
**Issue**: QA report shows Insurance Fund as "5.011e24" instead of ~$10K
- [ ] Debug WAD/USDT decimal conversion causing 5011000000005000000000000 display
- [ ] Fix frontend formatting to show proper "$10,000" instead of scientific notation  
- [ ] Verify Insurance Fund contract actually has ~$10K, not the massive erroneous amount
- **Why critical**: Investor demo cannot show wildly incorrect financial numbers

### 2. Oracle Keeper Stability Check [CRITICAL] [INFRASTRUCTURE]
**Issue**: Ensure mockkeeper.py runs reliably during demo
- [ ] Check if oracle keeper process is running consistently
- [ ] Test price feed stability under demo-like load conditions
- [ ] Verify no stale price warnings during investor presentation
- **Why critical**: Demo depends on live, fresh price data working properly

### 3. Fix Known Issues Documentation [CRITICAL] [DOCUMENTATION]  
**Issue**: Verify documentation accuracy for resolved items
- [ ] Confirm MarketDetail tab actually works (marked RESOLVED in known-issues.md)
- [ ] Confirm 24h Volume calculation works (marked RESOLVED in known-issues.md)
- [ ] Update any remaining inaccuracies in known-issues.md
- **Why critical**: Investors will see documentation mismatches as red flags

**Sprint Discipline**: Work ONLY on these three items. No additional features, monitoring dashboards, APY analysis, or contract changes. Focus purely on demo success.

The Insurance Fund display bug (Priority #1) is the most visually embarrassing issue that would immediately undermine credibility during the investor presentation.