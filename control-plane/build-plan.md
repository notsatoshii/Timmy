Based on the build plan and QA report, here are the 3 prioritized tasks for the investor demo:

### 1. Fix Frontend React App Deployment [CRITICAL] [FRONTEND]
- [ ] Investigate why frontend service shows "UP" but renders static HTML shell instead of React app
- [ ] Verify frontend build process and ensure proper index.html/assets generation  
- [ ] Fix web server configuration to serve React app with JavaScript execution
- [ ] Confirm React trading interface loads at localhost:3000 (primary blocker for investor demo)

### 2. Fix Vault Data Display [CRITICAL] [FRONTEND]
- [ ] Debug useVaultMulticall hook returning undefined values causing $NaN share price
- [ ] Resolve 413 RPC errors preventing vault data retrieval 
- [ ] Ensure vault tab displays real TVL and share price instead of $0 TVL
- [ ] Test vault metrics in both demo and connected wallet modes

### 3. Fix Position Values Display [CRITICAL] [FRONTEND]  
- [ ] Debug position PnL calculation showing $0.00 for all position values in demo mode
- [ ] Fix stub positions to display realistic demo data instead of zero values
- [ ] Ensure position equity, collateral, and PnL render correctly 
- [ ] Verify positions tab shows meaningful data for investor demo

**Constraints:**
- ✅ Frontend-only tasks (NO contract redeployments per locked sprint)
- ✅ ExecutionEngine and all contracts are PROTECTED 
- ✅ Exactly 3 critical tasks as specified in build plan
- ✅ Run `bash control-plane/health-check.sh` after each task to verify fixes

**Primary Emergency:** React app deployment failure - investors currently see static HTML instead of trading interface.