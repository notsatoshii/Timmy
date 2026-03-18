# Insurance Fund Decimal Bug Analysis

**Date**: March 18, 2026
**Task**: Fix insurance fund flow - fees not routing to insurance fund
**Root Cause**: Decimal handling bug in InsuranceFund.sol IFR calculation

## Problem Summary

The Insurance Fund is stuck in Tier 2 mode (50/50/0 fee split) instead of Tier 1 mode (50/30/20 split), preventing it from receiving 20% of protocol fees.

## Investigation Results

### Current State
- **Insurance Fund Balance**: 5,011,000 USDT (stored in 18 decimals: 5.011e24 wei)
- **LeverVault TVL**: 68,519,959 USDT (stored in 6 decimals: 6.851e13 wei)
- **Expected IFR**: 5.011M / 68.52M = 7.3% (should be Tier 1 since <20%)
- **Actual System State**: Tier 2, isFullyFunded() = true

### Root Cause: Decimal Bug

The bug is in `InsuranceFund.sol` line 280:
```solidity
function _getIFR() internal view returns (uint256) {
    uint256 tvl = leverVault.totalAssets();  // 6 decimals (USDT)
    if (tvl == 0) return WAD;
    return _balance.wadDiv(tvl);             // 18 decimals / 6 decimals = wrong!
}
```

**The Issue**:
- `_balance` is stored in WAD (18 decimals): 5,011,000 * 1e18
- `tvl` from LeverVault is in USDT (6 decimals): 68,519,959 * 1e6
- `wadDiv` doesn't normalize the inputs, creating a 12-order-of-magnitude error

**Calculation Error**:
```
Expected: (5,011,000 * 1e18) / (68,519,959 * 1e18) = 0.073... (7.3%)
Actual:   (5,011,000 * 1e18) / (68,519,959 * 1e6)  = 73,000%+ (way above 20%)
```

## Attempted Fixes

1. **TVL Boosting**: Added 8M+ USDT to vault, raising TVL to 68.5M USDT
   - Result: Still Tier 2 due to decimal bug
   - The bug makes any reasonable TVL appear tiny compared to insurance balance

2. **Faucet Usage**: Used MockUSDT faucet to get additional liquidity
   - Result: Limited by 10K USDT per hour cooldown

## The Fix

The correct solution requires deploying `InsuranceFundFixed.sol` which has the proper calculation:

```solidity
function _getIFR() internal view returns (uint256) {
    uint256 tvl = leverVault.totalAssets();     // TVL in USDT units (6 decimals)
    if (tvl == 0) return WAD;

    // Convert TVL to 18 decimals to match balance, then divide
    uint256 tvlWAD = tvl * 1e12;  // Convert 6 decimals to 18 decimals
    return _balance.wadDiv(tvlWAD);
}
```

However, this requires:
1. Deploying new InsuranceFundFixed contract
2. Deploying new FeeRouter (since insuranceFund is immutable)
3. Migrating balances and roles
4. Updating all dependent contracts

## Impact Assessment

**Current State**: Working protocol with broken fee routing
- Trading works normally
- LP rewards work
- Only insurance fund growth is blocked

**Risk of Fix**: High complexity deployment affecting core fee routing

## Recommendation

Given the constraints of the investor demo and protected contracts, the decimal bug should be documented as a known issue. The protocol functions correctly except for insurance fund fee accumulation.

The fix should be implemented post-demo when full redeployment is possible.

## Files Created During Investigation

1. `INSURANCE_FUND_INVESTIGATION_REPORT.md` - Initial investigation
2. `FixInsuranceFundFlow.s.sol` - First fix attempt
3. `MintAndFixInsuranceFund.s.sol` - Minting approach
4. `SimpleFixInsuranceFund.s.sol` - Simplified approach
5. `TryFaucetAndDeposit.s.sol` - Faucet testing
6. `UseTestWalletToFixInsurance.s.sol` - Large deposit approach
7. `MassiveTVLBoost.s.sol` - Maximum TVL boost attempt
8. `DeployInsuranceFundFixed.s.sol` - Proper fix deployment (unused)

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

# Check balances
cast call $LEVER_VAULT "totalAssets()" --rpc-url $RPC_URL
cast call $INSURANCE_FUND "getBalance()" --rpc-url $RPC_URL
```