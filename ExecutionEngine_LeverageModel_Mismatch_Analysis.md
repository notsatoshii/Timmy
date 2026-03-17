# ExecutionEngine/LeverageModel Mismatch Analysis

**Status**: DOCUMENTED
**Priority**: HIGH
**Type**: CONTRACT ARCHITECTURE ISSUE
**Date**: March 17, 2026

## Executive Summary

The ExecutionEngine contract has an immutable reference to an old LeverageModel contract that has restrictive leverage parameters, preventing positions from exceeding 1x leverage. Since both contracts are marked as PROTECTED and cannot be redeployed, this is a fundamental architecture constraint requiring targeted parameter fixes or post-demo architectural changes.

## Technical Root Cause

### Contract Architecture Issue
The ExecutionEngine contract declares the LeverageModel as:
```solidity
ILeverageModel public immutable leverageModel;
```

Being `immutable`, this address is hardcoded at deployment time and cannot be changed. The ExecutionEngine at `0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D` was deployed with a specific LeverageModel address that cannot be updated without contract redeployment.

### Address Inconsistency Matrix

| Component | Address | Status |
|-----------|---------|---------|
| **ExecutionEngine** | `0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D` | PROTECTED (no redeployment) |
| **ExecutionEngine's hardcoded LeverageModel** | `0x63B98Ec1e559E3b24199eb2115F0a57222e9818c` | OLD, restrictive params |
| **Environment Variable LEVERAGE_MODEL** | `0x474E2eE2911544a385eb017369e8516Ad6DcCAbd` | CURRENT, better params |
| **Alternative LeverageModel in scripts** | `0xA7D95F94dA06E29fc8eFf948Bca3B4AF1d2585ED` | MENTIONED in fix scripts |

### Impact on Position Opening

The ExecutionEngine calls the old LeverageModel's `getEffectiveMaxLeverage(marketId)` function (line 164 in ExecutionEngine.sol) to validate position leverage:

```solidity
uint256 maxLev = leverageModel.getEffectiveMaxLeverage(params.marketId);
if (params.leverage > maxLev) {
    revert ExecutionEngine__LeverageExceedsMax(params.leverage, maxLev);
}
```

If the old LeverageModel returns a maximum leverage of ~1x due to restrictive risk parameters, all position attempts with leverage > 1x will fail.

## Analysis of Available Workarounds

### Option 1: Fix Parameters on Old LeverageModel (RECOMMENDED)

**Target Contract**: `0x63B98Ec1e559E3b24199eb2115F0a57222e9818c`

**Approach**: Update risk parameters on the LeverageModel that ExecutionEngine is actually using.

**Required Actions**:
1. Verify access controls (KEEPER role permissions)
2. Call `setMarketRiskParams()` on the old LeverageModel with less restrictive parameters
3. Set lower volatility baseline and higher depth thresholds for all markets

**Script Available**: `CheckOldLeverageModelInterface.s.sol` and `FixExecutionEngineLeverageModel.s.sol`

**Parameters to Set**:
- `sigmaBaseline`: 0.25e18 (25% volatility - realistic for prediction markets)
- `depthThreshold`: 5e18 (5 USDT - achievable depth)

**Pros**:
- No contract redeployment required
- Respects PROTECTED contracts constraint
- Directly addresses the leverage limitation
- Can be done immediately if permissions allow

**Cons**:
- Requires admin/keeper access to the old LeverageModel
- May affect other components if they reference the same contract

### Option 2: Update Environment Configuration

**Target**: `control-plane/deploy-env.sh`

**Issue**: The environment variable `LEVERAGE_MODEL` points to a different contract than what ExecutionEngine uses, causing confusion in scripts and integrations.

**Solution**: Update environment to match reality or clearly document the discrepancy.

**Pros**:
- Aligns configuration with actual deployment
- Fixes script and integration issues

**Cons**:
- Doesn't solve the fundamental leverage limitation
- May break dependent services expecting the current address

### Option 3: Post-Demo Architectural Fix

**Approach**: Plan for post-demo period when redeployment restrictions are lifted.

**Strategy**:
1. Deploy new ExecutionEngine with updated LeverageModel reference
2. Migrate existing positions or coordinate with users for position closure
3. Update all integrations and configurations

**Pros**:
- Clean architectural solution
- Future-proof approach
- Aligns all components properly

**Cons**:
- Cannot be done during demo period
- Requires coordination for position migration
- Complex deployment process

## Verification Commands

To confirm which LeverageModel the ExecutionEngine is using:
```bash
# Requires forge/cast
cast call 0xc749C6aAe8a5ACBDD924DF7f833Dd3115307a60D "leverageModel()" --rpc-url $RPC_URL
```

To test leverage limits on a specific market:
```bash
# Run the debug script
forge script DebugOldLeverageModel.s.sol --rpc-url $RPC_URL
```

## Recommended Immediate Actions

1. **Verify Old LeverageModel Access**: Run `CheckOldLeverageModelInterface.s.sol` to confirm access permissions
2. **Fix Parameters**: Execute `FixExecutionEngineLeverageModel.s.sol` to update risk parameters
3. **Test Leverage**: Attempt to open a position with leverage > 1x to verify the fix
4. **Document Configuration**: Update CLAUDE.md to reflect the actual contract relationships

## Risk Assessment

| Risk Category | Level | Impact |
|---------------|-------|---------|
| **Demo Impact** | HIGH | Positions limited to 1x leverage severely limits demo |
| **User Experience** | HIGH | Users cannot test leveraged positions |
| **System Stability** | LOW | ExecutionEngine functions correctly, just with restrictions |
| **Future Development** | MEDIUM | Architecture mismatch may cause confusion |

## Success Criteria

- [ ] SpaceX market supports leverage ≥ 5x
- [ ] US-Iran market supports leverage ≥ 5x
- [ ] Test position can be opened with 3x leverage successfully
- [ ] No errors in ExecutionEngine leverage validation
- [ ] Environment documentation updated to reflect actual addresses

## Conclusion

The ExecutionEngine/LeverageModel mismatch is a configuration and parameter issue rather than a fundamental contract bug. The most practical solution is to update the risk parameters on the old LeverageModel that ExecutionEngine is actually using, which should allow for higher leverage positions while respecting the PROTECTED contracts constraint.

The architectural inconsistency should be addressed in a future deployment cycle when redeployment restrictions are lifted, but for the immediate demo needs, parameter adjustment is the recommended approach.