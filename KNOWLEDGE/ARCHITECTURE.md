# KNOWLEDGE/ARCHITECTURE.md — Contract Dependencies & Build Order

## System Data Flow

```
EXTERNAL PREDICTION MARKETS (Polymarket, Kalshi)
        │
        │ P_raw (raw implied probabilities)
        ▼
┌─────────────────────┐
│    OracleAdapter     │ ← Validates, smooths, outputs PI
│  (includes smoothing │    (full pipeline: P_raw → P_smooth = PI)
│   engine internals)  │
└─────────┬───────────┘
          │ PI
          ▼
┌─────────────────────────────────────────────────────────────┐
│                    PI (Probability Index)                     │
│              Single source of truth mark price                │
└──┬──────┬──────┬──────┬──────┬──────┬──────┬───────────────┘
   │      │      │      │      │      │      │
   ▼      ▼      ▼      ▼      ▼      ▼      ▼
 Exec   Margin  Liq   Fund   Borrow  Settl  LevModel
 Engine Engine  Engine Rate   FeeEng  Engine
   │      │      │      │      │      │
   └──────┴──────┴──────┴──────┴──────┘
                    │
                    ▼
          ┌─────────────────┐
          │   FeeRouter      │ ← 50/30/20 split
          └──┬──────┬──────┬┘
             │      │      │
             ▼      ▼      ▼
          LeverVault  Protocol  InsuranceFund
          (50% LP)   Treasury   (20%)
             │        (30%)
             ▼
        RewardsDistributor
        (+ unmatched funding from FundingRateEngine)
```

---

## Contract Dependency Matrix

Each contract lists what it READS FROM (dependencies) and what READS FROM IT (dependents).

| Contract | Reads From | Read By |
|----------|-----------|---------|
| **FixedPointMath** (lib) | nothing | everything |
| **RiskCurves** (lib) | nothing | LeverageModel, OILimits, MarginEngine, BorrowFeeEngine, FundingRateEngine, ExecutionEngine |
| **ProbabilityIndex** (lib) | nothing | OracleAdapter, MarginEngine |
| **OracleAdapter** | external oracles, MarketRegistry (τ, is_live) | all PI consumers (MarginEngine, ExecutionEngine, etc.) |
| **MarketRegistry** | nothing (admin-managed) | OracleAdapter, LeverageModel, OILimits, ExecutionEngine, BorrowFeeEngine, FundingRateEngine, SettlementEngine |
| **AccountManager** | nothing | ExecutionEngine, LeverVault |
| **PositionManager** | nothing (data store) | ExecutionEngine, MarginEngine, BorrowFeeEngine, FundingRateEngine, LiquidationEngine, SettlementEngine |
| **LeverageModel** | MarketRegistry, LeverVault (TVL), InsuranceFund (IFR), OILimits (utilization), RiskCurves | ExecutionEngine, MarginEngine |
| **OILimits** | MarketRegistry, LeverVault (TVL), RiskCurves | ExecutionEngine, MarginEngine, LeverageModel (utilization) |
| **ExecutionEngine** | OracleAdapter (PI), OILimits, LeverageModel, RiskCurves, PositionManager, AccountManager, MarginEngine | — (orchestrator) |
| **MarginEngine** | OracleAdapter (PI), RiskCurves, BorrowFeeEngine, FundingRateEngine, LeverageModel, PositionManager | LiquidationEngine, ExecutionEngine |
| **BorrowFeeEngine** | MarketRegistry (τ, is_live), RiskCurves, OILimits (imbalance), PositionManager | MarginEngine (equity calc), FeeRouter |
| **FundingRateEngine** | MarketRegistry, OILimits (OI balances), RiskCurves, PositionManager | MarginEngine (equity calc), RewardsDistributor (unmatched) |
| **FeeRouter** | BorrowFeeEngine, ExecutionEngine (TX fees), LiquidationEngine, SettlementEngine, InsuranceFund (IFR for tier) | LeverVault, RewardsDistributor, InsuranceFund, Protocol Treasury |
| **LeverVault** | AccountManager, FeeRouter | LeverageModel (TVL), OILimits (TVL) |
| **RewardsDistributor** | FeeRouter, FundingRateEngine (unmatched) | LeverVault (claim integration) |
| **InsuranceFund** | FeeRouter | LeverageModel (IFR), LiquidationEngine, SettlementEngine |
| **LiquidationEngine** | MarginEngine (equity, MM), OracleAdapter (PI), InsuranceFund, PositionManager | FeeRouter (liquidation fees) |
| **SettlementEngine** | OracleAdapter (PI_final), MarginEngine, BorrowFeeEngine, FundingRateEngine, InsuranceFund, LeverVault, PositionManager | FeeRouter (settlement fees) |

