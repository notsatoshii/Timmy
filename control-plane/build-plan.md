I apologize for the confusion with the question tool. Let me create a revised plan based on the feedback requirements: exactly THREE locked priorities focused only on critical demo blockers.

## REVISED PLAN - LOCKED SPRINT (3 PRIORITIES ONLY)

### 1. Fix Insurance Fund Display Bug [CRITICAL] [FRONTEND]
**Issue**: Insurance Fund shows "5.011e24" instead of ~$10K bootstrap amount
- [ ] Debug WAD/USDT decimal conversion in insurance fund display formatting
- [ ] Verify fix shows proper $10,000 value in dashboard
- **Why critical**: Would embarrass during investor presentation

### 2. Oracle Keeper Stability Check [CRITICAL] [INFRASTRUCTURE] 
**Issue**: Potential stale price issues could cause demo failures
- [ ] Verify oracle keeper (mockkeeper.py) is running consistently
- [ ] Test price feed stability during demo-like conditions
- **Why critical**: Demo depends on live price data working properly

### 3. Fix Known Issues Documentation [CRITICAL] [DOCUMENTATION]
**Issue**: Documentation shows resolved issues as still open
- [ ] Mark MarketDetail tab as RESOLVED (verification shows it's working)
- [ ] Mark 24h Volume calculation as RESOLVED (recent commits fixed it)
- [ ] Update known-issues.md to reflect current state
- **Why critical**: Investors will review documentation and see false negatives

**Sprint Discipline**: Work ONLY on these three items. No additional features, no contract redeployment, no address changes. Focus purely on demo success.

Is this the correct approach for the locked sprint?