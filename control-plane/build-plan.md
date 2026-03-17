Based on the QA report showing frontend DOWN (HTTP 000) and multiple critical data display issues, here are the prioritized tasks for the investor demo:

### 1. Fix Frontend Server [CRITICAL] [INFRA]
- [ ] 1. Frontend is completely down (HTTP 000) - investigate and restore service. Check systemd status, rebuild if needed, verify port 3000 binding. This blocks all investor evaluation.

### 2. Fix Vault Data Display [CRITICAL] [FRONTEND]  
- [ ] 2. Vault tab shows $NaN share price and $0 TVL in demo mode. Root cause: useVaultMulticall returns undefined, 413 RPC errors. Fix RPC calls and data formatting for proper vault metrics display.

### 3. Fix Position Values Display [CRITICAL] [FRONTEND]
- [ ] 3. Positions tab shows $0.00 for all position values in demo mode. Stub positions have zero values - need proper PnL calculation and formatting to show realistic position data to investors.

### 4. Fix Position Opening Limitations [HIGH] [CONTRACTS]
- [x] 4. ExecutionEngine uses old LeverageModel address - positions limited to 1x leverage only. Update ExecutionEngine to use new LeverageModel (0xf649e342...F9EF) to enable proper leveraged trading demo.

### 5. Fix Volume Calculation [MEDIUM] [FRONTEND]
- [ ] 5. 24h Volume shows collateral only instead of notional (collateral × leverage). Update volume calculation to display proper trading volumes for investor metrics.

**Priority Focus**: Tasks 1-3 are blocking all investor evaluation. Task 1 must be completed first as it prevents any frontend access. Tasks 2-3 address immediate data display issues that investors will see. Task 4 enables core functionality demonstration.