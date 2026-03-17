Perfect! Now I can see the correct approach. Here's the **REVISED PLAN** that follows the existing build-plan.md and respects all CLAUDE.md constraints:

## CORRECTED PLAN - FRONTEND-ONLY FIXES (3 Priorities)

### 1. Fix Frontend Data Display [CRITICAL]
**Root Issue**: Contracts have data (TVL: 60.5k USDT, 214 positions) but frontend shows $NaN/$0.00

**Frontend-Only Approach**:
- [ ] Debug `useVaultMulticall.ts` - RPC 413 errors causing undefined returns
- [ ] Add fallback logic when multicall fails → direct contract reads  
- [ ] Verify contract addresses in `frontend/user-app/src/config/contracts.ts` match `deploy-env.sh`
- [ ] **Bypass multicall entirely if needed** - use individual contract calls for demo

### 2. Remove All Fake Data [CRITICAL] 
**Build Plan Requirement**: No fabricated data allowed per CLAUDE.md

**Exact Removals**:
- [ ] `useVolumeCalculation.ts` - remove `BigInt('12800000000')`  
- [ ] `ProtocolStats.tsx` - remove `DEMO_FALLBACK_VALUES.volume24h`
- [ ] Show honest "$0.00" when no real trading events exist
- [ ] Fix volume calculation = notional (collateral × leverage), not just collateral

### 3. Fix QA Data Checks [CRITICAL]
**Issue**: `data_checks: []` empty in QA report despite working contracts

**Frontend Debug Focus**:
- [ ] Debug why `control-plane/qa-agent.py` can't extract frontend values
- [ ] Add debugging logs to identify exact break point in data flow  
- [ ] Ensure QA can read displayed values from frontend DOM
- [ ] Test that demo mode provides fallback when wallet disconnected

---

**Key Corrections from Original Plan**:
- ❌ Removed ExecutionEngine redeployment (violates protected contracts)
- ✅ Follows existing build-plan.md Phase 1 priorities  
- ✅ Frontend-only solutions (no contract changes)
- ✅ Exactly 3 priorities as mandated
- ✅ Addresses QA report within allowed constraints

**Success Criteria**: 
- Frontend displays real TVL/position data (not $NaN/$0.00)
- QA report shows populated `data_checks[]` array  
- Volume shows honest "$0.00" (no fake numbers)

This plan now correctly aligns with the existing approved priorities and respects all CLAUDE.md constraints. Should I proceed with Priority 1?