---

## Build Order (Phases)

### Phase 1: Foundation (no contract dependencies)
1. `FixedPointMath` — Pure math library. Test thoroughly.
2. `RiskCurves` — Pure math library. Depends only on FixedPointMath. Contains R(τ), R_borrow(τ), all parameter mappings.
3. `ProbabilityIndex` — Pure helpers for PI validation/bounds.
4. `MarketRegistry` — Admin-managed. No protocol dependencies. Stores market metadata.
5. `AccountManager` — User accounts. No protocol dependencies.
6. `PositionManager` — Position data store. No business logic. No protocol dependencies.

### Phase 2: Oracle & Price Pipeline
7. `OracleAdapter` — Full pipeline: external interface → validation → smoothing → PI output. Depends on MarketRegistry for τ/is_live.

### Phase 3: Risk & Leverage
8. `LeverageModel` — Depends on RiskCurves, MarketRegistry. Needs TVL/IFR (mock or interface).
9. `OILimits` — Depends on RiskCurves, MarketRegistry. Needs TVL (mock or interface).

### Phase 4: Fee Engines
10. `BorrowFeeEngine` — Depends on MarketRegistry, RiskCurves, OILimits.
11. `FundingRateEngine` — Depends on MarketRegistry, RiskCurves, OILimits.

### Phase 5: Margin & Execution
12. `MarginEngine` — Depends on PI, RiskCurves, LeverageModel, BorrowFeeEngine, FundingRateEngine, PositionManager.
13. `ExecutionEngine` — Orchestrator. Depends on PI, OILimits, LeverageModel, MarginEngine, PositionManager, AccountManager.

### Phase 6: Fee Routing & LP Pool
14. `FeeRouter` — Routes fees from all sources.
15. `InsuranceFund` — Receives from FeeRouter. Read by LeverageModel, LiquidationEngine.
16. `LeverVault` — ERC-4626 + tranche ledger. Complex. Depends on AccountManager, FeeRouter.
17. `RewardsDistributor` — Receives from FeeRouter + unmatched funding.

### Phase 7: Terminal Contracts
18. `LiquidationEngine` — Depends on MarginEngine, PI, InsuranceFund, PositionManager.
19. `SettlementEngine` — Depends on everything. Build last.

---

## USDT Flow Architecture

**Who holds USDT:**

| Contract | What It Holds | Source |
|----------|--------------|--------|
| **LeverVault** | LP deposits (principal). Counterparty to all trader PnL. | LP deposits |
| **AccountManager** | Trader collateral (free + locked). | Trader deposits |
| **RewardsDistributor** | Accumulated LP yield (pending claims). | FeeRouter + unmatched funding |
| **InsuranceFund** | Bad debt buffer. | FeeRouter (20% of fees) |
| **Protocol Treasury** | Protocol revenue. | FeeRouter (30% of fees) |

**USDT flows on key events:**

```
Position Opens:
  Trader → AccountManager (deposit collateral)
  AccountManager locks collateral
  TX fee: AccountManager → FeeRouter → split

Position Closes (trader profits):
  LeverVault → AccountManager (pays PnL to trader account)
  AccountManager releases collateral + credits PnL to trader
  Trader can withdraw from AccountManager

Position Closes (trader loses):
  AccountManager → LeverVault (loss transfers to vault)
  AccountManager releases remaining collateral to trader

Borrow Fee Accrual:
  Logically: trader equity erodes (no USDT moves until close)
  On close: fees deducted from equity, routed via FeeRouter

LP Deposit:
  LP → LeverVault (USDT in, lvUSDT shares out)

LP Withdrawal:
  LeverVault → LP (USDT out, lvUSDT burned)

LP Claim Yield:
  RewardsDistributor → LP (USDT, no shares burned)
```

**Key principle:** USDT moves between contracts only on discrete events (position open/close, deposit/withdrawal, fee routing). There are no continuous USDT transfers — only accounting entries (index-based accrual) that settle on state changes.

---

## NAV Incremental Tracking (Critical for Gas Efficiency)

NAV = Pool_USDT_Balance - Unrealized_Trader_PnL_Liability

Computing unrealized PnL by iterating all positions is O(positions) — unscalable. Instead, track incrementally:

