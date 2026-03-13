# SPEC: LeverVault

## Purpose
ERC-4626 vault with tranche ledger for yield-carrying LP shares. Deposits USDT → mints lvUSDT. NAV includes unrealized trader PnL (mark-to-market). Withdrawal via two-step queue (request → 48h → execute at current NAV). Transfers use proportional tranche splitting. This is the most complex contract in the protocol.

See KNOWLEDGE/TRANCHE_LEDGER.md for full design rationale and AMM survival proof.

## Dependencies
- OpenZeppelin ERC-4626, ERC-20
- IRewardsDistributor (for claim integration)
- USDT token
- FixedPointMath

## Build Priority
Phase 6 — Fee Routing & LP Pool. Complex — allocate extra build time.

## Access Control
- Any user: deposit, withdraw (via queue), transfer, claim, compound
- EXECUTION_ENGINE role: reporting unrealized PnL for NAV

## Constants
```solidity
uint8 constant MAX_TRANCHES = 10;
uint256 constant WITHDRAWAL_COOLDOWN = 172800;   // 48 hours in seconds
uint256 constant CANCEL_COOLDOWN = 86400;        // 24 hours in seconds
uint256 constant MAX_UTIL_FOR_WITHDRAWAL = 8e17; // 80%
```

## Tranche Ledger

### Data Structure
```solidity
struct Tranche {
    uint128 shares;
    uint128 rewardSnapshot;   // cumulative index from RewardsDistributor
}

mapping(address => Tranche[]) private _tranches;
```

### On Deposit (mint)
```
newShares = computed by ERC-4626 logic
Append: _tranches[depositor].push(Tranche(newShares, RewardsDistributor.rewardPerShareCumulative()))
If _tranches[depositor].length > MAX_TRANCHES: consolidateOldest(depositor)
```

### On Transfer (the critical override)
Override `_update` (or `_beforeTokenTransfer` depending on OZ version):
```
fraction = transferAmount × WAD / balanceOf(from)   // what fraction of total shares

For each tranche in _tranches[from]:
  sharesToMove = tranche.shares × fraction / WAD     // round DOWN
  tranche.shares -= sharesToMove
  if sharesToMove > 0:
    _tranches[to].push(Tranche(sharesToMove, tranche.rewardSnapshot))

// Clean up zero-share tranches from sender
// Consolidate receiver if > MAX_TRANCHES
```

**CRITICAL: Proportional from ALL tranches. NOT FIFO. NOT LIFO.**

### Consolidation
When an address exceeds MAX_TRANCHES:
```
// Merge two oldest tranches (index 0 and 1)
merged.shares = t[0].shares + t[1].shares
merged.snapshot = (t[0].shares × t[0].snapshot + t[1].shares × t[1].snapshot) / merged.shares
// Remove t[0] and t[1], insert merged at position 0
```

### Yield Calculation
```
function pendingYield(address holder) → uint256:
  currentIndex = RewardsDistributor.rewardPerShareCumulative()
  total = 0
  for each tranche in _tranches[holder]:
    total += tranche.shares × (currentIndex - tranche.rewardSnapshot) / WAD
  return total
```

## NAV Calculation
```
NAV = USDT.balanceOf(address(this)) - totalUnrealizedTraderPnL
```
- totalUnrealizedTraderPnL: sum of unrealized PnL across all open positions. If traders are profitable, NAV decreases (vault owes them). If traders are losing, NAV increases.
- Implementation: maintain a running counter updated on every PI update, or compute lazily.
- Does NOT include RewardsDistributor balance (that's separate yield, not NAV).

## Withdrawal Queue

### requestWithdrawal(uint256 shares) → uint256 receiptId
```
require shares > 0
require !isInCooldown(msg.sender)
require balanceOf(msg.sender) - queuedShares(msg.sender) >= shares   // can't queue more than free

// Lock shares (mark as non-transferable)
_queuedShares[msg.sender] += shares
receiptId = _nextReceiptId++
_receipts[receiptId] = WithdrawalReceipt(receiptId, msg.sender, shares, block.timestamp, false, false)
emit WithdrawalRequested(receiptId, msg.sender, shares, block.timestamp)
```

### executeWithdrawal(uint256 receiptId) → uint256 assets
```
receipt = _receipts[receiptId]
require receipt.owner == msg.sender
require !receipt.executed && !receipt.cancelled
require block.timestamp >= receipt.requestTimestamp + WITHDRAWAL_COOLDOWN

// Compute assets at CURRENT NAV (not request-time NAV)
assets = receipt.shares × getNAV() / totalSupply()

// Check utilization after withdrawal
// Global_OI / (TVL - assets) must be ≤ 80%
postTVL = totalAssets() - assets
if postTVL > 0:
  postUtil = globalOI × WAD / postTVL
  require postUtil <= MAX_UTIL_FOR_WITHDRAWAL

// Execute: burn shares, transfer USDT, include yield
yield = computeYieldForShares(msg.sender, receipt.shares)  // yield on queued tranches
totalPayout = assets + yield

_queuedShares[msg.sender] -= receipt.shares
receipt.executed = true
_burn(msg.sender, receipt.shares)
// Remove corresponding tranches proportionally
USDT.transfer(msg.sender, totalPayout)

emit WithdrawalExecuted(receiptId, msg.sender, receipt.shares, totalPayout, block.timestamp)
```

### cancelWithdrawal(uint256 receiptId)
```
receipt = _receipts[receiptId]
require receipt.owner == msg.sender && !receipt.executed && !receipt.cancelled
receipt.cancelled = true
_queuedShares[msg.sender] -= receipt.shares
_cancelCooldownEnd[msg.sender] = block.timestamp + CANCEL_COOLDOWN
emit WithdrawalCancelled(...)
```

## Transfer Override
```
// In _update (ERC-20 transfer hook):
// 1. Check sender has enough non-queued shares
require balanceOf(from) - _queuedShares[from] >= amount

// 2. Do proportional tranche split (described above)

// 3. Call super._update for standard ERC-20 balance tracking
```

## Edge Cases
- Transfer of 100% of shares → all tranches move, sender has empty array
- Transfer when receiver already has 10 tranches → consolidate receiver after receiving
- Deposit immediately followed by withdrawal request → shares exist but yield is minimal (fresh snapshot)
- NAV drops during queue → withdrawer gets less (correct — they bear full risk)
- NAV rises during queue → withdrawer gets more (correct — they bear full risk)
- Utilization at 81% → no withdrawals possible. LP waits for positions to close.
- Multiple pending receipts per user → supported. Each tracks its own shares.
- Compound creates a new tranche → may trigger consolidation if at max

## Testing
- Tranche split: verify proportional math with various fractions
- AMM test: deposit from two users into a mock pool, withdraw from pool, verify yield preserves
- Consolidation: fill to 10 tranches, add one more, verify oldest two merge correctly
- Withdrawal queue: request → wait 48h → execute. Verify NAV at execution, not request.
- Cancel → verify 24h cooldown active
- Utilization gate: mock high OI, verify withdrawal blocked
- Gas benchmarks for transfer with 10 tranches

