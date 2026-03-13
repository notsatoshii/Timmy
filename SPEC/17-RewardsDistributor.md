# SPEC: RewardsDistributor

## Purpose
Separate from LeverVault. Receives LP's 50% fee share (via FeeRouter) + unmatched funding (via FundingRateEngine). Maintains a cumulative reward-per-share index. LPs claim yield without burning shares. Tranche-aware — each tranche earns independently based on its snapshot.

## Dependencies
- ILeverVault (read tranches for yield computation)
- USDT token
- FixedPointMath

## Build Priority
Phase 6 — Fee Routing & LP Pool.

## Access Control
- FEE_ROUTER role: depositRewards
- FUNDING_RATE_ENGINE role: receiveUnmatchedFunding
- Any user: claim (for own address)
- LEVER_VAULT role: claim on behalf of user (for compound flow)

## State Variables
```solidity
uint256 private _rewardPerShareCumulative;   // WAD — increases monotonically
uint256 private _totalDistributed;
uint256 private _totalUnmatchedFunding;
uint256 private _totalFeeRewards;
```

## depositRewards(uint256 amount)
```
totalShares = LeverVault.totalSupply()
if totalShares == 0:
  // No LPs — rewards go to protocol treasury? Or accumulate?
  // Design decision: accumulate. Next depositor captures them.
  // Just increase index once there are shares.
  return

indexDelta = amount × WAD / totalShares
_rewardPerShareCumulative += indexDelta
_totalDistributed += amount
_totalFeeRewards += amount

// USDT already transferred by FeeRouter before calling this
emit RewardsDeposited(amount, _rewardPerShareCumulative, block.timestamp)
```

## receiveUnmatchedFunding(bytes32 marketId, uint256 amount)
```
// Same index update logic as depositRewards
totalShares = LeverVault.totalSupply()
if totalShares == 0: return

indexDelta = amount × WAD / totalShares
_rewardPerShareCumulative += indexDelta
_totalDistributed += amount
_totalUnmatchedFunding += amount

emit UnmatchedFundingReceived(marketId, amount, block.timestamp)
```

## claim() → uint256
```
tranches = LeverVault.getTranches(msg.sender)
currentIndex = _rewardPerShareCumulative
totalYield = 0

for each tranche in tranches:
  yield = tranche.shares × (currentIndex - tranche.rewardSnapshot) / WAD
  totalYield += yield

if totalYield == 0: revert NothingToClaim

// Reset all snapshots to current index (via LeverVault callback)
LeverVault.resetTrancheSnapshots(msg.sender, currentIndex)

// Transfer yield
USDT.transfer(msg.sender, totalYield)
emit RewardsClaimed(msg.sender, totalYield, block.timestamp)
return totalYield
```

**Note on architecture:** The claim() function needs to RESET tranche snapshots inside LeverVault. This requires either:
- Option A: RewardsDistributor has a REWARDS_DISTRIBUTOR role on LeverVault that can call resetSnapshots
- Option B: The claim flow goes through LeverVault.claim() which calls RewardsDistributor internally
- **Recommended: Option B** — LeverVault.claim() computes yield, calls RewardsDistributor to release USDT, and resets its own snapshots. RewardsDistributor is a "pool" that LeverVault draws from.

## pendingRewards(address holder) → uint256
```
tranches = LeverVault.getTranches(holder)
currentIndex = _rewardPerShareCumulative
total = 0
for each tranche:
  total += tranche.shares × (currentIndex - tranche.rewardSnapshot) / WAD
return total
```
This is a view function — same as LeverVault.pendingYield(). They should return the same value.

## Edge Cases
- No LPs when fees arrive → index doesn't increase (or accumulate for first depositor — design choice)
- Very small totalSupply → indexDelta could be huge. OK — it's per-share.
- Claim with zero pending → revert
- Claim frequency: no cooldown, no minimum, no utilization gate. Claim anytime.

