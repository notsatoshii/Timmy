Looking at the QA score of 52 and the identified issues, here are the prioritized tasks to improve the investor demo readiness:

### 1. Fix Oracle Price Feed Staleness [CRITICAL] [BACKEND]
- [ ] Investigate why oracle feeds are 373 seconds old (should be <30s)
- [ ] Restart mockkeeper service if needed (`python3 scripts/mockkeeper.py`)
- [ ] Verify prices.json is updating every 15 seconds as expected
- [ ] Add visible "last updated" timestamp in frontend UI for transparency

### 2. Resolve Health Monitoring Issues [HIGH] [DEVOPS]  
- [ ] Fix "NEEDS ATTENTION" health check status
- [ ] Implement proper API endpoints that return JSON (not HTML)
- [ ] Complete missing puppeteer dependencies for automated testing
- [ ] Verify all health endpoints are responding correctly

### 3. Add Real-Time Data Connection Indicators [HIGH] [FRONTEND]
- [ ] Add visual indicators showing live price feed status
- [ ] Display connection status for oracle feeds in UI
- [ ] Show "last price update" timestamp prominently
- [ ] Add warning indicators if feeds go stale (>60s old)

### 4. Complete Testing Infrastructure Setup [MEDIUM] [DEVOPS]
- [ ] Install missing puppeteer dependencies for screenshot verification
- [ ] Fix screenshot verification system fallback mode
- [ ] Ensure automated testing runs without errors
- [ ] Verify all verification scripts pass cleanly

### 5. Enhance API Architecture [MEDIUM] [BACKEND]
- [ ] Separate API endpoints from React router responses
- [ ] Implement proper REST endpoints with JSON responses  
- [ ] Add API versioning structure
- [ ] Set up automated health monitoring alerts

These tasks focus on the core infrastructure reliability issues that impact investor confidence, with oracle feed reliability being the highest priority for a trading platform demo.