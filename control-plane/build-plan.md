Based on the build plan and current verification status, here are the **3 locked sprint priorities** that must be completed for investor demo readiness:

### 1. MarketDetail Tab Implementation & Verification [CRITICAL] [FRONTEND]
- [ ] 1. Implement missing MarketDetail tab component in frontend
- [ ] 2. Add MarketDetail tab to manual verification checklist 
- [ ] 3. Run full tab verification with `node scripts/tab-sanity.js`
- [ ] 4. Take screenshots to validate market data displays correctly
- **Status**: Missing from current verification checklist - needs implementation first
- **Demo Impact**: Investors will navigate all tabs during presentation

### 2. Fix 24h Volume to Show Notional Value [CRITICAL] [FRONTEND] 
- [ ] 1. Locate volume calculation logic in frontend codebase
- [ ] 2. Update calculation from collateral-only to notional (collateral × leverage)
- [ ] 3. Verify volume metrics align with $60M TVL and 222 active positions
- [ ] 4. Test with current market data to ensure accurate display
- **Status**: Currently shows collateral only, missing leverage multiplier
- **Demo Impact**: Volume is a key KPI investors will scrutinize

### 3. Insurance Fund Growth Investigation [CRITICAL] [CONTRACTS]
- [ ] 1. Verify FeeRouter contract properly routes 20% of fees to InsuranceFund
- [ ] 2. Investigate why fund remains at $10K bootstrap instead of growing
- [ ] 3. Check fee flow from trading activity to insurance fund
- [ ] 4. Document findings for demo presentation on protocol sustainability
- **Status**: Stuck at bootstrap value despite 222 active positions generating fees
- **Demo Impact**: Shows protocol fee generation and sustainability model

**Sprint Rules**: Work ONLY on these 3 priorities. ALL must pass to transition to Phase 2. No additional features or improvements until these are resolved.