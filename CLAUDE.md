# CLAUDE.md — LEVER Protocol Build System

## What Is LEVER
Synthetic leveraged perpetuals on prediction markets. Traders take leveraged long/short positions on binary outcomes (elections, sports, etc.). A unified LP pool (LeverVault) backs all trades. The protocol references external prediction market prices (Polymarket) as its oracle — it does NOT build its own price discovery.

**Chain:** Base Sepolia (testnet) → Base (mainnet)
**Solidity:** 0.8.24 | Optimizer: on (200 runs)
**Dependencies:** OpenZeppelin v5.6.1, solmate, forge-std

---

## Architecture — 16 Contracts + 3 Libraries

### Libraries (no state, pure math)
| Library | Purpose |
|---------|---------|
| `FixedPointMath` | 18-decimal fixed-point arithmetic (WAD = 1e18). All protocol math uses this. |
| `RiskCurves` | Computes R(τ), R_borrow(τ), τ_effective, and all parameter mappings. |
| `ProbabilityIndex` | PI validation, bounds checking, convergence helpers. |

### Core Contracts (build order matters — see KNOWLEDGE/ARCHITECTURE.md)
| # | Contract | One-Line Purpose |
|---|----------|-----------------|
| 1 | `OracleAdapter` | Full price pipeline: ingests P_raw → validates → smooths → outputs PI. Includes volatility dampening, time-weighted smoothing, anti-manipulation filters, convergence enforcement. |
| 2 | `MarketRegistry` | Creates/manages markets. Stores metadata: resolution time, is_live, category, allocation weight. Source of τ and is_live for all other contracts. |
| 3 | `AccountManager` | User accounts, collateral deposits/withdrawals, position ownership tracking. |
| 4 | `PositionManager` | Stores all position state (entry PI, notional, collateral, leverage, borrow/funding index snapshots). Single source of truth for position data. CRUD only — no business logic. |
| 5 | `LeverageModel` | Three-step pipeline: Platform Ceiling → R(τ) compression → market-specific adjustment → Effective_Max_Leverage. M_market applied at BOTH R_adjusted level AND leverage level (intentional compounding). |
| 6 | `OILimits` | Four-tier OI cap system: global, per-market (dynamic), per-side, per-user. |
| 7 | `ExecutionEngine` | Orchestrates position opens/closes. Computes entry/exit prices via PI + imbalance-adjusted linear impact using imbalance_delta. NOT a vAMM. Calls PositionManager, MarginEngine, OILimits. |
| 8 | `MarginEngine` | IM, MM, equity calculation. Pincer effect: rising MM from below + borrow erosion from above. |
| 9 | `BorrowFeeEngine` | Continuous fee on all leveraged positions (1× exempt). Rate = base × M_ttR × (1 + surcharge). Time, liveness, volatility, concentration, and imbalance all feed in via R_borrow_adjusted and the surcharge. The "ticking clock." |
| 10 | `FundingRateEngine` | Trader↔trader periodic payments. Heavy side pays light side. Matched vs unmatched OI split. LP receives unmatched portion. |
| 11 | `FeeRouter` | Deterministic fee split. Routes borrow/TX/liquidation/settlement fees through 50/30/20 (LP/Protocol/Insurance). |
| 12 | `LeverVault` | ERC-4626 vault. LP deposits USDT → receives lvUSDT shares. NAV includes unrealized trader PnL. Tranche ledger for yield-carrying shares. |
| 13 | `RewardsDistributor` | Separate from vault. Receives LP's 50% fee share + unmatched funding. LPs claim yield without burning shares. |
| 14 | `InsuranceFund` | Bad debt absorption. Funded by 20% of fees. Three constraints: daily cap (25%), tiered split, 5% IFR floor. |
| 15 | `LiquidationEngine` | Force-closes positions when equity < MM. Partial liquidation, ordering, bad debt waterfall. |
| 16 | `SettlementEngine` | Binary resolution. PI snaps to 0 or 1. Settlement payout calculation, ADL, void handling. |

---

## Solidity Conventions

### Naming
- Contracts: PascalCase (`BorrowFeeEngine`)
- Functions: camelCase (`computeBorrowRate`)
- State variables: camelCase with underscore prefix for private (`_totalOI`)
- Constants: UPPER_SNAKE (`MAX_LEVERAGE`, `BASE_BORROW_RATE`)
- Events: PascalCase past tense (`PositionOpened`, `MarketResolved`)
- Errors: PascalCase with contract prefix (`MarginEngine__InsufficientCollateral`)

