Based on the known-issues.md file and the CLAUDE.md constraints (no contract redeployments), your revised plan is well-aligned with what's actually fixable for the investor demo. Let me help refine it:

## **CONFIRMED REVISED PLAN - 3 PRIORITIES ONLY**

### **Priority 1: Fix Vault Data Display [CRITICAL]**
- **Issue**: Vault tab shows $NaN share price and $0 TVL in demo mode  
- **Root Cause**: useVaultMulticall returns undefined, 413 RPC errors
- **Action**: 
  - Investigate RPC call failures in useVaultMulticall
  - Implement proper error handling and fallback for vault data
  - Fix share price calculation display
- **Success Criteria**: Vault tab displays valid share price and TVL values

### **Priority 2: Fix Position Values Display [CRITICAL]** 
- **Issue**: Positions tab shows $0.00 for all position values in demo mode
- **Root Cause**: Stub positions with zero calculated values
- **Action**: 
  - Fix position value calculations for existing positions
  - Ensure PnL, equity, and other metrics display realistic values
  - Verify position data fetching pipeline
- **Success Criteria**: Positions tab displays meaningful calculated values for all existing positions

### **Priority 3: Verify MarketDetail Functionality [CRITICAL]**
- **Issue**: MarketDetail tab not yet verified 
- **Action**: 
  - Complete end-to-end verification of MarketDetail pages
  - Test all functionality (price display, charts, position controls)
  - Document any issues discovered
- **Success Criteria**: Market detail pages function properly with any issues documented

**Explicitly DEFERRED** (due to contract deployment restrictions):
- ExecutionEngine/LeverageModel issues (protected contracts - no redeployment allowed)
- Position opening failures (requires ExecutionEngine fix)
- Volume calculation improvements

This plan respects the "no contract redeployment" constraint while addressing the most visible demo blockers. Ready to proceed with Priority 1?