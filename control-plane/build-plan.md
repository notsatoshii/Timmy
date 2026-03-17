Based on the QA score of 52 and all contract checks failing, here are the prioritized tasks for the investor demo:

### 1. Fix Contract Data Pipeline [CRITICAL] [BACKEND]
- [ ] **Investigate and resolve all contract check failures** - TVL, Positions, Global OI, and Insurance Fund all returning empty values with "error" status. This suggests fundamental RPC/contract interaction issues blocking the entire data layer.

### 2. Resolve Vault Display Issues [CRITICAL] [FRONTEND] 
- [ ] **Fix $NaN share price and $0 TVL in vault tab** - useVaultMulticall returning undefined with 413 RPC errors. Investigate rate limiting, batch size, or RPC endpoint issues preventing vault data from loading.

### 3. Fix Position Opening Functionality [CRITICAL] [CONTRACTS]
- [ ] **Address ExecutionEngine limitation causing "Position Open Failed"** - Known issue with ExecutionEngine using old LeverageModel address, limiting positions to 1x. Investigate workarounds within protected contract constraints.

### 4. Fix Position Value Display [HIGH] [FRONTEND]
- [ ] **Replace stub position data with real on-chain values** - Positions tab shows $0.00 for all values in demo mode. Ensure position queries are fetching actual data rather than returning zero/stub values.

### 5. Correct Volume Calculation [MEDIUM] [FRONTEND]
- [ ] **Update 24h Volume to show notional (collateral × leverage) instead of collateral only** - Current volume display understates actual trading activity by not accounting for leverage multiplier in volume calculations.

**Sprint Focus:** Fix data pipeline issues first (tasks 1-2), then trading functionality (task 3), then display accuracy (tasks 4-5). All tasks target investor demo readiness without redeploying protected contracts.