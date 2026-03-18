Based on the QA report (score: 68) and known issues, here are the prioritized tasks for investor demo readiness:

### 1. Fix Browser Dependencies for Visual Verification [CRITICAL] [VISUAL]
- [ ] Install missing browser dependencies (libatk, libgtk, libgdk, etc.) to enable screenshot testing and visual verification - this is blocking our ability to confirm the UI looks professional for investor presentations

### 2. Verify and Fix MarketDetail Tab [CRITICAL] [FRONTEND] 
- [ ] Test MarketDetail tab functionality to ensure it loads properly and displays market information correctly - currently listed as unverified blocker for investor demo

### 3. Fix 24h Volume Display Calculation [CRITICAL] [FRONTEND]
- [ ] Update volume calculation to show notional value (collateral × leverage) instead of just collateral amount - critical data accuracy issue for investor demo

### 4. Ensure Oracle Keeper Stability [HIGH] [BACKEND]
- [ ] Verify mockkeeper.py oracle service is running and update prices regularly to prevent stale price data during demo

### 5. Diagnose Insurance Fund Fee Flow [MEDIUM] [BACKEND] 
- [ ] Investigate why Insurance Fund remains at $10K bootstrap instead of receiving 20% fee share through FeeRouter - affects displayed protocol metrics

**Current Status**: Frontend serving (200), contracts operational, but visual quality unverified due to missing browser dependencies. Score: 68/100 needs improvement before investor presentation.