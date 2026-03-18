Looking at the QA report, I see a **CRITICAL** issue blocking the investor demo. Here are the prioritized tasks:

### 1. Fix Frontend Application Deployment [CRITICAL] [Frontend]
- [ ] Frontend showing directory listing instead of React app - complete deployment failure
- [ ] Investigate systemd service 'lever-frontend' status and restart if needed
- [ ] Verify React dev server is running on port 3000 with proper SPA routing
- [ ] Test that trading interface loads and core functionality is accessible to investors

### 2. Restore Insurance Fund Flow [HIGH] [Backend] 
- [ ] Insurance Fund stuck at $10K bootstrap - fees not flowing through FeeRouter
- [ ] Debug why protocol fees aren't reaching the Insurance Fund (should be 20% of all fees)
- [ ] Verify FeeRouter configuration and fee distribution paths
- [ ] Test fee flow with actual trades to confirm Insurance Fund growth

### 3. Stabilize Oracle Price Feeds [HIGH] [Infrastructure]
- [ ] Verify mockkeeper.py oracle service is running and updating prices
- [ ] Check if prices are going stale and affecting position valuations
- [ ] Ensure oracle keeper has stable nonce management for continuous operation
- [ ] Monitor price freshness for demo reliability

### 4. Validate LP APY Calculation [MEDIUM] [Analytics]
- [ ] LP APY showing 0.21% - investigate if calculation is accurate
- [ ] Verify if low APY is due to insufficient fee generation or calculation error
- [ ] Ensure APY reflects actual yield distribution to LPs

### 5. Final Demo Verification [MEDIUM] [QA]
- [ ] Run complete investor demo walkthrough once frontend is restored
- [ ] Verify all core flows: deposit, trade, view positions, check vault
- [ ] Take final screenshots to confirm professional presentation quality

**Focus:** Task 1 is a complete blocker - investors cannot see anything. Tasks 2-3 affect demo quality but aren't blocking basic functionality.