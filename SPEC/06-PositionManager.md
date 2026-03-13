# SPEC: PositionManager

## Purpose
Pure data store for all position state. Single source of truth. CRUD only — no business logic, no formula computation. Multiple contracts read from this; only ExecutionEngine, LiquidationEngine, and SettlementEngine write.

## Dependencies
- None (data store)

## Build Priority
Phase 1 — Foundation. ExecutionEngine, MarginEngine, BorrowFeeEngine, FundingRateEngine, LiquidationEngine, SettlementEngine all read from this.

## Access Control
- EXECUTION_ENGINE role: createPosition, closePosition, updateCollateral
- LIQUIDATION_ENGINE role: closePosition
- SETTLEMENT_ENGINE role: closePosition
- Any address: all view functions (positions are public data)

## State Variables
```solidity
mapping(uint256 => Position) private _positions;
mapping(address => uint256[]) private _userPositions;    // positionIds per user
mapping(bytes32 => uint256[]) private _marketPositions;  // positionIds per market
uint256 private _nextPositionId = 1;  // Start at 1, 0 means "not found"
```

## Position Struct
```solidity
struct Position {
    uint256 id;
    address owner;
    bytes32 marketId;
    bool isLong;
    uint256 entryPI;        // WAD
    uint256 entryPrice;     // WAD (execution price, includes impact)
    uint256 positionSize;   // Notional WAD
    uint256 collateral;     // Net collateral after TX fee WAD
    uint256 leverage;       // Effective leverage at open WAD
    uint256 borrowIndex;    // Cumulative borrow index snapshot WAD
    int256 fundingIndex;    // Cumulative funding index snapshot WAD (signed)
    uint256 openTimestamp;
    bool isOpen;
}
```

## Key Functions

### createPosition(...) → uint256 positionId
- Assign _nextPositionId, increment
- Store full Position struct
- Append to _userPositions[owner] and _marketPositions[marketId]
- Emit PositionCreated
- Return positionId

### closePosition(uint256 positionId)
- Require: isOpen == true
- Set isOpen = false
- Do NOT remove from arrays (gas expensive). Filter by isOpen in view functions.
- Emit PositionClosed

### updateCollateral(uint256 positionId, uint256 newCollateral)
- Require: isOpen == true
- Update collateral field
- Emit PositionCollateralUpdated

### getPosition(uint256 positionId) → Position
- Return full struct. Revert if positionId >= _nextPositionId.

### getUserPositions(address user) → uint256[]
- Return array of positionIds. Caller filters by isOpen if needed.

### getMarketPositions(bytes32 marketId) → uint256[]
- Return array of positionIds for a market.

## Edge Cases
- Position ID 0 never exists (start at 1)
- getPosition for non-existent ID → revert
- closePosition on already closed position → revert
- Large arrays: getUserPositions could be gas-heavy if user has thousands of historical positions. Consider: separate mapping for open positions only, or return a bounded slice.
- updateCollateral to 0 → allowed (position is being fully liquidated, collateral consumed by fees)

