# LEVER Protocol

> Synthetic leveraged perpetuals on binary prediction market outcomes.

LEVER brings leveraged long/short trading to prediction markets. Instead of binary yes/no positions, traders take 2-50x leveraged positions on probability movements, backed by a unified LP vault that earns yield from borrow fees across all markets simultaneously.

---

## Build Status

| Metric | Value |
|--------|-------|
| Overall Progress | **58%** (30/52 tasks) |
| Contracts | **16** implementations + **3** libraries |
| Test Files | **32** files (~1026 test functions) |
| Open Issues | 0 critical, 10 medium, 8 low |
| Resolved Issues | 26 |
| Latest Commit | `e643c46 audit: complete Phase 2 P1 spec audits for all 9 remaining contracts` |
| Branch | `main` |
| Last Updated | 2026-03-15 16:47:04 ICT |

### Phase Progress

```
  Phase 1: Stabilize: █████████████░░░░░░░ 4/6
  Phase 1.5: Math Verifications (COMPLETE): ████████████████████ 6/6
  Phase 2: Spec Audit (all contracts): ████████████████████ 19/19
  Phase 3: Integration Testing: ██░░░░░░░░░░░░░░░░░░ 1/10
  Phase 4: Deployment Prep: ░░░░░░░░░░░░░░░░░░░░ 0/5
  Phase 5: Testnet: ░░░░░░░░░░░░░░░░░░░░ 0/3
  Phase 6: Frontend: ░░░░░░░░░░░░░░░░░░░░ 0/3
```

---

## Architecture

**Chain:** Base (Sepolia testnet → mainnet)
**Solidity:** 0.8.24
**Framework:** Foundry
**Deposit Asset:** USDT / lvUSDT (ERC-4626 vault shares)

### Contract Overview

| Contract | Location | Category |
|----------|----------|----------|
| AccountManager | `contracts/core/` | Core Infrastructure |
| MarketRegistry | `contracts/core/` | Core Infrastructure |
| OracleAdapter | `contracts/core/` | Core Infrastructure |
| PositionManager | `contracts/core/` | Core Infrastructure |
| BorrowFeeEngine | `contracts/` | Fee Engine |
| ExecutionEngine | `contracts/` | Risk & Execution |
| FeeRouter | `contracts/` | Fee Engine |
| FundingRateEngine | `contracts/` | Fee Engine |
| InsuranceFund | `contracts/` | Vault & Settlement |
| LeverVault | `contracts/` | Vault & Settlement |
| LeverageModel | `contracts/` | Risk & Execution |
| LiquidationEngine | `contracts/` | Vault & Settlement |
| MarginEngine | `contracts/` | Risk & Execution |
| OILimits | `contracts/` | Risk & Execution |
| RewardsDistributor | `contracts/` | Vault & Settlement |
| SettlementEngine | `contracts/` | Vault & Settlement |
| FixedPointMath | `contracts/libraries/` | Library |
| ProbabilityIndex | `contracts/libraries/` | Library |
| RiskCurves | `contracts/libraries/` | Library |

### Key Design Decisions

- **Oracle:** References external prediction market prices (e.g., Polymarket) — no proprietary price discovery
- **Vault:** Unified ERC-4626 LeverVault (lvUSDT) backs all markets. LPs earn yield from borrow fees
- **Funding:** Single funding index per market. `accrued = -direction * posSize * (currentIndex - entryIndex)`
- **Liquidation:** 1.0% fee (100 bps). Bad debt socialized to LPs. ADL only at settlement
- **Withdrawal Gate:** 80% utilization threshold with blocking mechanism
- **Equity:** `Collateral + PnL - BorrowFees + Funding` (signed int256)
- **Settlement:** Fees frozen at external resolution timestamp

---

## Project Structure

```
lever-protocol/
├── contracts/
│   ├── core/           # OracleAdapter, MarketRegistry, AccountManager, PositionManager
│   ├── interfaces/     # All contract interfaces (I*.sol)
│   ├── libraries/      # FixedPointMath, RiskCurves, ProbabilityIndex
│   └── *.sol           # ExecutionEngine, LeverVault, fee engines, settlement
├── test/
│   ├── *.t.sol         # Unit tests + math verification
│   └── integration/    # Full lifecycle, liquidation, settlement, multi-market
├── control-plane/      # Build agent (Timmy), dashboard, automation
│   ├── agent-persona.md
│   ├── build-plan.md
│   ├── known-issues.md
│   ├── dashboard.py
│   ├── proactive-worker.sh
│   ├── nightly-cycle.sh
│   └── model-router.sh
├── CLAUDE.md           # Protocol specification
├── SPEC/               # Per-contract specifications
└── foundry.toml
```

---

## Testing

### Test Files

  - `AccountManager.t.sol`
  - `BorrowFeeEngine.t.sol`
  - `ExecutionEngine.t.sol`
  - `FeeRouter.t.sol`
  - `FixedPointMath.t.sol`
  - `FundingRateEngine.t.sol`
  - `InsuranceFund.t.sol`
  - `Integration.t.sol`
  - `LeverVault.t.sol`
  - `LeverageModel.t.sol`
  - `LiquidationEngine.t.sol`
  - `MarginEngine.t.sol`
  - `MarketRegistry.t.sol`
  - `MathVerification.t.sol`
  - `OILimits.t.sol`
  - `OracleAdapter.t.sol`
  - `PositionManager.t.sol`
  - `ProbabilityIndex.t.sol`
  - `RewardsDistributor.t.sol`
  - `RiskCurves.t.sol`
  - `SettlementEngine.t.sol`

  **Integration Tests:**
  - `FeeFlow.t.sol`
  - `InsuranceBadDebt.t.sol`
  - `LiquidationExecution.t.sol`
  - `LiquidationFlow.t.sol`
  - `MultiMarket.t.sol`
  - `NearResolution.t.sol`
  - `PositionLifecycle.t.sol`
  - `SettlementExecution.t.sol`
  - `SettlementFlow.t.sol`
  - `TrancheLedger.t.sol`
  - `WithdrawalQueue.t.sol`


### Running Tests

```bash
# Full test suite
forge test --summary

# Specific contract
forge test --match-contract OracleAdapterTest

# With gas reporting
forge test --gas-report

# Integration tests only
forge test --match-path test/integration/*
```

---

## Build Agent (Timmy)

This project uses an automated build agent that:

- Runs **every 4 hours** (proactive worker) — picks the next task from the build plan, executes it, runs QA, commits and pushes
- Runs **nightly at 2 AM UTC** — deep maintenance cycle: fixes issues, runs full test suite, generates summary
- **Auto-selects models** — Opus for spec audits and complex bugs, Sonnet for routine tasks
- Reports progress via **Telegram** and a **web dashboard**

### Dashboard

Access the live monitoring dashboard:
```
http://SERVER_IP:8080
```

Features: live terminal feed, build plan progress, worker/nightly logs, known issues tracker, git history, model router decisions.

---

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)
- Solidity 0.8.24

### Setup

```bash
git clone git@github.com:notsatoshii/Timmy.git lever-protocol
cd lever-protocol
forge install
forge build
forge test
```

---

## Roadmap

1. ~~Contract implementation~~ ✅
2. ~~Math verification~~ ✅
3. Spec audit (all contracts) — **in progress**
4. Integration testing — **in progress**
5. Base Sepolia deployment
6. Seed bots + monitoring
7. Frontend dashboard
8. Security audit
9. Mainnet launch

---

*This README is auto-generated by the build agent and updated nightly. Last generated: 2026-03-15 16:47:04 ICT*