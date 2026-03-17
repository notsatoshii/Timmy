Based on the current system status (health check: 20/20 pass, contracts have real data, but frontend data_checks are empty), here's a **REVISED FOCUSED PLAN** to address the Claude timeout feedback and critical demo blockers:

## REVISED PLAN - CLAUDE TIMEOUT RESPONSE
*Focus: Fix the 3 most critical demo blockers first*

### 🔥 PHASE 1: CRITICAL DEMO BLOCKERS (Complete in Priority Order)

#### 1. Fix Frontend Data Display [CRITICAL - 45min]
**Root Issue**: Contracts have data (TVL: 60.5T, Positions: 214) but frontend shows $NaN/$0.00

**Quick Fix Strategy**:
- [ ] Debug `frontend/user-app/src/hooks/useVaultMulticall.ts` - RPC 413 errors causing undefined returns
- [ ] Add fallback logic in `VaultTab.tsx` when multicall fails → show direct contract reads
- [ ] Verify contract addresses in `frontend/user-app/src/config/contracts.ts` match `deploy-env.sh`
- [ ] **BYPASS multicall entirely if needed** - use individual contract calls for demo

#### 2. Remove All Fake Data [CRITICAL - 30min] 
**Build Plan Requirement**: No fabricated data allowed

**Exact Removals**:
- [ ] `frontend/user-app/src/hooks/useVolumeCalculation.ts` - remove `BigInt('12800000000')`
- [ ] `frontend/user-app/src/components/ProtocolStats.tsx` - remove `DEMO_FALLBACK_VALUES.volume24h`
- [ ] Show honest "$0.00" when no real trading events exist
- [ ] Fix volume = notional (collateral × leverage), not just collateral

#### 3. Fix QA Data Checks [CRITICAL - 30min]
**Issue**: `data_checks: []` in QA report despite working contracts

**Quick Fix**:
- [ ] Debug why `control-plane/qa-agent.py` can't extract frontend values
- [ ] Add debugging logs to identify exact break point in data flow
- [ ] Ensure QA can read displayed values from frontend DOM
- [ ] Test that demo mode provides fallback when wallet disconnected

---

### 🚀 PHASE 2: HIGH PRIORITY (After Phase 1 Complete)

#### 4. Oracle Price Updates [HIGH - 20min]
- [ ] `systemctl status lever-oracle-keeper` - verify service running
- [ ] Check if prices updating every ~30 seconds in OracleAdapter
- [ ] Restart service if stale prices detected

#### 5. Position Opening [HIGH - 45min]
- [ ] Verify ExecutionEngine → LeverageModel address (0x474E...)
- [ ] Test position opening with deployer wallet
- [ ] Document exact error traces if failing

---

### ⚡ PHASE 3: POLISH (If Time Permits)

#### 6. Position Values in Demo Mode [MEDIUM]
#### 7. Market Detail Navigation [MEDIUM] 
#### 8. Insurance Fund Flow [LOW]
#### 9. LP APY Accuracy [LOW]

---

## KEY REVISIONS FOR TIMEOUT RESPONSE:

1. **Shortened timeline**: Focus on 3 critical blockers first (~105 min total)
2. **Bypass strategy**: If multicall keeps failing, use direct contract calls 
3. **Honest data only**: Complete removal of all fake fallbacks
4. **QA-focused**: Fix the empty `data_checks[]` that's blocking validation
5. **Phase gating**: Don't proceed to Phase 2 until Phase 1 passes

**Success Criteria**: 
- Frontend displays real TVL/position data (not $NaN/$0.00)
- QA report shows populated `data_checks[]` array
- Volume shows honest "$0.00" (no fake numbers)

**This plan addresses the timeout by focusing on the smallest set of changes needed for a working demo, then expanding only if the core issues are resolved.**