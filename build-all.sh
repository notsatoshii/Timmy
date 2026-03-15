#!/bin/bash
cd /root/lever-protocol
LOG="/root/lever-protocol/build.log"

run_step() {
  echo "========================================" >> $LOG
  echo "STEP: $1" >> $LOG
  echo "TIME: $(date)" >> $LOG
  echo "========================================" >> $LOG
  claude --dangerously-skip-permissions -p "$2" >> $LOG 2>&1
  echo "" >> $LOG
  echo "FINISHED: $1 at $(date)" >> $LOG
  echo "" >> $LOG
}

echo "BUILD STARTED: $(date)" > $LOG

# Phase 1: Libraries
run_step "FixedPointMath" "Read SPEC/01-FixedPointMath.md and KNOWLEDGE/FORMULAS.md. Implement contracts/libraries/FixedPointMath.sol with all functions: wadMul, wadDiv, wadExp, wadLn, wadSqrt, wadPow, clamp, clampInt, abs, toInt256, toUint256. Use solmate as reference for wadExp. Write tests at test/FixedPointMath.t.sol covering all edge cases from the spec. Run forge test and fix any failures. Commit when green."

run_step "RiskCurves" "Read SPEC/02-RiskCurves.md and KNOWLEDGE/FORMULAS.md. Implement contracts/libraries/RiskCurves.sol with computeR, computeRBorrow, computeRAdjusted, computeEffectiveTau. Use FixedPointMath for all math. Write tests at test/RiskCurves.t.sol. Run forge test and fix failures. Commit when green."

run_step "ProbabilityIndex" "Read SPEC/03-ProbabilityIndex.md. Implement contracts/libraries/ProbabilityIndex.sol. Write tests at test/ProbabilityIndex.t.sol. Run forge test and fix failures. Commit when green."

# Phase 2: Core Infrastructure
run_step "OracleAdapter" "Read SPEC/04-OracleAdapter.md. Implement contracts/OracleAdapter.sol including smoothing logic (SmoothingEngine is merged in). Write tests at test/OracleAdapter.t.sol. Run forge test and fix failures. Commit when green."

run_step "MarketRegistry" "Read SPEC/05-MarketRegistry.md. Implement contracts/MarketRegistry.sol. Write tests at test/MarketRegistry.t.sol. Run forge test and fix failures. Commit when green."

run_step "AccountManager" "Read SPEC/06-AccountManager.md. Implement contracts/AccountManager.sol. Write tests at test/AccountManager.t.sol. Run forge test and fix failures. Commit when green."

run_step "PositionManager" "Read SPEC/07-PositionManager.md. Implement contracts/PositionManager.sol as a pure data store, no business logic. Write tests at test/PositionManager.t.sol. Run forge test and fix failures. Commit when green."

# Phase 3: Risk and Execution
run_step "LeverageModel" "Read SPEC/08-LeverageModel.md and KNOWLEDGE/FORMULAS.md. Implement contracts/LeverageModel.sol with the 3-step leverage pipeline. M_market is applied TWICE - once in R_adjusted, once in Step 3. Write tests at test/LeverageModel.t.sol. Run forge test and fix failures. Commit when green."

run_step "OILimits" "Read SPEC/09-OILimits.md. Implement contracts/OILimits.sol. Write tests at test/OILimits.t.sol. Run forge test and fix failures. Commit when green."

run_step "ExecutionEngine" "Read SPEC/10-ExecutionEngine.md and KNOWLEDGE/FORMULAS.md. Implement contracts/ExecutionEngine.sol using imbalance_delta model, NOT imbalance_ratio. MAX_IMPACT = 5 percent. Write tests at test/ExecutionEngine.t.sol. Run forge test and fix failures. Commit when green."

run_step "MarginEngine" "Read SPEC/11-MarginEngine.md and KNOWLEDGE/FORMULAS.md. Implement contracts/MarginEngine.sol. Equity = Collateral + PnL - BorrowFees + Funding (int256 signed). Write tests at test/MarginEngine.t.sol. Run forge test and fix failures. Commit when green."

# Phase 4: Fee Engines
run_step "BorrowFeeEngine" "Read SPEC/12-BorrowFeeEngine.md and KNOWLEDGE/FORMULAS.md. Implement contracts/BorrowFeeEngine.sol with computeIndexAt for settlement freeze. Write tests at test/BorrowFeeEngine.t.sol. Run forge test and fix failures. Commit when green."

run_step "FundingRateEngine" "Read SPEC/13-FundingRateEngine.md and KNOWLEDGE/FORMULAS.md. Implement contracts/FundingRateEngine.sol with SINGLE funding index per market. accrued = -direction * posSize * (currentIndex - entryIndex). Write tests at test/FundingRateEngine.t.sol. Run forge test and fix failures. Commit when green."

run_step "FeeRouter" "Read SPEC/14-FeeRouter.md. Implement contracts/FeeRouter.sol. Write tests at test/FeeRouter.t.sol. Run forge test and fix failures. Commit when green."

# Phase 5: Vault and Settlement
run_step "LeverVault" "Read SPEC/15-LeverVault.md. Implement contracts/LeverVault.sol. Deposit asset is USDT, LP token is lvUSDT. NAV includes unrealized PnL tracked via _netUnrealizedPnL. Tranche transfer is proportional from ALL tranches. Has socializeLoss(). Write tests at test/LeverVault.t.sol. Run forge test and fix failures. Commit when green."

run_step "RewardsDistributor" "Read SPEC/16-RewardsDistributor.md. Implement contracts/RewardsDistributor.sol. Write tests at test/RewardsDistributor.t.sol. Run forge test and fix failures. Commit when green."

run_step "InsuranceFund" "Read SPEC/17-InsuranceFund.md. Implement contracts/InsuranceFund.sol. Write tests at test/InsuranceFund.t.sol. Run forge test and fix failures. Commit when green."

run_step "LiquidationEngine" "Read SPEC/18-LiquidationEngine.md. Implement contracts/LiquidationEngine.sol with three-path model (A/B/C). Liquidation fee is 1.0 percent (100 bps). Bad debt goes to LP socialization. Liquidations go through ExecutionEngine with impact. Write tests at test/LiquidationEngine.t.sol. Run forge test and fix failures. Commit when green."

run_step "SettlementEngine" "Read SPEC/19-SettlementEngine.md. Implement contracts/SettlementEngine.sol. Settlement fees frozen at external resolution timestamp. ADL only at settlement. Write tests at test/SettlementEngine.t.sol. Run forge test and fix failures. Commit when green."

echo "========================================" >> $LOG
echo "ALL BUILDS COMPLETE: $(date)" >> $LOG
echo "========================================" >> $LOG
