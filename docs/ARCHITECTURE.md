# LEVER Protocol — Technical Architecture

## Overview

LEVER is a synthetic leveraged perpetuals protocol for prediction markets. Traders take leveraged positions on binary outcomes (elections, sports, tech events) while a unified LP pool backs all trades. The protocol does NOT create its own price discovery — instead, it references external prediction market prices (Polymarket) as its oracle.

**Key Technical Characteristics:**
- **Chain:** Base Sepolia (testnet) → Base (mainnet)
- **Asset:** USDT (6 decimals) with internal WAD (1e18) math
- **Architecture:** 16 contracts + 3 libraries
- **Leverage:** Dynamic, up to 30× (decreases toward resolution)
- **Oracle:** External price feeds with sophisticated smoothing
- **LP Pool:** Unified ERC-4626 vault with tranche-based yield distribution

---

## System Architecture Overview

```mermaid
graph TB
    subgraph "External Sources"
        PM[Polymarket CLOB API]
        GM[Gamma API Backup]
    end

    subgraph "Oracle Layer"
        OA[OracleAdapter]
        OA --> |PI| CORE
    end

    subgraph "Core Protocol"
        MR[MarketRegistry]
        AM[AccountManager]
        PM_MGR[PositionManager]

        subgraph "Risk Management"
            LM[LeverageModel]
            OI[OILimits]
            ME[MarginEngine]
        end

        subgraph "Execution Layer"
            EE[ExecutionEngine]
            LE[LiquidationEngine]
            SE[SettlementEngine]
        end

        subgraph "Fee Engines"
            BF[BorrowFeeEngine]
            FR_ENG[FundingRateEngine]
            FR[FeeRouter]
        end

        subgraph "Liquidity Pool"
            LV[LeverVault]
            RD[RewardsDistributor]
            IF[InsuranceFund]
        end
    end

    PM --> OA
    GM --> OA

    OA --> EE
    OA --> ME
    OA --> LE
    OA --> SE

    MR --> LM
    MR --> OI
    MR --> BF
    MR --> FR_ENG

    EE --> PM_MGR
    EE --> AM
    EE --> ME
    EE --> OI
    EE --> LM

    BF --> FR
    FR_ENG --> FR
    FR --> LV
    FR --> RD
    FR --> IF

    style PM fill:#e1f5fe
    style OA fill:#f3e5f5
    style EE fill:#fff3e0
    style LV fill:#e8f5e8
```

---

## Contract Dependency Graph

### Libraries (Foundation Layer)
```mermaid
graph LR
    FPM[FixedPointMath<br/>WAD math]
    RC[RiskCurves<br/>R(τ) calculations]
    PI[ProbabilityIndex<br/>PI validation]

    FPM --> RC
    FPM --> PI
```

### Core Dependencies
```mermaid
graph TB
    subgraph "Phase 1: Foundation"
        FPM[FixedPointMath]
        RC[RiskCurves]
        PI_LIB[ProbabilityIndex]
        MR[MarketRegistry]
        AM[AccountManager]
        PM[PositionManager]
    end

    subgraph "Phase 2: Oracle"
        OA[OracleAdapter]
    end

    subgraph "Phase 3: Risk & Limits"
        LM[LeverageModel]
        OI[OILimits]
        BF[BorrowFeeEngine]
        FR_ENG[FundingRateEngine]
    end

    subgraph "Phase 4: Execution"
        ME[MarginEngine]
        EE[ExecutionEngine]
        FR[FeeRouter]
        IF[InsuranceFund]
        LV[LeverVault]
        RD[RewardsDistributor]
    end

    subgraph "Phase 5: Terminal"
        LE[LiquidationEngine]
        SE[SettlementEngine]
    end

    MR --> OA
    RC --> LM
    RC --> OI
    RC --> BF
    RC --> FR_ENG
    RC --> ME

    OA --> ME
    OA --> EE
    OA --> LE
    OA --> SE

    LM --> EE
    OI --> EE
    ME --> EE
    ME --> LE

    BF --> FR
    FR_ENG --> FR
    EE --> FR

    FR --> LV
    FR --> RD
    FR --> IF

    AM --> EE
    PM --> EE
    PM --> ME
    PM --> BF
    PM --> FR_ENG
    PM --> LE
    PM --> SE

    IF --> LE
    IF --> SE
    LV --> EE
```

---

## Oracle Flow: Polymarket → On-Chain PI

