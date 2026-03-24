# LEVER Protocol — Full Audit & Fix Plan

## Status: BLOCKED FOR INVESTOR DEMO — All bugs must be fixed before showing to investors

**Date**: 2026-03-23
**Context**: During FE investor demo preparation, discovered 9+ critical contract bugs including $426K unaccounted vault loss, systematic PnL bias (38 winners / 0 losers), and non-functional insurance fund.

---

## Phase 1: Contract-by-Contract Deep Analysis

Read EVERY contract. For each, verify:
- Math matches FORMULAS.md spec exactly
- Decimal handling (WAD 1e18 vs USDT 1e6) is consistent
- Money flows (USDT transfers) are complete — no orphaned accounting
- Access control is correct
- Reentrancy protection is in place
- Edge cases (zero values, overflow) are handled

### Analysis Order (dependency-first):

**Layer 0 — Pure Libraries (~600 lines)**
1. `contracts/libraries/FixedPointMath.sol` (301 lines)
2. `contracts/libraries/RiskCurves.sol` (243 lines)
3. `contracts/libraries/ProbabilityIndex.sol` (60 lines)

**Layer 1 — Data Stores (~750 lines)**
4. `contracts/core/MarketRegistry.sol` (313 lines)
5. `contracts/core/AccountManager.sol` (201 lines)
6. `contracts/core/PositionManager.sol` (235 lines)

**Layer 2 — Oracle (~477 lines)**
7. `contracts/core/OracleAdapter.sol` (477 lines)

**Layer 3 — Risk/Leverage/OI (~667 lines)**
8. `contracts/LeverageModel.sol` (333 lines)
9. `contracts/OILimits.sol` (334 lines)

**Layer 4 — Fee Engines (~679 lines)**
10. `contracts/BorrowFeeEngine.sol` (346 lines)
11. `contracts/FundingRateEngine.sol` (333 lines)

**Layer 5 — Margin & Execution (~988 lines)**
12. `contracts/MarginEngine.sol` (450 lines)
13. `contracts/ExecutionEngine.sol` (538 lines)

**Layer 6 — Fee Routing, Vault, Rewards (~1,078 lines)**
14. `contracts/FeeRouter.sol` (257 lines)
15. `contracts/InsuranceFund.sol` (282 lines)
16. `contracts/LeverVault.sol` (607 lines)
17. `contracts/RewardsDistributor.sol` (214 lines)

**Layer 7 — Terminal (~1,052 lines)**
18. `contracts/LiquidationEngine.sol` (452 lines)
19. `contracts/SettlementEngine.sol` (600 lines)

**Total: ~7,200 lines of Solidity**

---

## Phase 2: Known Bugs (Pre-Analysis)

| # | Severity | Bug | File(s) |
|---|----------|-----|---------|
| 1 | **CRITICAL** | PnL formula mismatch: ExecutionEngine uses `entryPrice` (impact-adjusted), MarginEngine/SettlementEngine use `entryPI` (raw). All equity views disagree with actual settlement. | ExecutionEngine:528-537, MarginEngine:367-370 |
| 2 | **CRITICAL** | OI not decremented on close — $3.2M ghost OI with zero open positions | ExecutionEngine:360, OILimits.decreaseOI |
| 3 | **CRITICAL** | $304K unaccounted vault drain — traced $122K of $426K loss | ExecutionEngine._settlePnL:375-420 |
| 4 | **CRITICAL** | InsuranceFund never absorbs bad debt — only emits event, no USDT transfer | ExecutionEngine:355-357, InsuranceFund.absorbBadDebt |
| 5 | **CRITICAL** | InsuranceFund WAD/USDT decimal mismatch — _balance mixes 1e18 bootstrap with 1e6 deposits | InsuranceFund:35,107 |
| 6 | **CRITICAL** | FeeRouter called without prior USDT transfer by Liquidation/Settlement engines — will revert | LiquidationEngine:421, SettlementEngine:269 |
| 7 | **CRITICAL** | Zero liquidations — MarginEngine.depthThreshold defaults to 0, causing ZeroDepthThreshold revert on every isLiquidatable check | MarginEngine:87, RiskCurves:108 |
| 8 | **HIGH** | No closing transaction fee — protocol forgoes 10bps of notional on every close | ExecutionEngine._executeClose |
| 9 | **HIGH** | Vault NAV doesn't include unrealized PnL — totalAssets() = raw USDT balance, _netUnrealizedPnL never updated | LeverVault.totalAssets, LeverVault.updateUnrealizedPnL |
| 10 | **MEDIUM** | LiquidationEngine doesn't transfer PnL losses to vault or route borrow fees | LiquidationEngine._closeAndSettle:396-408 |
| 11 | **MEDIUM** | FundingRateEngine.routeUnmatchedFunding — accounting only, no USDT to RewardsDistributor | FundingRateEngine:123-129 |
| 12 | **LOW** | SettlementEngine event emits wrong variable for totalLoserDebt | SettlementEngine:219-220 |

---

## Phase 3: Draft Findings Document

After Phase 1 analysis, produce a findings doc with for each bug:
- **ID**: LEVER-001 through LEVER-XXX
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Contract + Location**: file, function, line numbers
- **Description**: What is wrong
- **Expected** (from FORMULAS.md)
- **Actual** (from code)
- **Impact**: What happens, estimated loss
- **Fix**: Exact code change needed

