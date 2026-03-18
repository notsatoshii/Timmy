Based on the build plan and QA report analysis, here is the **revised plan** that strictly adheres to the 3 locked sprint priorities:

## REVISED INVESTOR DEMO PLAN

### 1. MarketDetail Tab Implementation & Verification [CRITICAL] [FRONTEND]
- [x] 1. Implement missing MarketDetail tab component in frontend
- [ ] 2. Add MarketDetail tab to manual verification checklist 
- [ ] 3. Run full tab verification with `node scripts/tab-sanity.js`
- [ ] 4. Take screenshots to validate market data displays correctly
- **Status**: Missing from current verification checklist - needs implementation first
- **Demo Impact**: Investors will navigate all tabs during presentation

### 2. Fix 24h Volume to Show Notional Value [CRITICAL] [FRONTEND] 
- [x] 1. Locate volume calculation logic in frontend codebase
- [ ] 2. Update calculation from collateral-only to notional (collateral × leverage)
- [ ] 3. Verify volume metrics align with $60M TVL and 222 active positions
- [ ] 4. Test with current market data to ensure accurate display
- **Status**: Currently shows collateral only, missing leverage multiplier
- **Demo Impact**: Volume is a key KPI investors will scrutinize

### 3. Insurance Fund Growth Investigation [CRITICAL] [CONTRACTS]
- [x] 1. Investigate massive contract value (5.011e24) vs UI display ($10K bootstrap)
- [ ] 2. Determine if this is a display bug, calculation overflow, or data format issue
- [ ] 3. Verify FeeRouter contract properly routes 20% of fees to InsuranceFund
- [ ] 4. Fix the display/calculation discrepancy to show accurate fund value
- **Status**: Contract shows 5.011e24, UI shows $10K - clear calculation/display bug
- **Demo Impact**: Shows protocol fee generation and sustainability model

**Sprint Rules Compliance**: These are the ONLY 3 tasks from the locked sprint priorities. All are marked [CRITICAL]. No additional tasks included.