### Patterns
- **Access control:** OpenZeppelin AccessControl (roles: ADMIN, KEEPER, ORACLE, MARKET_MANAGER)
- **Reentrancy:** ReentrancyGuard on all external state-changing functions
- **Pausable:** All contracts pausable by ADMIN
- **Upgradeable:** NO proxies in v1. Immutable deployment. If we need to fix, redeploy.
- **Fixed-point math:** ALL monetary values in WAD (1e18). Never use raw decimals. Use FixedPointMath for multiply/divide.
- **Timestamps:** block.timestamp for on-chain time. External resolution timestamps stored separately.
- **Errors:** Custom errors only (no require strings). Gas efficient.
- **Events:** Emit on every state change. Indexed params: market_id, user, direction.

### Code Style
- Max function length: 50 lines. Extract helpers.
- NatSpec on every public/external function.
- No assembly unless gas-critical path (and must be commented heavily).
- Tests mirror contract structure: `test/BorrowFeeEngine.t.sol` tests `BorrowFeeEngine.sol`.
- Integration tests in `test/integration/`.

### File Layout Per Contract
```
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
// 2. Custom errors
// 3. Events
// 4. Type declarations / structs
// 5. State variables (constants, immutables, storage)
// 6. Constructor
// 7. External functions (state-changing)
// 8. External functions (view/pure)
// 9. Internal functions
// 10. Private functions
```

---

## Core Design Principles (NON-NEGOTIABLE)

1. **PI is the single source of truth.** Every component that needs a price uses PI. No secondary price feeds anywhere.
2. **Unified LP pool.** One pool backs all markets. No per-market pools.
3. **Continuous risk functions, not phase tables.** No Phase A/B/C. Everything is a smooth function of τ_effective.
4. **Two risk curves.** R(τ) with τ_ref=24h drives mechanical constraints. R_borrow(τ) with τ_ref=168h drives borrow fees. Different timescales, same exponential shape.
5. **Leverage → 1× at resolution.** By settlement, all positions should be fully collateralized. The ticking clock of borrow fees forces this.
6. **Fee split is deterministic.** 50% LP / 30% Protocol / 20% Insurance. (Tier 2 when IFR ≥ 20%: 50/50/0.)
7. **Funding is separate from protocol fees.** Matched funding = trader↔trader (zero-sum). Unmatched funding = trader→LP (risk compensation). Neither goes through the 50/30/20 split.
8. **Tranche ledger for LP shares.** lvUSDT is NOT a standard ERC-20 internally. Each address holds a list of tranches (max 10). Proportional split on transfer. Yield identity survives AMM passage.
9. **Withdrawal queue, not simple cooldown.** Request → 48h wait → execute at current NAV. FIFO ordering. Cancellable with 24h re-request cooldown.
10. **No cross-margining.** Each position has independent margin. No netting across markets.

---

## Key Constants (Quick Reference)

