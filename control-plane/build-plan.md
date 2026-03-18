## REVISED PLAN: LEVER Protocol Investor Demo Sprint

**Status**: LOCKED to exactly 3 priorities as defined in `build-plan.md`

### Priority 1: MarketDetail Tab Verification [CRITICAL] [FRONTEND]
- [ ] Complete manual verification checklist for MarketDetail tab specifically  
- [ ] Run `node scripts/tab-sanity.js` and ensure MarketDetail passes all validation
- [ ] Take screenshots and validate market data displays correctly
- **Demo Impact**: Investors will navigate all tabs during presentation

### Priority 2: Volume Metrics Accuracy [CRITICAL] [FRONTEND]
- [ ] Update 24h volume calculation to show notional (collateral × leverage)
- [ ] Locate volume calculation logic and apply leverage multiplier
- [ ] Verify volumes align with $60M TVL and 222 active positions  
- **Demo Impact**: Volume is a key KPI investors will scrutinize

### Priority 3: Insurance Fund Growth Validation [CRITICAL] [CONTRACTS]
- [ ] Verify FeeRouter properly routes 20% of all fees to InsuranceFund
- [ ] Investigate why fund remains at $10K bootstrap vs growing
- [ ] Document fee flow validation for demo presentation
- **Demo Impact**: Shows protocol sustainability and fee generation

## Sprint Rules
- Work ONLY on these 3 priorities
- Do NOT work on anything else until ALL THREE pass  
- Focus on presentation polish, not debugging
- Current system status: 100/100 QA score, all systems operational

**Transition Criteria**: All 3 priorities must PASS to move to Phase 2 (auto-improve mode)