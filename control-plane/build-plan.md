Perfect! Now I can see the actual issues. Based on the QA report and the feedback, here's the **CORRECTED PLAN** focusing only on the three locked sprint priorities:

## REVISED PLAN - LOCKED SPRINT (3 PRIORITIES ONLY)

### 1. Fix Insurance Fund Display Bug [CRITICAL] [FRONTEND]
**Issue**: QA report shows Insurance Fund as "5011000000005000000000000 [5.011e24]" instead of ~$10K
- [ ] Debug WAD/USDT decimal conversion in Insurance Fund display formatting
- [ ] Fix frontend to show proper "$10,000" instead of scientific notation
- **Why critical**: Would embarrass during investor presentation showing massive incorrect numbers

### 2. Oracle Keeper Stability Check [CRITICAL] [INFRASTRUCTURE] 
**Issue**: Verify mockkeeper.py is running reliably for demo
- [ ] Check if oracle keeper (mockkeeper.py) is running consistently  
- [ ] Test price feed stability during demo-like conditions
- [ ] Ensure no stale price issues during investor presentation
- **Why critical**: Demo depends on live price data working properly

### 3. Fix Known Issues Documentation [CRITICAL] [DOCUMENTATION]
**Issue**: Ensure documentation accurately reflects current resolved state
- [ ] Verify known-issues.md shows MarketDetail tab as RESOLVED (appears already done)
- [ ] Verify 24h Volume calculation marked as RESOLVED (appears already done)  
- [ ] Update any remaining inaccuracies in known-issues.md
- **Why critical**: Investors will review documentation and see false negatives

**Sprint Discipline**: Work ONLY on these three items. No additional features, no contract redeployment, no address changes. Focus purely on demo success.

This plan correctly focuses on the three critical blockers identified in your feedback, with the Insurance Fund display bug being the most urgent visible issue.