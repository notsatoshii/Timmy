# SPEC: FeeRouter

## Purpose
Deterministic fee split. Routes all protocol fees (borrow, TX, liquidation, settlement) through 50/30/20 (LP/Protocol/Insurance). Tier 2 when IFR ≥ 20%: 50/50/0. Funding payments do NOT go through this — they route directly between traders and LP.

## Dependencies
- IInsuranceFund (IFR for tier determination, deposit)
- IRewardsDistributor (LP share deposit)
- USDT token
- FixedPointMath

## Build Priority
Phase 6 — Fee Routing & LP Pool.

## Access Control
- BORROW_FEE_ENGINE, EXECUTION_ENGINE, LIQUIDATION_ENGINE, SETTLEMENT_ENGINE roles: routeFees
- EXECUTION_ENGINE role: collectTransactionFee

## Constants
```solidity
uint256 constant LP_SHARE = 5e17;               // 50% — always
uint256 constant PROTOCOL_SHARE_T1 = 3e17;      // 30% (IFR < 20%)
uint256 constant INSURANCE_SHARE_T1 = 2e17;     // 20% (IFR < 20%)
uint256 constant PROTOCOL_SHARE_T2 = 5e17;      // 50% (IFR ≥ 20%)
uint256 constant INSURANCE_SHARE_T2 = 0;         // 0%  (IFR ≥ 20%)
uint256 constant TX_FEE_RATE = 1e15;             // 0.10% (10 bps)
address public immutable protocolTreasury;
```

## routeFees(FeeType feeType, uint256 amount)
```
if amount == 0: revert

tier = InsuranceFund.isFullyFunded() ? 2 : 1

lpShare = amount × LP_SHARE / WAD
if tier == 1:
  protocolShare = amount × PROTOCOL_SHARE_T1 / WAD
  insuranceShare = amount - lpShare - protocolShare    // remainder to avoid rounding loss
else:
  protocolShare = amount - lpShare    // 50% remainder
  insuranceShare = 0

// Transfer
USDT.transfer(RewardsDistributor, lpShare)
RewardsDistributor.depositRewards(lpShare)
USDT.transfer(protocolTreasury, protocolShare)
if insuranceShare > 0:
  USDT.transfer(InsuranceFund, insuranceShare)
  InsuranceFund.deposit(insuranceShare)

emit FeesRouted(feeType, amount, lpShare, protocolShare, insuranceShare, tier)
```

## collectTransactionFee(uint256 notional) → uint256
```
fee = notional × TX_FEE_RATE / WAD
routeFees(FeeType.TRANSACTION, fee)
return fee
```

## Edge Cases
- Rounding: use remainder-based calculation for last share to ensure lpShare + protocolShare + insuranceShare = amount exactly.
- IFR fluctuates around 20%: tier can flip between calls. Each call uses current tier. No hysteresis needed.
- Zero amount → revert.
- protocolTreasury is immutable, set in constructor.

