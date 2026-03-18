Looking at the QA report with a score of 60 and several critical visual issues, I'll prioritize the most impactful fixes for the investor demo.

### 1. Fix Fee Router System Failure [CRITICAL] [BACKEND]
- [ ] 1. Investigate and resolve the fee router component failure that's preventing proper fee distribution (50/30/20 split to LP/Protocol/Insurance)

### 2. Correct Insurance Fund Display Corruption [CRITICAL] [FRONTEND] 
- [ ] 2. Fix Insurance Fund display showing corrupted value $5.011e24 instead of expected ~$10K range - likely a decimal formatting issue with WAD conversion

### 3. Restore Browser Automation Testing [HIGH] [INFRASTRUCTURE]
- [ ] 3. Install missing Chrome dependencies and fix screenshot system to enable automated testing verification for investor demos

### 4. Investigate Low LP APY Pipeline [MEDIUM] [BACKEND]
- [ ] 4. Debug why LP APY is only 0.21% despite $11.5M OI and 228 positions - fees may not be flowing properly to RewardsDistributor

### 5. Stabilize Oracle Keeper Service [MEDIUM] [INFRASTRUCTURE]
- [ ] 5. Verify mockkeeper.py service stability and price freshness to prevent stale oracle data during investor demonstrations

**Context**: QA score is 60/100 with critical fee router and display issues blocking a professional investor demo. Frontend is UP but core financial components are malfunctioning.