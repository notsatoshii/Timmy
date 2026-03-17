You're absolutely correct. I apologize for the critical violations in my original plan. After reading the actual `build-plan.md`, I now understand the correct scope and constraints.

## **CORRECTED PLAN - Follows Exact Build-Plan.md Priorities**

### **Priority 1: Data Display Consistency [CRITICAL]**
**Issue**: Frontend shows $NaN/$0.00 despite contracts having real data (TVL: 60.5k USDT, 214 positions)

**Frontend-Only Fixes**:
- [ ] Debug `useVaultMulticall.ts` RPC 413 errors causing undefined returns
- [ ] Add fallback logic when multicall fails → direct contract reads  
- [ ] Verify contract addresses in `frontend/user-app/src/config/contracts.ts` match `control-plane/deploy-env.sh`
- [ ] Implement bypass logic if multicall completely fails

### **Priority 2: Remove ALL Fake Data [CRITICAL]**
**Issue**: Fabricated volume values violate CLAUDE.md constraints

**Exact Removals**:
- [ ] `useVolumeCalculation.ts` - remove `BigInt('12800000000')` fake volume
- [ ] `ProtocolStats.tsx` - remove any `DEMO_FALLBACK_VALUES`
- [ ] Show honest "$0.00" when no real trading events exist
- [ ] Fix volume calculation = notional (collateral × leverage), not just collateral

### **Priority 3: QA Integration Success [CRITICAL]**  
**Issue**: `data_checks: []` empty despite working contracts

**Frontend Debug**:
- [ ] Debug why QA agent can't extract displayed values from DOM
- [ ] Add logging to identify exact break point in data extraction
- [ ] Ensure demo mode provides readable fallback values
- [ ] Test QA agent can read displayed TVL/position values

---

**Key Corrections**:
- ❌ Removed ExecutionEngine redeployment (violates protected contracts)
- ✅ Frontend-only solutions (no contract changes)  
- ✅ Exactly 3 priorities from approved build-plan.md
- ✅ Respects current sprint constraints

**Should I proceed with Priority 1: Debugging the RPC 413 errors in `useVaultMulticall.ts`?**