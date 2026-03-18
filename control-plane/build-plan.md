Looking at the QA report, I see a **CRITICAL** issue blocking the investor demo: the frontend is showing a directory listing instead of the React application. This needs immediate attention.

### 1. Fix Frontend React App Deployment [CRITICAL] [FRONTEND]
- [ ] 1. Investigate why React app shows directory listing instead of application at localhost:3000
- [ ] 2. Check lever-frontend systemd service status and logs
- [ ] 3. Verify build process completed successfully and index.html exists
- [ ] 4. Ensure nginx/static file serving configuration is correct
- [ ] 5. Restart services and confirm React app loads properly

### 2. Verify Investor Demo Functionality [CRITICAL] [FRONTEND]  
- [ ] 1. Test all core investor demo features: trading interface, portfolio view, market data
- [ ] 2. Verify no error boundaries or crashes on key pages
- [ ] 3. Confirm TVL ($60.5M), positions (238), and other metrics display correctly
- [ ] 4. Take screenshots to document working state
- [ ] 5. Run full user flow test to ensure end-to-end functionality

### 3. Address LP APY and Fee Flow Issues [MEDIUM] [CONTRACTS]
- [ ] 1. Investigate why LP APY is only 0.21% (should increase with higher leverage usage)
- [ ] 2. Check why Insurance Fund is stuck at $10K bootstrap value
- [ ] 3. Verify FeeRouter is properly routing fees to RewardsDistributor and InsuranceFund
- [ ] 4. Monitor if oracle keeper (mockkeeper.py) is running and updating prices

### 4. Final Demo Readiness Check [HIGH] [VERIFICATION]
- [ ] 1. Run complete health check and ensure score >90
- [ ] 2. Verify all investor-facing metrics are realistic and impressive
- [ ] 3. Test demo flow from investor perspective (professional appearance, trust factors)
- [ ] 4. Document any remaining known issues that won't impact demo

The **directory listing issue** is a complete blocker for the investor demo (professional score 1/10). This must be resolved first before any other work.