| Constant | Value | Used By |
|----------|-------|---------|
| `BASE_BORROW_RATE` | 0.02% per hour (2 bps/hr) | BorrowFeeEngine |
| `MAX_BORROW_MULTIPLIER` (M_ttR_max) | 25.0× | BorrowFeeEngine |
| `BASE_FUNDING_RATE` | 0.01% per hour | FundingRateEngine |
| `MAX_FUNDING_RATE` | 0.05% per hour (5 bps/hr) | FundingRateEngine |
| `FUNDING_ESCALATION_MAX` | 4.0× | FundingRateEngine |
| `LAMBDA` | 2.0 | RiskCurves |
| `TAU_REF` | 24 hours | RiskCurves (mechanical) |
| `TAU_REF_BORROW` | 168 hours (1 week) | RiskCurves (borrow) |
| `LIVE_COMPRESSION` | 0.70 | RiskCurves |
| `BASE_MAX_LEVERAGE` | 30× | LeverageModel |
| `TVL_MATURITY` | $50M | LeverageModel |
| `IFR_TARGET` | 20% of TVL | InsuranceFund |
| `INSURANCE_BOOTSTRAP` | $10,000 | InsuranceFund |
| `GLOBAL_OI_RATIO` | 60% of TVL | OILimits |
| `BASE_MM_RATE` | 2.5% of notional | MarginEngine |
| `MM_MULTIPLIER_RANGE` | 1.0× – 3.0× | MarginEngine |
| `LIQUIDATION_BUFFER` | 0.5% (50 bps) | MarginEngine |
| `TX_FEE` | 0.10% (10 bps) of notional | FeeRouter |
| `SETTLEMENT_FEE` | 0.20% (20 bps) of notional | SettlementEngine |
| `CONCENTRATION_THRESHOLD` | 15% of global OI | RiskCurves |
| `CONCENTRATION_FLOOR` | 0.5 | RiskCurves |
| `MAX_IMPACT` | 5% (0.05) | ExecutionEngine |
| `IMBALANCE_MULTIPLIER` | 2.0 | ExecutionEngine |
| `WITHDRAWAL_COOLDOWN` | 48 hours | LeverVault |
| `CANCEL_RE_REQUEST_COOLDOWN` | 24 hours | LeverVault |
| `MAX_UTILIZATION_FOR_WITHDRAWAL` | 80% | LeverVault |
| `MAX_TRANCHES_PER_ADDRESS` | 10 | LeverVault |
| `PENDING_RESOLUTION_MM_MULT` | 2.0× | SettlementEngine |
| `INSURANCE_DAILY_CAP` | 25% of insurance balance | InsuranceFund |
| `INSURANCE_FLOOR_IFR` | 5% of TVL | InsuranceFund |
| `SURCHARGE_FACTOR` | 1.0 | BorrowFeeEngine |

Full constant definitions with context: see `KNOWLEDGE/CONSTANTS.md`

---

## Formula Quick-Reference (Most Critical)

### Risk Curves
```
τ_effective = τ × (1 - live_compression × is_live)
R(τ) = 1 - e^(-λ × τ_effective / τ_ref)
R_borrow(τ) = 1 - e^(-λ × τ_effective / τ_ref_borrow)
R_adjusted = R(τ) × M_market
```

### Parameter Mappings (from R_adjusted)
```
Leverage_Compression = R_adjusted
OI_Cap_Multiplier = 0.20 + R_adjusted × 0.80
MM_Multiplier = 3.0 - R_adjusted × 2.0
IM_Multiplier = 3.0 - R_adjusted × 2.0
Borrow_M_ttR = 1.0 + (25.0 - 1.0) × (1 - R_borrow_adjusted)
```

### Equity (the equation everything depends on)
```
Equity = Collateral + PnL(PI) - Accrued_Borrow_Fees + Accrued_Funding
  Borrow: uint256, always positive (cost). Funding: int256 (+ = received, - = paid)
PnL = direction × (PI_current - PI_entry) × position_size
```

### Execution Price (imbalance_delta model — NOT ratio-based)
```
base_impact = trade_size / (market_depth × 2)
market_depth = Market_OI_Cap × Execution_Depth_Mult(R_adjusted)

imbalance_before = (longOI - shortOI) / totalOI
imbalance_after  = (longOI' - shortOI') / totalOI'    // post-trade values
imbalance_delta  = |imbalance_after| - |imbalance_before|
  // positive = trade worsens balance, negative = trade improves balance

impact = base_impact × (1 + imbalance_delta × imbalance_multiplier)
impact = min(impact, MAX_IMPACT)    // capped at 5%

entry_price = PI × (1 + impact)  // for longs
entry_price = PI × (1 - impact)  // for shorts
```

### Leverage Pipeline (3 steps — M_market applied TWICE for leverage)
```
Step 1: Platform_Ceiling = Base_Max × TVL_Mult × IFR_Mult × Util_Mult
Step 2: Compressed = Platform_Ceiling × R_adjusted        // R_adjusted already includes M_market
Step 3: Effective_Max = max(1.0, Compressed × M_market)   // M_market applied AGAIN at leverage level
```

All formulas with full variable definitions: see `KNOWLEDGE/FORMULAS.md`

---

## Agent Workflow Rules

### Build → Review Rotation
- The agent that builds a contract does NOT review it
- Reviews happen during the builder's cooldown rotation
- Reviewer checks against the spec file in `SPEC/` and the formulas in `KNOWLEDGE/FORMULAS.md`

