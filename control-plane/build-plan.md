You're absolutely right. I need to follow the official build plan exactly. Let me read the actual priorities:

**REVISED PLAN - Following Official Build Plan**

### 1. Fix Insurance Fund Display Bug [CRITICAL] [BACKEND]
- [ ] Insurance Fund shows corrupted value $5.011e24 instead of expected ~$10K bootstrap
- [ ] Check FeeRouter fee distribution and InsuranceFund balance calculations  
- [ ] Verify formatWad/formatUsdt conversion in frontend InsuranceFund display
- [ ] Target: Show correct $10K-$50K range based on actual fee accumulation

### 2. Verify Oracle Keeper Stability [HIGH] [INFRASTRUCTURE]  
- [ ] Check if mockkeeper.py is running and updating prices regularly
- [ ] Verify price feeds are fresh (not stale) across all active markets
- [ ] Test oracle price pipeline from Polymarket → OracleAdapter → PI updates
- [ ] Ensure positions can open/close with current price data

### 3. Investigate Low LP APY Issue [MEDIUM] [BACKEND]
- [ ] LP APY currently 0.21% - trace fee flow from trades → FeeRouter → RewardsDistributor  
- [ ] Check if borrow fees, transaction fees, and funding payments are reaching LP pool
- [ ] Verify RewardsDistributor is accumulating yield properly
- [ ] Target: APY should reflect actual trading activity (228 positions, $11.5M OI)

**Focus**: Following CLAUDE.md directive to "Work ONLY on the three priorities" - these are the top 3 from the official plan. 

Should I start with #1 (Insurance Fund bug) as it's marked CRITICAL?