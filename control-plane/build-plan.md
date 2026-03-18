Based on the build plan and current QA report (score 60/100), here are the prioritized tasks for the investor demo sprint:

### 1. Fix Browser Dependencies for Visual Verification [CRITICAL] [INFRASTRUCTURE]
- [ ] Install missing browser dependencies (libatk-bridge, libgtk, libgdk, etc.) to enable screenshot testing and visual verification of the trading interface for investor presentations

### 2. Verify MarketDetail Tab Functionality [CRITICAL] [FRONTEND]
- [ ] Test and fix MarketDetail tab to ensure it loads properly and displays market information correctly - currently listed as unverified blocker for investor demo

### 3. Fix 24h Volume Calculation [CRITICAL] [DATA]
- [ ] Update volume calculation to show notional value (collateral × leverage) instead of just collateral amount - critical data accuracy issue that affects investor confidence

### 4. Oracle Price Feed Stability [HIGH] [BACKEND] 
- [ ] Verify mockkeeper.py oracle service is running consistently to prevent stale price data during live demo scenarios

### 5. Insurance Fund Fee Flow Investigation [MEDIUM] [CONTRACTS]
- [ ] Diagnose why Insurance Fund remains at $10K bootstrap instead of receiving proper 20% fee share through FeeRouter

**Current Status**: Frontend serving (HTTP 200), contracts operational, but visual quality assessment blocked by missing browser dependencies. Score 60/100 requires improvement before investor presentation.