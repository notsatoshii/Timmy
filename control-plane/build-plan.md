Thank you for the correction. I completely misunderstood the locked sprint priorities. Let me revise the plan to focus **exclusively** on the three locked priorities:

## REVISED PLAN - INVESTOR DEMO SPRINT (LOCKED PRIORITIES ONLY)

### 1. **Fix Insurance Fund Display Bug** [CRITICAL] [FRONTEND/CONTRACTS]
**Issue**: Insurance Fund showing $5.011e24 instead of expected ~$10K bootstrap
- [ ] Investigate frontend display calculation vs contract state
- [ ] Check InsuranceFund contract balance and fee routing
- [ ] Fix display corruption affecting investor confidence
- [ ] Verify fix with screenshots

### 2. **Add Testnet/Mainnet Clarity** [CRITICAL] [FRONTEND]  
**Issue**: Trust score (6/10) - investors need clear testnet environment indication
- [ ] Add prominent "TESTNET ENVIRONMENT" banner across all pages
- [ ] Label/remove hardcoded values (50M TVL, 15.43% APY) 
- [ ] Add professional disclaimers about testnet vs production
- [ ] Include audit status and mainnet roadmap context
- [ ] Verify professional presentation improvements

### 3. **Verify Frontend Stability** [HIGH] [TESTING]
**Issue**: End-to-end validation needed for demo readiness  
- [ ] Test complete user flows (wallet, markets, trading, portfolio)
- [ ] Take browser screenshots for investor presentation
- [ ] Verify no React crashes or loading failures
- [ ] Document stable demo experience

**Goal**: Move from QA score 68 → investor-ready by fixing trust score (6/10) and professional presentation issues.

**Scope**: Work ONLY on these three priorities. No SSL deployment, volume logic, or other features until these pass.