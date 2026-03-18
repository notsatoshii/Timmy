Based on the QA report showing a critically low score (28) and frontend completely non-functional, I've identified the root cause: **missing index.html in the build directory**. Here are the prioritized tasks:

### 1. Restore Frontend React Application [CRITICAL] [FRONTEND]
- [x] 1. Copy missing index.html and static directory from build.safe to build directory
- [ ] 2. Restart lever-frontend systemd service to serve the restored React app
- [ ] 3. Verify application loads at localhost:3000 instead of directory listing
- [ ] 4. Test basic navigation and ensure no immediate crashes or error boundaries
- [ ] 5. Take screenshots to confirm professional UI is displaying

### 2. Verify Core Demo Functionality [CRITICAL] [VERIFICATION] 
- [x] 1. Test trading interface - position opening with various leverage levels
- [ ] 2. Verify portfolio/positions tab shows data correctly (not $0.00 values)
- [ ] 3. Confirm market data displays properly with live TVL ($60.5M) and metrics
- [ ] 4. Check vault tab shows correct share price and APY information
- [ ] 5. Run complete health check script and achieve score >90

### 3. Fix Frontend Build Process [HIGH] [FRONTEND]
- [x] 1. Investigate why React build process is not generating index.html
- [ ] 2. Check package.json scripts and build configuration
- [ ] 3. Test `npm run build` manually to identify compilation issues
- [ ] 4. Ensure proper permissions on build directory and files
- [ ] 5. Document build steps to prevent future deployment failures

### 4. Address Low LP APY and Fee Flow [MEDIUM] [CONTRACTS]
- [x] 1. Investigate why LP APY shows only 0.21% (should be higher with $60.5M TVL)
- [ ] 2. Check if Insurance Fund is stuck at $10K bootstrap (should grow with fees)
- [ ] 3. Verify oracle keeper (mockkeeper.py) is running and updating market prices
- [ ] 4. Test that FeeRouter is properly distributing fees to RewardsDistributor

### 5. Final Investor Demo Polish [HIGH] [DEMO]
- [x] 1. Run professional appearance audit - ensure branding and UI quality
- [ ] 2. Test complete investor user journey from landing to position management  
- [ ] 3. Verify all key metrics display impressive, realistic values
- [ ] 4. Document any remaining minor issues that won't impact demo presentation
- [ ] 5. Create demo script highlighting key product features and TVL growth

**The missing index.html is the #1 blocker** - investors currently see a file directory instead of the product, giving a professional score of 1/10. This must be fixed immediately.