```mermaid
sequenceDiagram
    participant PM as Polymarket CLOB
    participant KP as Keeper Bot
    participant OA as OracleAdapter
    participant EE as ExecutionEngine
    participant TR as Trader

    Note over PM: Active binary market<br/>with orderbook

    loop Every 30s
        KP->>PM: GET /midpoint/{market_id}
        PM-->>KP: raw_price: 0.6234

        Note over KP: Convert to WAD<br/>6234000000000000000

        KP->>OA: pushPrice(marketId, rawPrice)

        Note over OA: Validation Pipeline
        OA->>OA: 1. Staleness check (<2min)
        OA->>OA: 2. Bounds check (0.01-0.99)
        OA->>OA: 3. Delta limit (max 5% jump)
        OA->>OA: 4. Spread validation
        OA->>OA: 5. Depth validation

        Note over OA: Smoothing Pipeline
        OA->>OA: 6. EMA smoothing (α=0.1)
        OA->>OA: 7. Volatility dampening
        OA->>OA: 8. Time weighting

        OA->>OA: Output: PI = smoothed_price

        Note over OA,EE: PI now available to all<br/>protocol components
    end

    TR->>EE: openPosition(long, 1000 USDT, 5x)
    EE->>OA: getPI(marketId)
    OA-->>EE: Current PI
    Note over EE: Compute execution price<br/>with imbalance impact
    EE->>TR: Position opened
```

---

## Trading Flow: Position Open → Close

```mermaid
sequenceDiagram
    participant T as Trader
    participant AM as AccountManager
    participant EE as ExecutionEngine
    participant OA as OracleAdapter
    participant ME as MarginEngine
    participant PM as PositionManager
    participant LV as LeverVault
    participant FR as FeeRouter

    T->>AM: deposit(2000 USDT)
    Note over AM: Trader has collateral

    T->>EE: openPosition(marketId, long, 1000, 5x)

    EE->>OA: getPI(marketId)
    OA-->>EE: PI = 0.6500

    EE->>ME: validateMargin(1000, 5x)
    ME-->>EE: IM = 200, MM = 150

    Note over EE: Compute execution price<br/>PI + imbalance impact
    EE->>EE: entry_price = 0.6520 (0.3% impact)

    EE->>PM: createPosition(positionData)
    EE->>AM: lockCollateral(trader, 1000)

    Note over EE: TX fee: 10 bps of notional
    EE->>AM: debit(trader, 5)
    EE->>FR: routeFee(5, TX_FEE)

    FR->>LV: transfer(2.5)    # 50% to LP
    FR->>IF: transfer(1)      # 20% to Insurance
    Note over FR: 30% to Protocol Treasury

    Note over T,PM: Position exists, fees accruing

    rect rgb(255, 245, 157)
        Note over T,FR: Time passes... borrow fees accrue
    end

    T->>EE: closePosition(positionId)

    EE->>OA: getPI(marketId)
    OA-->>EE: PI = 0.7200 (price moved up)

    EE->>ME: computeEquity(positionId, currentPI)
    Note over ME: PnL = +5x × (0.72-0.652) × 1000<br/>= +340 USDT profit<br/>- borrow fees - funding
    ME-->>EE: equity = 1320 USDT

    EE->>LV: fundTraderPnL(trader, 340)
    Note over LV: Vault pays trader's profit

    EE->>AM: releaseCollateral(trader, 1320)
    EE->>PM: closePosition(positionId)

    T->>AM: withdraw(1320)
    Note over T: Trader profit: +320 USDT<br/>(minus fees)
```

---

## Liquidation Flow

```mermaid
sequenceDiagram
    participant K as Keeper/Anyone
    participant LE as LiquidationEngine
    participant ME as MarginEngine
    participant OA as OracleAdapter
    participant PM as PositionManager
    participant IF as InsuranceFund
    participant AM as AccountManager
    participant LV as LeverVault

    Note over K: Price moved against<br/>leveraged position

    K->>LE: liquidatePosition(positionId)

    LE->>ME: computeEquity(positionId)
    ME->>OA: getPI(marketId)
    OA-->>ME: Current PI
    ME->>ME: equity = collateral + PnL - fees
    ME-->>LE: equity = 45, MM = 50

    Note over LE: equity < MM → liquidatable

    LE->>OA: getPI(marketId)
    LE->>LE: exitPrice = PI (no impact for liquidations)

    LE->>AM: debitPnL(trader, loss_amount)
    Note over AM: If insufficient balance,<br/>returns bad debt amount

    alt No bad debt
        LE->>LV: transfer(remaining_collateral)
        LE->>AM: releaseCollateral(trader, 0)
    else Bad debt exists
        LE->>IF: absorbBadDebt(bad_debt_amount)
        Note over IF: Insurance fund covers loss
    end

    LE->>PM: closePosition(positionId)

    Note over LE: Liquidation fee: 0.5% of notional
    LE->>K: transfer(liquidation_reward)
```