**Per-market running totals (maintained by OILimits or a dedicated tracker):**
```solidity
mapping(bytes32 => uint256) _longNotional;   // total long notional per market
mapping(bytes32 => uint256) _shortNotional;  // total short notional per market
mapping(bytes32 => uint256) _lastPI;         // PI at last NAV update
```

**On every PI update (O(1) per market):**
```
piDelta = int256(newPI) - int256(_lastPI[marketId])
pnlDelta = piDelta × int256(_longNotional[marketId] - _shortNotional[marketId]) / WAD
_netUnrealizedPnL += pnlDelta
_lastPI[marketId] = newPI
```

**On position open/close (O(1)):**
```
// Open: add to running notional
_longNotional[marketId] += positionSize   // or short

// Close: subtract AND adjust for this position's PnL becoming realized
_longNotional[marketId] -= positionSize
// PnL was already in _netUnrealizedPnL from PI updates; now it's realized
// Realized PnL moves USDT between AccountManager and LeverVault
_netUnrealizedPnL -= thisPositionPnL    // remove from unrealized
```

**NAV = LeverVault.balance() - _netUnrealizedPnL** — always O(1).

This is O(active_markets) per oracle update and O(1) per deposit/withdrawal, which is scalable.

---

## Funding Index Architecture

LEVER uses a SINGLE cumulative funding index per market (not two per-side indices). Direction is applied per-position:

```
_fundingIndex[marketId] += fundingRate × Δt   // positive when longs pay

For any position:
  indexDelta = currentIndex - entryIndex
  direction = isLong ? +1 : -1
  accruedFunding = -direction × posSize × indexDelta / WAD
    // Positive = received, negative = paid
```

This pattern (used by GMX, dYdX) is cleaner than dual indices and eliminates sign confusion.

---

## Interface Strategy

Because contracts have circular read dependencies (LeverageModel needs TVL from LeverVault, LeverVault needs LeverageModel for capacity), we use **interfaces**:

- Define `ILeverVault`, `IInsuranceFund`, `IMarketRegistry`, `IPositionManager`, etc.
- Build against interfaces first
- Wire up concrete addresses in deployment script

Every contract constructor takes addresses of its dependencies as parameters. No hardcoded addresses.

---

## PositionManager vs ExecutionEngine (Separation of Concerns)

| Contract | Responsibility |
|----------|---------------|
| **PositionManager** | Pure data store. Creates, reads, updates, deletes position structs. Tracks positions per market/user. No business logic, no formula computation. |
| **ExecutionEngine** | Orchestrator. Computes execution prices, validates margin checks, calls OILimits, calls PositionManager to store/update positions, calls AccountManager to lock/release collateral. Contains the open/close workflow. |

PositionManager is deliberately "dumb" — it stores state and provides getters. This lets multiple contracts (MarginEngine, BorrowFeeEngine, FundingRateEngine, LiquidationEngine, SettlementEngine) read position data without depending on ExecutionEngine.

---

## Market Lifecycle (State Machine)

```
LISTED → ACTIVE → PENDING_RESOLUTION → RESOLVED
                                      → VOIDED
```

| State | What's Allowed |
|-------|---------------|
| LISTED | Market exists. No trading. Waiting for first valid PI. |
| ACTIVE | Full trading. All systems operational. |
| PENDING_RESOLUTION | No new positions. No voluntary closes. Liquidations continue (2× MM). Fees frozen at external timestamp. |
| RESOLVED | PI_final = 0 or 1. Traders claim payouts. No further state changes. |
| VOIDED | All positions unwind at entry price (PnL = 0). Accrued fees NOT refunded. |

---

## Position Lifecycle

```
OPEN → (accruing borrow + funding) → CLOSED (voluntary)
                                    → LIQUIDATED (equity < MM)
                                    → SETTLED (market resolved)
```

### Position Struct (in PositionManager)
```solidity
struct Position {
    uint256 id;
    address owner;
    bytes32 marketId;
    bool isLong;            // true = long (YES), false = short (NO)
    uint256 entryPI;        // PI at open (WAD)
    uint256 entryPrice;     // Execution price at open (WAD)
    uint256 positionSize;   // Notional (WAD)
    uint256 collateral;     // Net collateral after TX fee (WAD)
    uint256 leverage;       // Effective leverage at open (WAD)
    uint256 borrowIndex;    // Snapshot of cumulative borrow index at open (WAD, per-side: long or short)
    int256 fundingIndex;    // Snapshot of single cumulative funding index at open (signed)
    uint256 openTimestamp;
    bool isOpen;
}
```

