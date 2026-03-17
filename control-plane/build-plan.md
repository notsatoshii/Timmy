Based on your feedback, you're absolutely correct. I violated the locked sprint constraints. Here's the properly revised plan focusing ONLY on the 3 critical frontend issues:

## REVISED PLAN: Investor Demo Critical Fixes

### Current Status (from QA report):
- **Frontend Service**: UP but serves "Only static HTML shell" 
- **Vision Score**: 60 (low due to frontend deployment issue)
- **Contracts**: ALL functional (TVL, Positions, Global OI, Insurance Fund = "ok")

---

## THE 3 CRITICAL TASKS (Frontend-Only, No Redeployments)

### 1. **Fix Frontend React App Deployment** [CRITICAL BLOCKER]
**Issue**: QA shows service "UP" but renders static HTML shell instead of React app
- [ ] Investigate why React app isn't loading (build/deployment issue)
- [ ] Verify frontend build process generates proper index.html and assets
- [ ] Fix web server configuration to serve React app instead of directory listing
- [ ] Confirm React app loads properly at localhost:3000 with JavaScript execution

### 2. **Fix Vault Data Display** [CRITICAL] 
**Issue**: Vault tab shows $NaN share price and $0 TVL in demo mode
- [ ] Debug useVaultMulticall hook returning undefined values
- [ ] Fix 413 RPC errors preventing vault data retrieval
- [ ] Ensure vault metrics display real TVL and share price values
- [ ] Test vault data display in both demo and connected wallet modes

### 3. **Fix Position Values Display** [CRITICAL]
**Issue**: Positions tab shows $0.00 for all position values in demo mode
- [ ] Debug position PnL calculation and display logic
- [ ] Fix stub positions showing zero values instead of realistic demo data
- [ ] Ensure position equity, collateral, and PnL display correctly
- [ ] Verify position data renders properly in demo mode

---

## Key Constraints: ✅
- ✅ **NO contract redeployments** (ExecutionEngine and all contracts are PROTECTED)
- ✅ **Frontend-only tasks** (all 3 tasks are UI/data display fixes)
- ✅ **Focused scope** (exactly 3 critical tasks, not 5)
- ✅ **Investor demo ready** (addresses the core blockers investors will see)

**Primary Emergency**: React app deployment failure is the biggest blocker - investors see static HTML instead of the trading interface.

**Verification**: Run `bash control-plane/health-check.sh` after each task to confirm fixes.