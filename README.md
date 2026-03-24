# LEVER Protocol

> Synthetic leveraged perpetuals on binary prediction market outcomes.

LEVER brings leveraged long/short trading to prediction markets. Instead of binary yes/no positions, traders take 2-50x leveraged positions on probability movements, backed by a unified LP vault that earns yield from borrow fees across all markets simultaneously.

---

## Build Status

| Metric | Value |
|--------|-------|
| Overall Progress | **0%** (0/0 tasks) |
| Contracts | **18** implementations + **3** libraries |
| Interfaces | **16** |
| Test Files | **35** files (~1062 test functions) |
| Open Issues | 0 critical, 0 medium, 0 low |
| Resolved Issues | 0 |
| Latest Commit | `47bcdbabf nightly: update known issues based on 2026-03-23 analysis` |
| Branch | `main` |
| Last Updated | 2026-03-23 09:06:49 ICT |

### Phase Progress

```
```

---

## Architecture

**Chain:** Base (Sepolia testnet > mainnet)
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
| InsuranceFundFixed | `contracts/` | Vault & Settlement |
| LeverVault | `contracts/` | Vault & Settlement |
| LeverageModel | `contracts/` | Risk & Execution |
| LeverageModelFixed | `contracts/` | Risk & Execution |
| LiquidationEngine | `contracts/` | Vault & Settlement |
| MarginEngine | `contracts/` | Risk & Execution |
| OILimits | `contracts/` | Risk & Execution |
| RewardsDistributor | `contracts/` | Vault & Settlement |
| SettlementEngine | `contracts/` | Vault & Settlement |
| FixedPointMath | `contracts/libraries/` | Library |
| ProbabilityIndex | `contracts/libraries/` | Library |
| RiskCurves | `contracts/libraries/` | Library |

### Key Design Decisions

- **Oracle:** References external prediction market prices — no proprietary price discovery
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
  contracts/
    core/           OracleAdapter, MarketRegistry, AccountManager, PositionManager
    interfaces/     All contract interfaces (I*.sol)
    libraries/      FixedPointMath, RiskCurves, ProbabilityIndex
    *.sol           ExecutionEngine, LeverVault, fee engines, settlement
  test/
    *.t.sol         Unit tests + math verification
    integration/    Full lifecycle, liquidation, settlement, multi-market
  control-plane/    Build agent (Timmy), dashboard, automation
  CLAUDE.md         Protocol specification
  SPEC/             Per-contract specifications
  foundry.toml
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
  - `MockUSDT.t.sol`
  - `OILimits.t.sol`
  - `OracleAdapter.t.sol`
  - `PositionManager.t.sol`
  - `ProbabilityIndex.t.sol`
  - `RewardsDistributor.t.sol`
  - `RiskCurves.t.sol`
  - `SettlementEngine.t.sol`

  **Integration:**
  - `ClosePositionFlow.t.sol`
  - `FeeFlow.t.sol`
  - `HighLeverageValidation.t.sol`
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
forge test --summary            # Full suite
forge test --match-contract X   # Specific contract
forge test --gas-report         # With gas
forge test --match-path test/integration/*  # Integration only
```

---

## Build Agent (Timmy)

Automated build agent that works autonomously:

- **Every 4 hours:** picks the next task, executes with QA gate, commits and pushes
- **Nightly at 2 AM UTC:** deep maintenance — fixes issues, runs full test suite
- **Model routing:** Opus for spec audits and complex bugs, Sonnet for routine tasks
- **Reports via Telegram** and a **web dashboard** at `http://SERVER_IP:8080`

---

## Development

```bash
git clone git@github.com:notsatoshii/Timmy.git lever-protocol
cd lever-protocol
forge install
forge build
forge test
```

---

## Roadmap

1. ~~Contract implementation~~ Done
2. ~~Math verification~~ Done
3. Spec audit (all contracts) — in progress
4. Integration testing — in progress
5. Base Sepolia deployment
6. Seed bots + monitoring
7. Frontend dashboard
8. Security audit
9. Mainnet launch

---

*Auto-generated by build agent. Last updated: 2026-03-23 09:06:49 ICT*