---

## Phase 4: Review the Findings Doc

Re-read every contract with the findings doc in hand:
- Are any fixes incomplete?
- Do any fixes introduce new bugs?
- Are there cascading effects from one fix to another?
- Does the fix maintain the invariants from FORMULAS.md?

Revise the doc.

---

## Phase 5: Write Tests

For EVERY finding, write a Foundry test that:
1. **Demonstrates the bug** (fails on current code)
2. **Validates the fix** (passes on fixed code)

Additional tests:
- **Accounting invariant**: total USDT in system == total deposits (no money created/destroyed)
- **PnL consistency**: ExecutionEngine PnL == MarginEngine PnL for same position
- **OI tracking**: OI increases on open, decreases on close, net zero after all positions closed
- **InsuranceFund**: bad debt actually reduces insurance balance and transfers USDT
- **Fee routing**: all fee paths result in correct USDT transfers to correct destinations
- **Liquidation**: leveraged position at margin threshold gets liquidated correctly
- **Settlement**: binary resolution pays winners, takes from losers, routes fees
- **Vault NAV**: unrealized PnL reflected in totalAssets and share price

---

## Phase 6: Frontend Tests (Puppeteer)

Write Puppeteer tests that verify:
- Position open: correct entry price shown matches on-chain PI + impact
- Position close: PnL matches on-chain mark price, not Polymarket oracle
- Market detail: Mark price shows on-chain PI, warning when stale
- Vault: TVL, APY, share price match on-chain data
- Positions tab: entry, PnL, equity all calculated from on-chain mark price
- Recent trades: real event data from chain, correct BaseScan links
- Liquidity pool: depth metrics match on-chain OI caps

---

## Phase 7: Test → Review → Fix → Repeat

1. Run all tests
2. Review failures
3. Fix code
4. Re-run tests
5. Review passes for false positives
6. QA/QC pass

---

## Phase 8: Final Draft & Deployment Plan

Produce:
1. Final findings doc with all fixes verified by tests
2. Deployment script that redeploys affected contracts
3. Migration plan (handle existing state: ghost OI, stale prices, vault NAV)
4. Keeper configuration (oracle keeper gas optimization, liquidation keeper setup)

---

## Forensic Data (Current State)

### On-Chain Facts
- Vault NAV: $24,640,546 (lost $426K from initial ~$25.07M)
- Vault share price: 0.9836 (below 1.0 — LPs underwater)
- Ghost OI: $3,201,132 (zero open positions)
- Open positions: 0
- Total positions ever opened: 114
- Total positions ever closed: 66
- Closed PnL: 38 winners, 0 losers, 28 breakeven = $16,289 net to traders
- Closing fees: OVERFLOW (~1.5e72) — decimal mismatch in event encoding
- InsuranceFund USDT balance: $5,000,000 (untouched)
- InsuranceFund internal _balance: ~10 quadrillion (WAD bootstrap never decremented correctly)
- AccountManager USDT: $12,741,297 ($5.9M unaccounted vs known trader balances $6.8M)
- FeeRouter USDT: $94,471 (fees collected but not fully distributed)
- RewardsDistributor USDT: $10,920
- Liquidations: 0 (ever)
- Keeper wallet: 0x0e4D636c6D79c380A137f28EF73E054364cd5434 (funded with ~0.01 ETH, ~8 days runway)

### Key Wallet Addresses
- Demo wallet: 0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da (key: e7d996...)
- Test wallet: 0xB072263740D7c60f1Aa0BF46e737F83544C7b785 (key: bf4b6a...)
- Keeper: 0x0e4D636c6D79c380A137f28EF73E054364cd5434 (key in .env.deployer)
- 20 demo wallets: /home/lever/lever-protocol/control-plane/demo-wallets.json
- 76 bot wallets: /home/lever/lever-protocol/control-plane/bot-wallets.json

### Key File Locations
- Contracts: /home/lever/lever-protocol/contracts/
- Tests: /home/lever/lever-protocol/test/
- Specs: /home/lever/lever-protocol/SPEC/
- Formulas: /home/lever/lever-protocol/KNOWLEDGE/FORMULAS.md
- Constants: /home/lever/lever-protocol/KNOWLEDGE/CONSTANTS.md
- Architecture: /home/lever/lever-protocol/KNOWLEDGE/ARCHITECTURE.md
- Frontend: /home/lever/lever-protocol/frontend/user-app/
- Deployments: /home/lever/lever-protocol/frontend/user-app/public/deployments/
- Oracle keeper: /home/lever/lever-protocol/scripts/oracle/mock_keeper.py
- Keeper service: lever-oracle.service (systemd)

### FE Fixes Already Made (This Session)
- Fused Markets + Trading tabs into single "Trade" tab
- Fixed Positions top stats (was showing dashes, now shows real data from on-chain)
- Redesigned footer (slim single-line status bar)
- Redesigned MarketDetail page (two-column layout, sticky trade form, liquidity pool viz, real on-chain recent trades)
- Fixed PnL calculation to use on-chain mark price (getPI) not Polymarket oracle
- Fixed mark price label to show staleness warning
- All loading animations use spinning Lever logo
- Keeper funded and running (multicall batched, 20 markets per TX, ~8 day runway)
- Keeper stepping logic added for anti-manipulation filter (gradual price convergence)
