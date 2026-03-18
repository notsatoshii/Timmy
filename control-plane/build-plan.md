### LEVER Protocol — Priority Tasks for Investor Demo

Based on QA score 60/100 with critical visual issues blocking investor credibility:

### 1. Fix Zero-Value Display Bug [CRITICAL] [FRONTEND]
- [ ] 1. Debug why frontend shows $0 TVL/APY when contracts report $60.5M TVL - likely decimal conversion or data fetching issue in dashboard components

### 2. Fix Positions Tab Navigation [CRITICAL] [FRONTEND] 
- [ ] 2. Investigate routing issue where Positions tab shows trading interface instead of positions table - verify React Router configuration and component mapping

### 3. Verify MarketDetail Tab Functionality [CRITICAL] [FRONTEND]
- [ ] 3. Complete verification of MarketDetail tab per known issues - ensure it renders without errors and shows proper market data/charts

### 4. Fix Volume Calculation Display [HIGH] [FRONTEND]
- [ ] 4. Update 24h Volume to show notional (collateral × leverage) instead of just collateral amounts - modify volume calculation logic

### 5. Validate Demo Data Completeness [MEDIUM] [INTEGRATION]
- [ ] 5. Ensure all 215 positions and trading activity display properly across all tabs to demonstrate protocol functionality for investors

**Focus**: Frontend display bugs are making working protocol appear broken. Contract layer is healthy (all checks pass), but presentation layer failing investor demo requirements.