You're absolutely right. I apologize for violating the locked sprint constraints. Let me provide the corrected plan that strictly follows the 3 locked priorities from the build plan:

## CORRECTED INVESTOR DEMO PLAN

### 1. MarketDetail Tab Implementation & Verification [CRITICAL] [FRONTEND]
- [ ] Implement missing MarketDetail tab component in frontend
- [ ] Add MarketDetail tab to manual verification checklist 
- [ ] Run full tab verification with `node scripts/tab-sanity.js`
- [ ] Take screenshots to validate market data displays correctly
- **Demo Impact**: Investors will navigate all tabs during presentation

### 2. Fix 24h Volume to Show Notional Value [CRITICAL] [FRONTEND] 
- [ ] Update calculation from collateral-only to notional (collateral × leverage)
- [ ] Verify volume metrics align with $60M TVL and 222 active positions
- [ ] Test with current market data to ensure accurate display
- **Demo Impact**: Volume is a key KPI investors will scrutinize

### 3. Insurance Fund Growth Investigation [CRITICAL] [CONTRACTS]
- [ ] Investigate massive contract value (5.011e24) vs UI display ($10K bootstrap)
- [ ] Determine if this is a display bug, calculation overflow, or data format issue
- [ ] Verify FeeRouter contract properly routes 20% of fees to InsuranceFund
- [ ] Fix the display/calculation discrepancy to show accurate fund value
- **Demo Impact**: Shows protocol fee generation and sustainability model

**Sprint Rules Compliance**: These are the ONLY 3 tasks from the locked sprint priorities. All marked [CRITICAL]. Task #3 correctly categorized as [CONTRACTS] investigation, not frontend display fix.