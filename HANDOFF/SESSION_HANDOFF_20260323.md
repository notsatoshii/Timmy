# Session Handoff — 2026-03-23 Full Protocol Audit & Fix

## WHAT TO DO

You are continuing a full protocol audit and fix session. The user wants EVERY contract analyzed, all bugs fixed, tested, and redeployed. This is blocking an investor demo.

**READ THESE FILES FIRST:**
1. `/home/lever/lever-protocol/HANDOFF/FULL_AUDIT_PLAN.md` — The complete audit plan with all known bugs, analysis order, and phases
2. `/home/lever/lever-protocol/CLAUDE.md` — Protocol architecture, conventions, formulas
3. `/home/lever/lever-protocol/KNOWLEDGE/FORMULAS.md` — Every formula from the whitepaper
4. `/home/lever/lever-protocol/KNOWLEDGE/CONSTANTS.md` — Every constant with rationale

## THE WORK

### Step 1: Deep Analysis (all 19 contracts)
Read every contract in dependency order (see FULL_AUDIT_PLAN.md Layer 0→7). For each:
- Verify math matches FORMULAS.md
- Check decimal handling (WAD 1e18 vs USDT 1e6)
- Trace USDT transfers end-to-end
- Check access control, reentrancy
- Note any bugs not already in the known list

### Step 2: Draft Findings Document
Write `/home/lever/lever-protocol/REVIEW/AUDIT_FINDINGS_V1.md` with every finding in format:
- ID, Severity, Contract, Location, Description, Expected, Actual, Impact, Fix

### Step 3: Review the Draft
Re-read every contract with the findings doc. Look for:
- Incomplete fixes, cascading effects, new bugs introduced by fixes
- Revise the doc → V2

### Step 4: Write Tests
For every finding, write a Foundry test in `/home/lever/lever-protocol/test/audit/`:
- `AuditPnLConsistency.t.sol` — PnL matches across ExecutionEngine/MarginEngine/SettlementEngine
- `AuditOITracking.t.sol` — OI increases on open, decreases on close
- `AuditInsuranceFund.t.sol` — bad debt absorption with real USDT transfers
- `AuditFeeRouting.t.sol` — all fee paths have USDT pre-transferred
- `AuditLiquidation.t.sol` — leveraged position gets liquidated
- `AuditVaultNAV.t.sol` — unrealized PnL in totalAssets
- `AuditAccountingInvariant.t.sol` — total USDT in == total USDT out
- `AuditDecimalConsistency.t.sol` — WAD vs USDT decimals everywhere

Also write Puppeteer FE tests in `/root/fe-audit-tests.js`:
- Position open shows correct entry price from on-chain
- PnL uses on-chain mark price
- Market detail shows staleness warnings
- Vault metrics match on-chain

### Step 5: Implement Fixes
Fix every contract. Key fixes needed:
1. **ExecutionEngine._executeClose**: Use `entryPI` and `currentPI` for PnL, not impact prices
2. **ExecutionEngine._executeClose**: Add closing TX fee via feeRouter.collectTransactionFee
3. **ExecutionEngine._executeClose**: Route bad debt to InsuranceFund.absorbBadDebt
4. **InsuranceFund**: Fix decimal mismatch — use USDT decimals consistently, add real USDT transfers for absorbBadDebt
5. **LiquidationEngine._routeFee**: Transfer USDT to FeeRouter before calling routeFees
6. **SettlementEngine.claimSettlement**: Same — transfer USDT before routeFees
7. **LeverVault**: Update _netUnrealizedPnL tracking, or simplify totalAssets
8. **MarginEngine**: Ensure depthThreshold is set for all markets (deployment fix)
9. **OILimits.decreaseOI**: Debug why ghost OI persists — check role grants and revert handling
10. **FundingRateEngine.routeUnmatchedFunding**: Add actual USDT transfer to RewardsDistributor

### Step 6: Test → Review → Fix → Repeat
Run `forge test`, fix failures, re-review.

### Step 7: Final Draft
Produce final `/home/lever/lever-protocol/REVIEW/AUDIT_FINDINGS_FINAL.md`

### Step 8: Redeploy
Use `forge script` to redeploy affected contracts. Update deployment JSONs. Restart keeper. Re-seed positions.

## 12 KNOWN BUGS (ranked by severity)

1. **CRITICAL** — PnL formula mismatch (entryPrice vs entryPI) → 38 winners, 0 losers
2. **CRITICAL** — $304K unaccounted vault drain
3. **CRITICAL** — Ghost OI ($3.2M with zero positions)
4. **CRITICAL** — InsuranceFund never absorbs (no USDT transfer, just accounting)
5. **CRITICAL** — InsuranceFund decimal mismatch (WAD bootstrap + USDT deposits)
6. **CRITICAL** — FeeRouter called without USDT by Liquidation/Settlement
7. **CRITICAL** — Zero liquidations (depthThreshold unset → ZeroDepthThreshold revert)
8. **HIGH** — No closing transaction fee (10bps foregone)
9. **HIGH** — Vault NAV missing unrealized PnL (_netUnrealizedPnL never updated)
10. **MEDIUM** — LiquidationEngine doesn't route losses to vault
11. **MEDIUM** — FundingRateEngine.routeUnmatchedFunding — no USDT transfer
12. **LOW** — SettlementEngine event emits wrong variable

## CURRENT SYSTEM STATE

- All positions closed (0 open)
- Ghost OI: $3.2M on-chain
- Vault NAV: $24.64M (lost $426K)
- Share price: 0.9836
- InsuranceFund: $5M USDT (untouched)
- Keeper running (multicall, ~8 day runway)
- Frontend deployed at http://165.245.186.254:3000/
- Base Sepolia testnet