### Session Discipline
- 2-hour session windows (context fills fast with DeFi contracts)
- At session start: read this file + KNOWLEDGE/lessons.md + relevant SPEC/prompts/
- Before building a contract: read its spec file AND the KNOWLEDGE/FORMULAS.md section for that contract
- On completion: write handoff doc to HANDOFF/
- Log lessons learned to KNOWLEDGE/lessons.md

### Git Discipline
- Commit after every contract completion
- Commit message format: `[CONTRACT_NAME] description of what was done`
- Never force push. Never rewrite history.
- Hourly auto-backup via cron handles pushes to GitHub

### Test Requirements
- Every contract gets unit tests covering:
  - Happy path for each external function
  - Edge cases (zero values, max values, overflow boundaries)
  - Access control (unauthorized callers revert)
  - All custom errors are tested
- Integration tests for cross-contract flows (open position → accrue fees → liquidate)
- Fuzz tests for mathematical functions (especially FixedPointMath, RiskCurves)

### What NOT To Do
- Do NOT use floating point. Everything is WAD (1e18 fixed-point).
- Do NOT hardcode magic numbers. Use named constants.
- Do NOT skip NatSpec. Every public function gets documentation.
- Do NOT build contracts out of dependency order. Check KNOWLEDGE/ARCHITECTURE.md.
- Do NOT assume PI is always between 0.01 and 0.99. It can be exactly 0 or 1 at settlement.
- Do NOT implement cross-margining. Each position is independent.
- Do NOT put yield into vault NAV. Yield goes to RewardsDistributor (separate contract).
- Do NOT use a vAMM. The execution model is linear impact, not constant-product.
- Do NOT use imbalance_ratio directly for execution impact. Use imbalance_delta (change in absolute imbalance caused by the specific trade). See WP Section 10.2.
- Do NOT apply M_market only once for leverage. It compounds: once inside R_adjusted, once as a separate Step 3 Market_Adjustment. See WP Section 9.9.

---

## Reference Files

| File | What's In It |
|------|-------------|
| `KNOWLEDGE/ARCHITECTURE.md` | Contract dependency graph, build order, data flow diagram |
| `KNOWLEDGE/FORMULAS.md` | Every formula from the whitepaper, organized by contract |
| `KNOWLEDGE/CONSTANTS.md` | Every constant with context and rationale |
| `KNOWLEDGE/TRANCHE_LEDGER.md` | Tranche ledger design + withdrawal queue |
| `KNOWLEDGE/lessons.md` | Running log of build lessons (self-improving) |
| `SPEC/*.md` | Per-contract build specs (Deliverable 4) |
| `BUILD_LOG.md` | Running log of what's been built |


## DEPLOYMENT VERIFICATION
- All deployed contract addresses are in control-plane/deploy-env.sh — this is the single source of truth
- After every deployment task, run control-plane/health-check.sh — if it fails, the task is not done
- Never trust script stdout ("SUCCESS") as proof — verify on-chain with cast calls
- Read control-plane/worker-rule.md before any deployment work

## TESTING AND VERIFICATION
Three mandatory scripts exist:
- control-plane/health-check.sh -- system-wide pass/fail
- scripts/visual-verify.js -- headless browser testing with screenshots
- scripts/user-flow-test.sh -- on-chain user journey simulation
Run appropriate scripts after every task. See control-plane/worker-rule.md for details.


## MANDATORY TASK WORKFLOW
1. `bash control-plane/preflight.sh` — fix issues first
2. `source control-plane/deploy-env.sh`
3. Read control-plane/thinking-protocol.md
4. Do the task
5. `bash control-plane/health-check.sh` — must pass
6. `node scripts/visual-verify.js` — frontend tasks
7. `bash scripts/user-flow-test.sh` — contract tasks
8. Commit with verification results

## WALLETS
- Deployer (.env.deployer): admin only
- Test wallet (.env.testwallet): testing + demo
- Bot wallets (control-plane/bot-wallets.json): 76 bots
- Fund bots: python3 scripts/fund-all-bots.py
- Every wallet needs ETH for gas

## COMMON ERRORS
- SourceNotActive = register oracle source
- AccessControlUnauthorized = wrong wallet or missing role
- MarketNotFound = markets not onboarded
- Black screen = React provider crash
- $0.00 stats = wrong addresses in config/contracts.ts
