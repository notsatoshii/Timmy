#!/bin/bash
cd /home/lever/lever-protocol
LOG="/home/lever/lever-protocol/test-phase.log"
BOT_TOKEN="8541708860:AAGmNKlIeo5Acn6Wssk6HzQR1QfMNX2GXwk"
CHAT_ID="422985839"

notify() {
  curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${CHAT_ID}&text=$1" > /dev/null
}

run_step() {
  echo "========================================" >> $LOG
  echo "STEP: $1" >> $LOG
  echo "TIME: $(date)" >> $LOG
  echo "========================================" >> $LOG
  notify "Starting: $1"
  claude --dangerously-skip-permissions -p "$2" >> $LOG 2>&1
  echo "" >> $LOG
  echo "FINISHED: $1 at $(date)" >> $LOG
  echo "" >> $LOG
}

echo "TEST PHASE STARTED: $(date)" > $LOG
notify "TEST PHASE STARTED"

# ============================================
# PHASE A: Fix Known Issues
# ============================================

run_step "Fix CLAUDE.md USDC refs" "In CLAUDE.md, find all references to USDC and change them to USDT. Find all references to lvUSDC and change them to lvUSDT. The canonical stablecoin for LEVER is USDT. Commit with message: fix: CLAUDE.md USDC to USDT references"

run_step "Fix foundry.toml via_ir" "Check if foundry.toml has via_ir = true under [profile.default]. If not, add it. Run forge build to verify it compiles. Commit if changed."

run_step "Fix RiskCurves edge case" "In contracts/libraries/RiskCurves.sol: add a custom error RiskCurves__ZeroDepthThreshold() and make computeDepthFactor revert when depthThreshold == 0 instead of returning WAD. Update test/RiskCurves.t.sol: change test_depthFactor_zeroThreshold to expect the revert. Run forge test and commit."

run_step "Full compile check" "Run forge build. If there are any errors, fix them. Show me the final output."

run_step "Full test suite" "Run forge test --summary. Report how many tests pass and fail across all files. If any fail, fix them and rerun. Do not move on until all tests pass."

# ============================================
# PHASE B: Math Verification Scripts
# ============================================

run_step "Math verification: RiskCurves" "Write test/MathVerification.t.sol. Test RiskCurves with these exact inputs and verify against hand-calculated expected outputs:
- computeEffectiveTau(4 hours in seconds, true): expect 4 * 0.30 = 1.2 hours in seconds
- computeR(1.2 hours WAD, 24 hours WAD): expect 1 - exp(-2.0 * 1.2 / 24) = 0.09516 in WAD (tolerance 0.001)
- computeRBorrow(1.2 hours WAD, 168 hours WAD): expect 1 - exp(-2.0 * 1.2 / 168) = 0.01423 in WAD (tolerance 0.001)
- computeRAdjusted with R=0.09516 WAD and M_market=0.8 WAD: expect 0.07613 WAD (tolerance 0.001)
Run forge test -vv on this file. If values dont match within tolerance, something is wrong - report the actual vs expected."

run_step "Math verification: LeverageModel" "Add to test/MathVerification.t.sol. Test the full leverage pipeline with the whitepaper worked example:
- TVL = 10M USDT (10_000_000e18), Insurance = 600K (IFR = 6%), Global Utilization = 40%, tau = 4 hours, is_live = true, M_market = 0.80
- Step 1: TVL_Mult = sqrt(10M / 50M) = 0.4472. IFR_Mult = max(0.40, 6/10) = 0.60. Util_Mult = max(0.30, 1 - 0.70 * max(0, (0.40 - 0.30)/0.70)) = 0.90. Platform_Ceiling = 30 * 0.4472 * 0.60 * 0.90 = 7.24x
- Step 2: R_adjusted = 0.07613. Compressed = 7.24 * 0.07613 = 0.551x
- Step 3: Effective_Max = max(1.0, 0.551 * 0.80) = max(1.0, 0.441) = 1.0x
- Verify the contract returns approximately 1.0x (WAD) for these inputs. Tolerance 0.1 WAD.
Run forge test -vv. Report actual vs expected."

run_step "Math verification: ExecutionEngine" "Add to test/MathVerification.t.sol. Test execution pricing:
- Market_OI_Cap = 1_000_000e18, R_adjusted = 0.50 WAD
- market_depth = 1_000_000 * (0.30 + 0.50 * 0.70) = 650_000
- Trade size = 10_000e18, long_oi = 300_000e18, short_oi = 200_000e18
- base_impact = 10_000 / (650_000 * 2) = 0.00769
- imbalance_before = |300_000 - 200_000| = 100_000. imbalance_after (long open) = |310_000 - 200_000| = 110_000
- imbalance_delta = 110_000 - 100_000 = 10_000 (as WAD ratio of OI cap = 0.01)
- impact = min(0.00769 * (1 + 0.01 * 2.0), 0.05) = min(0.00769 * 1.02, 0.05) = 0.00784
- For PI = 0.60 WAD: entry_price = 0.60 * (1 + 0.00784) = 0.60471
- Verify within tolerance of 0.001. Run forge test -vv."

