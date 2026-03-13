# SPEC: MarketRegistry

## Purpose
Creates and manages markets. Stores metadata: resolution time, is_live, category, allocation weight. The canonical source of τ (time-to-resolution) and is_live for all other contracts. Admin-managed — no automated state transitions except τ decreasing with time.

## Dependencies
- None (admin-managed)

## Build Priority
Phase 1 — Foundation. OracleAdapter, LeverageModel, OILimits, BorrowFeeEngine, FundingRateEngine, ExecutionEngine, SettlementEngine all read from this.

## Access Control
- MARKET_MANAGER role: createMarket, activateMarket, setLive, updateAllocationWeight
- ORACLE role: setPendingResolution, resolveMarket
- ADMIN role: voidMarket

## State Variables
```solidity
mapping(bytes32 => Market) private _markets;
bytes32[] private _activeMarketIds;
```

## Market Struct
```solidity
struct Market {
    bytes32 id;
    string name;
    string externalMarketId;     // Polymarket market ID
    MarketState state;           // LISTED, ACTIVE, PENDING_RESOLUTION, RESOLVED, VOIDED
    MarketCategory category;     // HIGH_LIQUIDITY, MEDIUM_LIQUIDITY, LOW_LIQUIDITY, NEW_UNPROVEN
    uint256 resolutionTime;      // Expected resolution timestamp (seconds)
    uint256 listingTime;         // When created (seconds)
    uint256 allocationWeight;    // OI allocation fraction [0, WAD]
    bool isLive;                 // Underlying event in progress
    uint256 liveStartTime;       // When is_live flipped true
    uint8 outcome;               // 0=NO, 1=YES, 2=VOID (set after resolution)
    uint256 externalResolutionTime;  // Timestamp from source platform (fee accrual anchor)
}
```

## State Machine
```
LISTED → ACTIVE → PENDING_RESOLUTION → RESOLVED
                                      → VOIDED
```
Only valid transitions. Revert on invalid.

## Key Functions

### getTau(bytes32 marketId) → uint256
```
if block.timestamp >= resolutionTime: return 0
tauSeconds = resolutionTime - block.timestamp
tauHours = tauSeconds × WAD / 3600
return tauHours
```
- Returns hours in WAD. All consumers expect WAD-encoded hours.
- Never negative. Returns 0 if past resolution time.

### getTauMax(bytes32 marketId) → uint256
```
tauMaxSeconds = resolutionTime - listingTime
tauMaxHours = tauMaxSeconds × WAD / 3600
return tauMaxHours
```

### isLive(bytes32 marketId) → bool
- Returns the is_live flag

### setLive(bytes32 marketId)
- Requires state == ACTIVE
- Sets isLive = true, liveStartTime = block.timestamp
- Emits MarketLive event
- IRREVERSIBLE — once live, cannot go back to not-live

### resolveMarket(bytes32 marketId, uint8 outcome, uint256 externalTimestamp)
- Requires state == PENDING_RESOLUTION
- outcome must be 0 or 1
- Stores outcome and externalResolutionTime
- Transitions to RESOLVED
- externalTimestamp is when the SOURCE PLATFORM resolved (not block.timestamp)

## Edge Cases
- Market with resolutionTime in the past at creation → reject
- getTau called after resolution → returns 0 (not negative)
- Allocation weights across all markets should sum to ≤ WAD but this is NOT enforced on-chain (admin responsibility). Log a warning event if sum exceeds WAD.
- setLive called when already live → no-op or revert (choose revert — explicit is safer)
- voidMarket from any state except RESOLVED → should work (can void even before activation)