---

## Fee Distribution Architecture

```mermaid
graph TB
    subgraph "Fee Sources"
        TX[Transaction Fees<br/>10 bps on opens/closes]
        BF[Borrow Fees<br/>Continuous on leveraged positions]
        LF[Liquidation Fees<br/>50 bps on liquidated notional]
        SF[Settlement Fees<br/>20 bps on settled positions]
    end

    subgraph "Fee Router (50/30/20 Split)"
        FR[FeeRouter<br/>Deterministic Distribution]
    end

    subgraph "Fee Destinations"
        LP_SHARE[LP Share<br/>50%]
        PROTOCOL[Protocol Treasury<br/>30%]
        INSURANCE[Insurance Fund<br/>20%]
    end

    subgraph "Additional LP Revenue"
        UNMATCHED[Unmatched Funding<br/>From heavy side imbalance]
        COUNTERPARTY[Counterparty PnL<br/>When traders lose]
    end

    TX --> FR
    BF --> FR
    LF --> FR
    SF --> FR

    FR --> LP_SHARE
    FR --> PROTOCOL
    FR --> INSURANCE

    LP_SHARE --> RD[RewardsDistributor]
    UNMATCHED --> RD
    COUNTERPARTY --> LV[LeverVault<br/>NAV increase]

    style RD fill:#e8f5e8
    style LV fill:#e8f5e8
    style INSURANCE fill:#ffebee
    style PROTOCOL fill:#f3e5f5
```

### Fee Tier System

The protocol operates two fee tiers based on Insurance Fund Ratio (IFR):

| Tier | Condition | LP Share | Protocol | Insurance |
|------|-----------|----------|----------|-----------|
| **Tier 1** | IFR < 20% of TVL | 50% | 30% | 20% |
| **Tier 2** | IFR ≥ 20% of TVL | 50% | 50% | 0% |

---

## Vault Mechanics: Tranche Ledger System

LEVER uses a sophisticated tranche-based system that allows LPs to track yield separately from principal:

```mermaid
graph TB
    subgraph "LP Deposit Flow"
        LP[LP deposits 1000 USDT]
        LP --> LV[LeverVault]
        LV --> TRANCHE[Creates Tranche #1<br/>1000 shares @ $1.00 NAV]
    end

    subgraph "Yield Accumulation"
        FEES[Protocol Fees]
        FUNDING[Unmatched Funding]
        PNL[Trader Losses]

        FEES --> RD[RewardsDistributor]
        FUNDING --> RD
        PNL --> LV_NAV[LeverVault NAV ↑]
    end

    subgraph "Yield Distribution"
        RD --> YIELD[Yield allocated to<br/>Tranche #1: 50 USDT]
        YIELD --> CLAIMABLE[LP can claim 50 USDT<br/>without burning shares]
    end

    subgraph "Transfer Behavior"
        TRANSFER[LP sends 500 shares to Alice]
        TRANSFER --> PROP_SPLIT[Proportional split:<br/>500 shares + 25 USDT yield → Alice<br/>500 shares + 25 USDT yield → LP]
        PROP_SPLIT --> ALICE_TRANCHE[Alice gets new tranche]
        PROP_SPLIT --> LP_TRANCHE[LP keeps original tranche]
    end
```

### Key Tranche Properties

1. **Yield Identity Preservation:** Each tranche remembers when it was created and accumulates yield proportionally
2. **Transfer Splitting:** When shares are transferred, both principal and accrued yield split proportionally
3. **Maximum 10 Tranches:** Addresses can hold up to 10 tranches; 11th deposit triggers automatic consolidation
4. **AMM Compatibility:** Yield survives DeFi passage through proportional splitting

---

## Settlement Flow: Market Resolution