run_step "Math verification: FundingRateEngine" "Add to test/MathVerification.t.sol. Test single funding index:
- Set funding rate to 0.001 WAD per second. Advance 3600 seconds (1 hour).
- Expected index delta = 0.001 * 3600 = 3.6 WAD
- Long position, size = 100e18, entry index = 0: accrued = -1 * 100 * (3.6 - 0) = -360 (long pays)
- Short position, size = 100e18, entry index = 0: accrued = -(-1) * 100 * (3.6 - 0) = +360 (short receives)
- Verify signs are correct: longs pay positive funding, shorts receive. This is THE bug that took 3 rounds to fix.
Run forge test -vv. Report actual vs expected."

run_step "Math verification: BorrowFeeEngine" "Add to test/MathVerification.t.sol. Test borrow fee accrual:
- Base rate = 0.0002 per hour. M_ttR at tau=0 should be 25x. No imbalance surcharge.
- Effective rate = 0.0002 * 25 = 0.005 per hour
- After 10 hours: accrued index = 0.005 * 10 = 0.05
- Position size 1000 USDT at 5x leverage, notional = 5000. Borrow fee = 5000 * 0.05 = 250 USDT
- But 1x is exempt, so borrowable notional = 4000. Borrow fee = 4000 * 0.05 = 200 USDT
- Verify within tolerance. Run forge test -vv."

run_step "Math verification: MarginEngine equity" "Add to test/MathVerification.t.sol. Test the canonical equity equation:
- Collateral = 1000e18, Direction = long (+1), Entry PI = 0.50, Current PI = 0.60, Size = 10_000e18
- PnL = +1 * (0.60 - 0.50) * 10_000 = +1000 USDT
- Accrued borrow = 200e18 (from previous test scenario)
- Accrued funding = -360e18 (long pays, from previous test scenario)
- Equity = 1000 + 1000 - 200 + (-360) = 1440 USDT
- Verify Equity = Collateral + PnL - BorrowFees + Funding where Funding is signed int256
Run forge test -vv. Report actual vs expected."

# ============================================
# PHASE C: Integration Tests (no mocks)
# ============================================

run_step "Integration: Full lifecycle" "Write test/Integration.t.sol. This test deploys ALL contracts with real implementations - NO mocks. Wire them together with proper addresses and permissions. Then run this scenario:
1. Create a market with M_market=0.80, sigma=0.5
2. LP deposits 100_000 USDT into LeverVault
3. Verify vault NAV = 100_000 USDT
4. Trader deposits 1_000 USDT collateral via AccountManager
5. Trader opens 5x long at PI=0.50 via ExecutionEngine (notional 5000, size=10_000)
6. Verify position exists in PositionManager with correct fields
7. Verify OI increased in OILimits
8. Simulate oracle moving PI from 0.50 to 0.60
9. Check equity is positive and approximately correct
10. Trader closes position
11. Verify PnL distributed correctly - trader received profit, vault absorbed loss
12. Verify all OI returned to zero
13. Verify vault NAV reflects the loss
If any step fails, report what failed and what the actual values were. Do NOT skip failures. Run with forge test -vv."

run_step "Integration: Liquidation" "Add to test/Integration.t.sol. New test function:
1. Same setup: LP deposits 100K, market created
2. Trader opens 10x long at PI=0.50 with 1000 USDT collateral
3. Move oracle to PI=0.42 (should be near liquidation)
4. Check if position is liquidatable via MarginEngine
5. Execute liquidation via LiquidationEngine
6. Verify liquidation fee = 1.0% of notional went to correct destination
7. Verify position is closed or reduced
8. If bad debt: verify LP socialization happened via LeverVault.socializeLoss()
9. Verify InsuranceFund balance changed appropriately
Run forge test -vv. Report results."

run_step "Integration: Settlement" "Add to test/Integration.t.sol. New test function:
1. Create market, LP deposits, two traders open opposing positions (one long, one short)
2. Both accrue funding and borrow fees for simulated 24 hours
3. Resolve market at PI=1.0 (outcome happened)
4. Call SettlementEngine to settle both positions
5. Verify fees were frozen at resolution timestamp, not settlement timestamp
6. Verify long trader receives full payout minus fees
7. Verify short trader loses full collateral minus any remaining
8. Verify funding payments net to zero between the two sides
9. Verify vault NAV is consistent after settlement
Run forge test -vv. Report results."

run_step "Integration: Multi-market stress" "Add to test/Integration.t.sol. New test function:
1. Create 3 markets with different M_market values (0.60, 0.80, 1.00)
2. LP deposits 500K USDT
3. Open positions across all 3 markets, some long some short
4. Move oracles in different directions
5. Verify global OI limits enforced across markets
6. Verify utilization calculation is correct globally
7. Verify leverage limits differ per market due to different M_market
8. Close all positions
9. Verify vault NAV is consistent - total fees collected match fee distributions
Run forge test -vv. Report results."

# ============================================
# PHASE D: Final Report
# ============================================

run_step "Final test run" "Run forge test --summary. Show total tests, passes, failures. If any failures remain, list them with the error messages. Then run forge snapshot to generate gas benchmarks. Commit everything."

echo "========================================" >> $LOG
echo "TEST PHASE COMPLETE: $(date)" >> $LOG
echo "========================================" >> $LOG
notify "TEST PHASE COMPLETE. Check test-phase.log for results."
