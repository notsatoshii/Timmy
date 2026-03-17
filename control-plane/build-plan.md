Perfect! Now I can see the actual priorities. Here's the **CORRECTED PLAN** that follows the existing build-plan.md and respects all CLAUDE.md constraints:

## REVISED PLAN - FRONTEND-ONLY FIXES (Phase 1 Critical)

### 1. Fix Frontend Data Display [CRITICAL - 45min]
**Root Issue**: Contracts have data (TVL: 60.5T, Positions: 214) but frontend shows $NaN/$0.00

**Frontend-Only Fixes**:
- [ ] Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` - RPC 413 errors causing undefined returns
- [ ] Add fallback logic in `VaultTab.tsx` when multicall fails → show direct contract reads  
- [ ] Verify contract addresses in `frontend/user-app/src/config/contracts.ts` match `deploy-env.sh`
- [ ] **BYPASS multicall entirely if needed** - use individual contract calls for demo

### 2. Remove All Fake Data [CRITICAL - 30min] 
**Build Plan Requirement**: No fabricated data allowed per CLAUDE.md

**Exact Removals**:
- [ ] `frontend/user-app/src/hooks/useVolumeCalculation.ts` - remove `BigInt('12800000000')`  
- [ ] `frontend/user-app/src/components/ProtocolStats.tsx` - remove `DEMO_FALLBACK_VALUES.volume24h`
- [ ] Show honest "$0.00" when no real trading events exist
- [ ] Fix volume = notional (collateral × leverage), not just collateral

### 3. Fix QA Data Checks [CRITICAL - 30min]
**Issue**: `data_checks: []` in QA report despite working contracts

**Frontend Debug Focus**:
- [ ] Debug why `control-plane/qa-agent.py` can't extract frontend values
- [ ] Add debugging logs to identify exact break point in data flow  
- [ ] Ensure QA can read displayed values from frontend DOM
- [ ] Test that demo mode provides fallback when wallet disconnected

---

**Key Changes from Original Plan**:
- ❌ Removed ExecutionEngine redeployment (violates protected contracts)
- ✅ Follows existing build-plan.md Phase 1 priorities  
- ✅ Frontend-only solutions (no contract changes)
- ✅ Exactly 3 priorities as specified
- ✅ Addresses QA report within allowed constraints

**Success Criteria**: 
- Frontend displays real TVL/position data (not $NaN/$0.00)
- QA report shows populated `data_checks[]` array  
- Volume shows honest "$0.00" (no fake numbers)

Should I proceed with this corrected plan?