```mermaid
sequenceDiagram
    participant O as Oracle/ADMIN
    participant SE as SettlementEngine
    participant OA as OracleAdapter
    participant PM as PositionManager
    participant AM as AccountManager
    participant LV as LeverVault
    participant IF as InsuranceFund
    participant T as Trader

    Note over O: External event resolves<br/>(e.g. election results)

    O->>SE: resolveMarket(marketId, outcome)
    Note over SE: outcome = 0 (NO) or 1 (YES)

    SE->>OA: snapPI(marketId, outcome)
    Note over OA: PI_final = 0.0 or 1.0

    Note over SE: Calculate settlement for all positions

    loop For each position
        SE->>PM: getPosition(positionId)

        alt Position is LONG and outcome = 1 (YES wins)
            SE->>SE: payout = full_notional (1:1)
            SE->>LV: fundTraderPnL(trader, profit)
            SE->>AM: creditPayout(trader, payout)
        else Position is LONG and outcome = 0 (NO wins)
            SE->>SE: payout = 0
            SE->>LV: collectLoss(trader, position_value)
        else Position is SHORT and outcome = 0 (NO wins)
            SE->>SE: payout = full_notional (1:1)
            SE->>LV: fundTraderPnL(trader, profit)
            SE->>AM: creditPayout(trader, payout)
        else Position is SHORT and outcome = 1 (YES wins)
            SE->>SE: payout = 0
            SE->>LV: collectLoss(trader, position_value)
        end

        alt Bad debt exists
            SE->>IF: absorbBadDebt(bad_debt_amount)
        end

        SE->>PM: settlePosition(positionId)
    end

    T->>SE: claimPayout(positionId)
    SE->>AM: transfer(trader, payout_amount)
```

---

## Role & Permission Model

```mermaid
graph TB
    subgraph "Admin Roles"
        ADMIN[ADMIN_ROLE<br/>Contract owner]
        MARKET_MGR[MARKET_MANAGER<br/>Market lifecycle]
        ORACLE_ROLE[ORACLE_ROLE<br/>Price feeds & resolution]
        KEEPER[KEEPER_ROLE<br/>Parameter updates]
    end

    subgraph "Admin Permissions"
        ADMIN --> PAUSE[Pause/unpause contracts]
        ADMIN --> ROLES[Grant/revoke roles]
        ADMIN --> EMERGENCY[Emergency functions]
        ADMIN --> VOID[Void markets]
    end

    subgraph "Market Manager Permissions"
        MARKET_MGR --> CREATE[Create markets]
        MARKET_MGR --> ACTIVATE[Activate markets]
        MARKET_MGR --> LIVE[Set markets live]
        MARKET_MGR --> METADATA[Update market metadata]
    end

    subgraph "Oracle Permissions"
        ORACLE_ROLE --> PRICE[Push price updates]
        ORACLE_ROLE --> RESOLVE[Resolve markets]
        ORACLE_ROLE --> PENDING[Set pending resolution]
        ORACLE_ROLE --> FREEZE[Freeze/unfreeze markets]
    end

    subgraph "Keeper Permissions"
        KEEPER --> PARAMS[Update smoothing parameters]
        KEEPER --> LEVERAGE[Update leverage params]
        KEEPER --> ACCRUAL[Trigger fee accrual]
    end

    style ADMIN fill:#ffebee
    style MARKET_MGR fill:#e8f5e8
    style ORACLE_ROLE fill:#e3f2fd
    style KEEPER fill:#fff3e0
```

### Role Assignment by Contract

| Contract | ADMIN | MARKET_MANAGER | ORACLE | KEEPER |
|----------|-------|----------------|--------|---------|
| **MarketRegistry** | ✓ | Create/activate/live | Resolve/pending | — |
| **OracleAdapter** | ✓ | — | Push prices/freeze | Update params |
| **ExecutionEngine** | ✓ | — | — | — |
| **LeverageModel** | ✓ | — | — | Update params |
| **LeverVault** | ✓ | — | — | — |
| **LiquidationEngine** | ✓ | — | — | Liquidate (anyone) |
| **SettlementEngine** | ✓ | — | Resolve | — |

---

## Market Categories & Examples

LEVER supports diverse binary prediction markets across multiple categories:

