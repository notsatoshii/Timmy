### 1. **Fix MarketDetail Error Boundary** [CRITICAL] [FRONTEND]
- [ ] 1. Debug and fix MarketDetail component crashes when users click on market cards
- [ ] 2. Rewrite sanity-check-frontend.sh to test ALL 4 tabs (Trading, Positions, Vault, MarketDetail) with screenshots
- [ ] 3. Ensure error boundary failures cause script to exit with failure status

**Status**: Trading/Vault/Positions tabs fixed. Only MarketDetail remains broken, blocking investor demo.

### 2. **Fix Demo Mode Data Display** [CRITICAL] [FRONTEND] 
- [ ] 1. Fix 24h Volume calculation to show NOTIONAL (collateral × leverage) instead of collateral only
- [ ] 2. Fix MarketDetail OI showing $39B instead of realistic ~$150K (WAD vs USDT decimal conversion bug)
- [ ] 3. Verify all numerical formatting displays properly in demo mode across all tabs

**Status**: Vault tab now shows correct TVL ($60.5M), share price ($1.00), APY (0.2%). Volume/OI display bugs remain.

### 3. **Fix Position Opening via Configuration** [HIGH] [CONFIGURATION]
- [ ] 1. Fix leverage configuration bug causing SpaceX to show 1.8x max instead of 20-30x (decimal format mismatch)
- [ ] 2. Test position opening with 5-15x leverage using test wallet after configuration fix  
- [ ] 3. Fix frontend position opening in demo mode (contracts work via CLI, frontend shows "Position Open Failed")

**Status**: Root cause identified as decimal format mismatch per official plan. Fix through configuration, NOT redeployment.

### 4. **Fix Browser Automation Dependencies** [MEDIUM] [INFRASTRUCTURE]
- [ ] 1. Fix Puppeteer libatk-1.0.so.0 dependency error preventing proper UI verification
- [ ] 2. Restore automated screenshot testing capability for investor demo validation

**Status**: Visual verification failing due to browser automation issues, preventing full QA validation.

### 5. **Verify Complete User Flow** [MEDIUM] [TESTING]
- [ ] 1. Run complete verification protocol after fixes: frontend build → restart service → sanity check
- [ ] 2. Target QA score improvement from current 60 to 80+ via MarketDetail stability and realistic demo data

**Status**: Ready for final verification once Priority 1-3 complete. Current QA score 60, target 80+.