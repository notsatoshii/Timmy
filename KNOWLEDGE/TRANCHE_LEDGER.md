# KNOWLEDGE/TRANCHE_LEDGER.md — Yield-Carrying LP Shares & Withdrawal Queue

## What Makes This Novel

Standard ERC-20 yield-bearing tokens (aTokens, cTokens, yVault shares) treat all shares as identical. A share minted 12 months ago is indistinguishable from one minted 12 seconds ago. The token has no memory of when it was created or how much unclaimed yield sits behind it.

LEVER's lvUSDT uses a **tranche ledger** — each address holds a list of tranches, not just a balance. Each tranche carries its own reward snapshot. Yield identity survives transfers, including passage through AMM pools.

This is a new primitive: **Time-Stratified Fungible Tokens.** Fungible at the ERC-20 interface. Differentiated by time internally.

---

## Architecture: Two Contracts

| Contract | Role |
|----------|------|
| **LeverVault** (ERC-4626) | Holds USDT deposits. Issues lvUSDT shares. Manages NAV (principal ± unrealized trader PnL). Contains the tranche ledger. |
| **RewardsDistributor** | Separate contract. Receives LP's 50% fee share + unmatched funding. LPs claim yield here without burning vault shares. |

**Critical separation:** Fees do NOT inflate share price / NAV. They accumulate in RewardsDistributor and are claimed separately. This prevents the withdrawal timing attack where an LP deposits before a fee event and withdraws after.

---

## Tranche Ledger Data Structure

```solidity
struct Tranche {
    uint128 shares;          // number of shares in this batch
    uint128 rewardSnapshot;  // cumulative reward index when this batch was acquired
}

// Per address: array of tranches, max 10
mapping(address => Tranche[]) private _tranches;
```

### balanceOf (ERC-20 compatible)
```
balanceOf(addr) = Σ tranche.shares for all tranches of addr
```
Looks like a normal ERC-20 to wallets, DEXs, and all existing infrastructure.

### Yield Calculation
```
yield_for_tranche = tranche.shares × (current_reward_index - tranche.rewardSnapshot)
total_pending_yield(addr) = Σ yield_for_tranche for all tranches
```

### Total Economic Value
```
total_value(addr) = balanceOf(addr) × NAV_per_share + total_pending_yield(addr)
```

---

## Transfer Logic — Proportional Split

**The critical design decision.** When transferring shares, take a proportional slice from EVERY tranche. Not FIFO (punishes sender), not LIFO (games the system).

```
fraction = transfer_amount / sender_total_shares

For each sender tranche:
    shares_to_move = tranche.shares × fraction (round down)
    sender tranche.shares -= shares_to_move
    Append to receiver: Tranche(shares_to_move, tranche.rewardSnapshot)
```

**Why proportional works:**
- Receiver inherits a representative cross-section of the sender's yield history
- No information loss — each moved batch keeps its original snapshot
- Survives AMM passage: pool accumulates separate tranches from each depositor, withdrawals take proportional slices from all of them

### Consolidation (Max 10 Tranches)

When a receiver would exceed 10 tranches after a transfer:
```
Merge two oldest tranches:
    merged.shares = a.shares + b.shares
    merged.snapshot = (a.shares × a.snapshot + b.shares × b.snapshot) / (a.shares + b.shares)
```
Precision loss is negligible — a few days difference on months-old tranches.

**Gas cost:** ~200K gas worst case (10 tranches per side) on L1. Negligible on Base L2.

---

## AMM Survival Test

This is the hardest composability test. The tranche ledger passes it:

```
1. Alice deposits 10K tokens (6mo old, $3K yield) into Uniswap pool
   → Pool gets: [Tranche(10K, 6mo_snapshot)]

2. Bob deposits 10K tokens (1 day old, $0.50 yield) into same pool
   → Pool gets: [Tranche(10K, 6mo_snapshot), Tranche(10K, 1day_snapshot)]
   → NOT blended. Two separate entries.

3. Charlie buys 10K tokens (50% of pool)
   → Each tranche gives up 50%
   → Charlie gets: [Tranche(5K, 6mo_snapshot), Tranche(5K, 1day_snapshot)]
   → Charlie inherited half of Alice's 6-month yield history
```

The yield identity is preserved through the intermediary.

---

## Withdrawal Queue

### Why a Queue (Not Simple Cooldown)

Two-step process prevents the free-option exploit: if NAV were locked at request time, LP could cancel on NAV drop (avoid loss) or execute on NAV rise (capture gain). Computing at execution time means LP bears full NAV risk throughout.

### Flow

```
Step 1: requestWithdrawal(shareAmount)
  → Shares locked (non-transferable, non-sellable)
  → Shares STILL EARN yield during queue
  → Shares STILL exposed to NAV changes
  → Receipt created with: address, shares, timestamp, FIFO position

Step 2: executeWithdrawal(receiptId)    // after 48 hours
  → Check: 48h elapsed?
  → Check: post-withdrawal utilization ≤ 80%?
  → If both pass: burn shares, return USDT at current NAV
  → Accumulated yield on those tranches included in payout
```

### Key Rules

| Rule | Detail |
|------|--------|
| NAV timing | Computed at EXECUTION, not request |
| Cancellation | Allowed, but triggers 24h cooldown before new request |
| Queue order | Strict FIFO. No queue-jumping even if smaller withdrawals fit. |
| Partial withdrawals | Supported. Non-queued shares stay fully active. |
| Queued shares | Cannot be transferred. Still earn yield. Still bear NAV risk. |
| Utilization gate | Post-withdrawal utilization must stay ≤ 80%. If blocked, LP retries later. |

---

## What This Enables (Beyond LEVER)

| Application | How Tranches Help |
|-------------|-------------------|
| **Self-repaying loans** | CDP accepts lvUSDT. Collateral value = shares × NAV + pending_yield. Yield accumulates passively, can auto-repay debt. |
| **Yield stripping** | Separate "yield rights" (pending_yield) from "principal rights" (NAV claim). Trade them independently. |
| **Age-weighted governance** | Governance weight = Σ(tranche.shares × age(tranche)). Rewards commitment without lockups. |
| **On-chain credit scoring** | Tranche ages prove long-term capital commitment. Expensive to fake (requires months of real capital at risk). |
| **Sybil-resistant airdrops** | Weight by token-days: Σ(tranche.shares × days_held). Can't game with last-minute wallet splits. |
| **Premium for seasoned shares** | OTC/DEX market where aged lvUSDT trades at a premium over fresh. Natural yield curve. |

---

## Implementation Notes for Agents

1. **LeverVault inherits ERC-4626** but overrides `transfer` and `transferFrom` to implement the tranche split logic.
2. **`_beforeTokenTransfer` hook** is where tranche splitting happens.
3. **RewardsDistributor** needs to expose `rewardPerShareCumulative()` for snapshot reads.
4. **`claim()` function** iterates all tranches, computes yield per tranche, resets snapshots to current index.
5. **`compound()` function** claims yield + re-deposits in single tx. Creates a new tranche with fresh snapshot.
6. **`pendingYield(address)` view function** — external protocols need this to value positions.
7. **`getTranches(address)` view function** — returns the full tranche array for a given address.
8. **`weightedAge(address)` view function** — returns weighted average age for governance/scoring use cases.
9. **Rounding:** On proportional split, round shares DOWN per tranche. Dust remains with sender. Accumulate dust into the last tranche.
10. **Zero-share tranches:** After rounding, some tranches may have 0 shares. Clean them up (remove from array) to avoid wasting storage.