| Category | Example Markets | Typical Duration |
|----------|-----------------|------------------|
| **Tech** | SpaceX IPO 2026?, OpenSea Token Launch? | 3-12 months |
| **Geopolitics** | US-Iran Ceasefire?, Taiwan Invasion? | 1-6 months |
| **Sports** | FIFA World Cup Winner: Spain? | Event-specific |
| **Macro** | Fed Rate Below 4%?, Inflation Above 3%? | Quarterly/Annual |
| **Stocks** | AAPL Above $250?, TSLA Below $100? | Monthly/Quarterly |
| **Crypto** | BTC Above $100k?, ETH Merge 2.0? | Event-specific |
| **Forex** | EUR/USD Above 1.10?, Argentina 1500 ARS/USD? | Monthly |
| **Speculative** | Nothing Ever Happens 2026? | Annual memes |

Each market includes:
- **Resolution Time:** Fixed timestamp for outcome determination
- **Category:** Used for allocation weights and risk adjustments
- **Polymarket Reference:** Link to external price source
- **Initial Probability:** Starting PI value for trading

---

## Risk Management Framework

```mermaid
graph TB
    subgraph "Time-to-Resolution (τ) Effects"
        TAU[τ hours remaining]
        TAU --> R_MECH[R(τ) = 1 - e^(-2τ/24)]
        TAU --> R_BORROW[R_borrow(τ) = 1 - e^(-2τ/168)]
    end

    subgraph "Market-Specific Adjustments"
        VOL[Volatility Factor]
        DEPTH[Depth Factor]
        CONC[Concentration Factor]

        VOL --> M_MARKET[M_market = min(vol×depth×conc)]
        DEPTH --> M_MARKET
        CONC --> M_MARKET
    end

    subgraph "Risk-Adjusted Parameters"
        R_MECH --> R_ADJ[R_adjusted = R(τ) × M_market]
        M_MARKET --> R_ADJ

        R_BORROW --> R_BORROW_ADJ[R_borrow_adjusted]
        M_MARKET --> R_BORROW_ADJ
    end

    subgraph "Dynamic Constraints"
        R_ADJ --> LEV_COMP[Leverage Compression]
        R_ADJ --> OI_MULT[OI Cap Multiplier]
        R_ADJ --> MM_MULT[Margin Multiplier]

        R_BORROW_ADJ --> BORROW_MULT[Borrow Rate Multiplier]
    end

    style TAU fill:#fff3e0
    style R_ADJ fill:#ffebee
    style LEV_COMP fill:#e8f5e8
```

### Key Risk Principles

1. **Leverage → 1× at Resolution:** Borrow fees and margin requirements force full collateralization
2. **Live Market Compression:** 70% reduction in effective time when markets go "live"
3. **Concentration Penalties:** Large positions in single markets face increased constraints
4. **Volatility Dampening:** High volatility markets get reduced parameters
5. **Depth Requirements:** Shallow external markets get reduced capacity

---

## Data Structures & Storage

### Position Struct
```solidity
struct Position {
    uint256 id;                // Unique position identifier
    address owner;             // Position owner
    bytes32 marketId;          // Market reference
    bool isLong;               // true = YES, false = NO
    uint256 entryPI;           // PI at position open (WAD)
    uint256 entryPrice;        // Execution price (WAD)
    uint256 positionSize;      // Notional amount (WAD)
    uint256 collateral;        // Net collateral (WAD)
    uint256 leverage;          // Effective leverage (WAD)
    uint256 borrowIndex;       // Borrow fee index snapshot
    int256 fundingIndex;       // Funding rate index snapshot
    uint256 openTimestamp;     // Block timestamp at open
    bool isOpen;               // Position status
}
```

### Market Struct
```solidity
struct Market {
    bytes32 id;                // Market identifier
    string name;               // Human readable name
    string category;           // Category for risk adjustments
    uint256 resolutionTime;    // Scheduled resolution timestamp
    uint256 allocationWeight;  // Weight for OI allocation (WAD)
    MarketState state;         // LISTED/ACTIVE/PENDING/RESOLVED/VOIDED
    uint256 outcome;           // Final outcome (0 or 1)
    bool isLive;               // Live event status
    uint256 liveStartTime;     // When market went live
}
```

### Tranche Struct
```solidity
struct Tranche {
    uint256 shares;            // Share balance in this tranche
    uint256 yieldDebt;         // Yield debt for reward calculation
    uint256 timestamp;         // Creation timestamp
    uint256 navSnapshot;       // NAV at creation
}
```

---

This architecture enables LEVER to provide synthetic leverage on any binary prediction market while maintaining strict risk controls and efficient capital utilization through the unified LP pool model.