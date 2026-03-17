You're absolutely right. I apologize for that critical oversight. Let me revise the plan to comply with the PROTECTED CONTRACTS policy.

## Revised Priority Tasks

### 1. Investigate Leverage Limitation Issue [CRITICAL] [INVESTIGATION]
- [ ] **Log the leverage limitation issue** instead of redeploying protected contracts
- [ ] **Verify current LeverageModel integration** - check if ExecutionEngine properly calls the deployed LeverageModel (0x474E2eE2911544a385eb017369e8516Ad6DcCAbd)
- [ ] **Test existing contracts** to determine if limitation is configuration vs. contract issue
- [ ] **Check leverage calculations** in frontend vs. contract state
- [ ] **Document findings** for potential future resolution without touching protected contracts

### 2. Resolve Vault Tab Data Issues [CRITICAL] [FRONTEND] 
- [ ] Debug useVaultMulticall returning undefined causing $NaN share price and $0 TVL
- [ ] Investigate 413 RPC errors in vault data fetching
- [ ] Implement fallback data handling for demo mode stability
- [ ] Verify share price calculation displays correctly

### 3. Fix Positions Tab Value Display [CRITICAL] [FRONTEND]
- [ ] Debug why all position values show $0.00 in demo mode
- [ ] Verify position value calculations (PnL, equity, collateral)
- [ ] Test with actual positions to ensure proper value display
- [ ] Add error handling for undefined position data

### 4. Verify MarketDetail Tab Functionality [HIGH] [FRONTEND]
- [ ] Test MarketDetail tab navigation and data loading
- [ ] Verify market statistics, charts, and position opening from market view
- [ ] Ensure proper error handling and loading states
- [ ] Test all interactive elements (trade buttons, market info)

### 5. Correct 24h Volume Calculation [MEDIUM] [FRONTEND]
- [ ] Fix volume calculation to show notional value (collateral × leverage) instead of collateral only
- [ ] Update volume aggregation logic in relevant hooks/components
- [ ] Verify volume displays correctly across all market views

**Updated Approach:** Investigate and document the leverage issue without violating protected contract policy, while focusing on frontend data fixes that are immediately actionable.