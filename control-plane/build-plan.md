Based on the QA report showing a score of 60/100 and the visual/trust issues identified, I'll generate priority tasks for the investor demo:

## LEVER Protocol — Priority Tasks (2026-03-18)

### 1. Fix Leverage Claims Consistency [HIGH] [FRONTEND]
- [ ] Update HTML metadata and frontend copy to reflect actual 30x max leverage capability (currently claims 12x)
- [ ] Verify leverage display matches protocol specs in trading interface
- [ ] Test position opening at various leverage levels (5x, 15x, 25x, 30x) to confirm functionality

### 2. Enhance Professional Demo Presentation [HIGH] [FRONTEND]
- [ ] Add protocol version and deployment status indicators
- [ ] Replace placeholder domains (docs.lever.finance, support@lever.finance) with working links or remove
- [ ] Add security/audit status indicators to build investor confidence
- [ ] Include key metrics (TVL, position count) in noscript fallback

### 3. Investigate Insurance Fund Flow [MEDIUM] [BACKEND]
- [ ] Verify FeeRouter is properly routing 20% of fees to Insurance Fund
- [ ] Check why Insurance Fund is stuck at $10K bootstrap instead of growing
- [ ] Test fee flow from trading activity to Insurance Fund accumulation

### 4. Improve LP Yield Display [MEDIUM] [FRONTEND]
- [ ] Investigate why LP APY shows only 0.21% when $68M TVL and active trading should generate higher yields
- [ ] Verify RewardsDistributor is accumulating fees for LP distribution
- [ ] Ensure yield calculations include all fee sources (borrow, funding, transaction fees)

### 5. Oracle Service Stability [LOW] [OPERATIONS]
- [ ] Verify mockkeeper service is running continuously and updating prices every 15s
- [ ] Add monitoring/alerting for oracle price staleness
- [ ] Ensure price feeds remain active during investor demo period

**Current Status**: 264 active positions, $68.5M TVL, $14.6M Global OI - system operational but presentation quality needs improvement for investor confidence.