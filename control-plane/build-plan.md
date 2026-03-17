Thank you for the correction. You're absolutely right - I violated the protected contracts policy and exceeded the scope. Let me provide the corrected plan based on your feedback:

## CORRECTED PLAN: Three Critical Priorities Only

### 1. **Investigate Leverage Limitation Issue** [INVESTIGATION]
- [ ] **Document the issue** without touching protected ExecutionEngine (0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D)
- [ ] **Verify integration** between ExecutionEngine and LeverageModel (0x474E2eE2911544a385eb017369e8516Ad6DcCAbd) 
- [ ] **Log findings** for configuration vs contract issue determination
- [ ] **Test current behavior** to understand limitation scope

### 2. **Fix Vault Tab $NaN Display** [FRONTEND]
- [ ] **Debug useVaultMulticall** returning undefined values
- [ ] **Investigate 413 RPC errors** affecting vault data fetching
- [ ] **Implement error handling** for share price display
- [ ] **Verify TVL display** functions correctly

### 3. **Fix Position Values Display** [FRONTEND]  
- [ ] **Debug $0.00 position values** in demo mode
- [ ] **Verify position data flow** from contracts to frontend
- [ ] **Test collateral/PnL calculations** display properly
- [ ] **Add fallback handling** for undefined position data

**Scope:** Work ONLY on these three priorities. Respect all protected contracts. Focus on investigation and frontend fixes only, no contract redeployments.

This aligns with the build plan requirements and protects existing infrastructure while addressing the most critical demo blockers.