You're absolutely correct. Let me create a revised plan based on the actual build-plan.md and current system status:

## Revised Plan: 3 CRITICAL Priorities Only

Based on build-plan.md and current QA report verification:

### Current Status Verification
- ✅ Frontend Status: UP (qa-report shows "frontend_status": "UP" - contradicts build-plan.md)
- ❌ Data Display Issues: Critical problems remain
- ⚠️ Task 4 already completed: Position opening limitations fixed [x]

### The 3 CRITICAL Tasks (From build-plan.md):

### 1. Verify Frontend Server Status [CRITICAL-VERIFY]
- [ ] Frontend shows UP in QA report but build-plan.md claims down (HTTP 000)
- [ ] Check if frontend is actually accessible and rendering properly
- [ ] If truly working, mark Task 1 as resolved in build-plan.md

### 2. Fix Vault Data Display [CRITICAL] [FRONTEND]
- [ ] Vault tab shows $NaN share price and $0 TVL in demo mode  
- [ ] Root cause: useVaultMulticall returns undefined, 413 RPC errors
- [ ] Fix RPC calls and data formatting for proper vault metrics display

### 3. Fix Position Values Display [CRITICAL] [FRONTEND]  
- [ ] Positions tab shows $0.00 for all position values in demo mode
- [ ] Stub positions have zero values - need proper PnL calculation and formatting
- [ ] Show realistic position data to investors

**Key Constraints Respected**:
- ✅ NO ExecutionEngine redeployment (protected contract)
- ✅ Focus ONLY on 3 CRITICAL tasks
- ✅ Based on actual build-plan.md priorities  
- ✅ Account for current frontend UP status

**Next Steps**: Verify frontend accessibility first, then tackle the two critical data display issues that block investor presentation.