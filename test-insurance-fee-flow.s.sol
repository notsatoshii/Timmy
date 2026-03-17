// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/ExecutionEngine.sol";
import "./contracts/core/AccountManager.sol";
import "./contracts/InsuranceFund.sol";
import "./contracts/FeeRouter.sol";
import "./contracts/BorrowFeeEngine.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./contracts/interfaces/IExecutionEngine.sol";

/// @notice Test insurance fund fee flow by opening positions and checking balances
contract TestInsuranceFeeFlow is Script {
    function run() external {
        vm.startBroadcast();

        // Load contract addresses
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address accountManager = vm.envAddress("ACCOUNT_MANAGER");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address feeRouter = vm.envAddress("FEE_ROUTER");
        address usdt = vm.envAddress("USDT_ADDRESS");
        address borrowFeeEngine = vm.envAddress("BORROW_FEE_ENGINE");

        console.log("=== TESTING INSURANCE FUND FEE FLOW ===");
        console.log("ExecutionEngine:", executionEngine);
        console.log("InsuranceFund:", insuranceFund);
        console.log("FeeRouter:", feeRouter);
        console.log("");

        // Get initial states
        uint256 insuranceBalanceBefore = InsuranceFund(insuranceFund).getBalance();
        uint256 usdtBalanceBefore = IERC20(usdt).balanceOf(msg.sender);
        uint8 tier = FeeRouter(feeRouter).getCurrentTier();
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = FeeRouter(feeRouter).getCurrentSplit();

        console.log("BEFORE Transaction:");
        console.log("  Insurance Fund balance:", insuranceBalanceBefore / 1e18);
        console.log("  USDT balance:", usdtBalanceBefore / 1e18);
        console.log("  Fee tier:", tier);
        console.log("  Insurance share:", insurancePct / 1e15, "bps");
        console.log("");

        // Test market ID from health check
        bytes32 marketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        // Test parameters
        uint256 collateral = 50e18; // 50 USDT (smaller amount)
        uint256 leverage = 2e18; // 2x leverage
        bool isLong = true;

        console.log("Opening position...");
        console.log("  Collateral:", collateral / 1e18);
        console.log("  Leverage:", leverage / 1e18);
        console.log("  Notional:", (collateral * leverage) / 1e36);

        // Approve and deposit collateral to AccountManager
        IERC20(usdt).approve(accountManager, collateral);
        AccountManager(accountManager).deposit(collateral);

        // Open position
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: isLong,
            collateral: collateral,
            leverage: leverage
        });

        uint256 positionId = ExecutionEngine(executionEngine).openPosition(params);
        console.log("Position opened with ID:", positionId);

        // Check immediate impact on insurance fund (from transaction fee)
        uint256 insuranceBalanceAfterTx = InsuranceFund(insuranceFund).getBalance();
        uint256 txFeeIncrease = insuranceBalanceAfterTx > insuranceBalanceBefore
            ? insuranceBalanceAfterTx - insuranceBalanceBefore
            : 0;
        console.log("Insurance balance after TX fee:", insuranceBalanceAfterTx / 1e18);
        console.log("TX fee to insurance:", txFeeIncrease);

        // Simulate time passage for borrow fees to accrue
        console.log("");
        console.log("Simulating 6 hours for borrow fees...");
        vm.warp(block.timestamp + 6 hours);

        // Trigger borrow fee accrual manually
        BorrowFeeEngine(borrowFeeEngine).accrueIndex(marketId, true);

        // Check borrow fees
        uint256 accruedBorrowFees = BorrowFeeEngine(borrowFeeEngine).getAccruedFees(positionId);
        console.log("Accrued borrow fees:", accruedBorrowFees / 1e18);

        // Close position to trigger fee routing
        console.log("Closing position...");
        ExecutionEngine(executionEngine).closePosition(positionId);

        // Get final state
        uint256 insuranceBalanceAfter = InsuranceFund(insuranceFund).getBalance();
        console.log("");
        console.log("AFTER closing position:");
        console.log("  Insurance Fund balance:", insuranceBalanceAfter / 1e18);

        uint256 totalFeeIncrease = insuranceBalanceAfter > insuranceBalanceBefore
            ? insuranceBalanceAfter - insuranceBalanceBefore
            : 0;
        console.log("  Total fee increase:", totalFeeIncrease / 1e18);

        // Check fee routing totals
        uint256 txFeesRouted = FeeRouter(feeRouter).getTotalFeesRouted(IFeeRouter.FeeType.TRANSACTION);
        uint256 borrowFeesRouted = FeeRouter(feeRouter).getTotalFeesRouted(IFeeRouter.FeeType.BORROW);

        console.log("");
        console.log("Fee router totals:");
        console.log("  TX fees routed:", txFeesRouted / 1e18);
        console.log("  Borrow fees routed:", borrowFeesRouted / 1e18);

        // Analysis
        console.log("");
        if (totalFeeIncrease > 0) {
            console.log("SUCCESS: Insurance fund received fees!");
        } else if (tier == 2) {
            console.log("INFO: Insurance fund is fully funded (Tier 2)");
            console.log("      No fees go to insurance in Tier 2 (50/50/0 split)");
            console.log("      This is normal protocol behavior.");
        } else {
            console.log("FAILURE: No fees flowed to insurance fund");
        }

        vm.stopBroadcast();
    }
}