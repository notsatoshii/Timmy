# Insurance Fund Growth Investigation Report

**Date**: March 18, 2026
**Issue**: Insurance Fund stuck at $5.01M instead of growing from fees
**Status**: 222 active positions generating fees, but fund not receiving new fees
**Impact**: Critical for demo - shows protocol sustainability model

## Executive Summary

**ROOT CAUSE IDENTIFIED**: The Insurance Fund is not growing because it is in Tier 2 mode due to an astronomically high IFR (Insurance Fund Ratio) caused by near-zero TVL in the LeverVault.

## Technical Analysis

### Current State
- **Insurance Fund Balance**: 5,011,000 USDT
- **LeverVault TVL**: ~0.00006 USDT (60,501,227,994,841 wei)
- **LeverVault Shares**: ~0.000061 lvUSDT
- **IFR (Insurance Fund Ratio)**: ~82 billion percent
- **Fee Router Tier**: 2 (Tier 2 = 50/50/0 split)

### Fee Flow Analysis
- **Current Fee Split (Tier 2)**:
  - LP: 50%
  - Protocol: 50%
  - Insurance: 0% ← THIS IS THE PROBLEM
- **Total Fees Generated**: 1 USDT (minimal due to low activity)

### How the IFR System Works
```
IFR = Insurance_Balance / TVL
IFR_Target = 20%

If IFR >= 20%: Tier 2 mode (50/50/0 split)
If IFR < 20%:  Tier 1 mode (50/30/20 split)
```

### Current Calculation
```
IFR = 5,011,000 USDT / 0.00006 USDT = 82+ billion %
```

This astronomical IFR triggers `isFullyFunded() = true`, switching to Tier 2.

## Contract Verification

✅ **FeeRouter Contract**: Correctly implemented
- Proper 50/30/20 split logic for Tier 1
- Proper 50/50/0 split logic for Tier 2
- Correctly routes fees to InsuranceFund when `insuranceShare > 0`

✅ **InsuranceFund Contract**: Correctly implemented
- Proper `isFullyFunded()` logic (IFR >= 20%)
- Correct IFR calculation: `balance / TVL`
- Deposit function works correctly

✅ **Fee Generation**: Working
- Transaction fees: Minimal but present
- Borrow fees: 1 USDT routed
- Position activity: 222 active positions

## The Problem

The protocol is designed to stop sending fees to insurance when the fund is "fully funded" (>=20% of TVL). However, with near-zero TVL:

1. **IFR becomes infinite**: 5M / 0.00006 = astronomical percentage
2. **isFullyFunded() returns true**: IFR >> 20% target
3. **FeeRouter switches to Tier 2**: No fees to insurance
4. **Insurance fund stops growing**: Gets 0% of new fees

## Solution

**Primary Fix**: Increase LeverVault TVL to bring IFR to reasonable levels

### Target Numbers
- **Current IFR**: ~82 billion %
- **Target IFR**: <20% (to switch back to Tier 1)
- **Required TVL**: >25 million USDT to achieve <20% IFR

### Calculation
```
To achieve 20% IFR:
20% = 5,011,000 / TVL
TVL = 5,011,000 / 0.20 = 25,055,000 USDT
```

## Implementation Steps

1. **Add LP Deposits**: Deposit substantial USDT into LeverVault
2. **Monitor IFR**: Check `insuranceFund.getIFR()` until <20%
3. **Verify Tier Switch**: Confirm `feeRouter.getCurrentTier()` returns 1
4. **Resume Fee Flow**: Insurance should receive 20% of new fees

## Demo Impact

**Current State**:
- Shows protocol stuck in "over-funded" mode
- Demonstrates fee routing logic works (50/50/0)
- Shows sustainability model edge case

**After Fix**:
- Shows normal fee routing (50/30/20)
- Demonstrates insurance fund growth
- Proves protocol sustainability model

## Files Created

1. **InvestigateInsuranceFund.s.sol**: Comprehensive diagnostic script
2. **INSURANCE_FUND_INVESTIGATION_REPORT.md**: This report

## Verification Commands

```bash
# Check current state
source control-plane/deploy-env.sh
export PATH="/home/lever/.foundry/bin:$PATH"
RPC_URL="https://sepolia.base.org"

# Check IFR and tier
cast call $INSURANCE_FUND "getIFR()" --rpc-url $RPC_URL
cast call $FEE_ROUTER "getCurrentTier()" --rpc-url $RPC_URL
cast call $INSURANCE_FUND "isFullyFunded()" --rpc-url $RPC_URL

# Check TVL
cast call $LEVER_VAULT "totalAssets()" --rpc-url $RPC_URL
```

## Conclusion

The FeeRouter contract is working correctly. The issue is systemic - the near-zero TVL creates an edge case where the insurance fund appears "over-funded" relative to vault assets, triggering the protocol's designed behavior to stop insurance funding when IFR >= 20%.

This is actually correct protocol behavior, but requires LP deposits to normalize the IFR ratio and resume insurance fee flow.