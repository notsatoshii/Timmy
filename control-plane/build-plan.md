Based on the QA report and known issues, here are the prioritized tasks for LEVER Protocol:

### 1. **Frontend Interface Verification [CRITICAL] [DEMO]**
- [ ] Test actual frontend at localhost:3000 in browser (QA shows only HTML shell visible via curl)
- [ ] Verify all investor-facing features render and function properly
- [ ] Validate trading interface loads with real market data and positions display correctly
- [ ] Confirm responsive design and interactive elements work across device sizes

### 2. **MarketDetail Tab Implementation [CRITICAL] [DEMO]**
- [ ] Complete MarketDetail tab verification and testing
- [ ] Ensure market-specific data displays correctly for investor evaluation
- [ ] Test navigation and data accuracy within market detail views

### 3. **24h Volume Display Fix [CRITICAL] [DATA]**
- [ ] Fix 24h Volume to show notional value (collateral × leverage) instead of collateral only
- [ ] Verify volume calculations align with investor expectations for trading metrics
- [ ] Test across different markets and time periods

### 4. **Data Freshness & Oracle Health [HIGH] [INFRASTRUCTURE]**
- [ ] Verify oracle keeper (mockkeeper.py) is running and updating prices
- [ ] Check price staleness across all markets to prevent investor concerns
- [ ] Ensure real-time data flows properly through the system

### 5. **Investor Demo Polish [MEDIUM] [DEMO]**
- [ ] Address remaining visual inconsistencies and professional appearance
- [ ] Verify all key metrics (TVL, positions, OI) display properly for investor review  
- [ ] Test complete user flow from market browsing to position management

**Current Status**: Score 52/100 - Focus on resolving visual assessment issues and critical demo blockers first.