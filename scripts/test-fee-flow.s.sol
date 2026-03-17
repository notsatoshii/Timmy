// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/AccountManager.sol";
import "../contracts/InsuranceFund.sol";
import "../contracts/FeeRouter.sol";
import "../contracts/interfaces/IERC20.sol";

/// @notice Test fee flow by opening and closing a small position
contract TestFeeFlow is Script {
    function run() external {
        vm.startBroadcast();

        // Load contract addresses
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address accountManager = vm.envAddress("ACCOUNT_MANAGER");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address feeRouter = vm.envAddress("FEE_ROUTER");
        address usdt = vm.envAddress("USDT_ADDRESS");

        console.log("Testing fee flow...");
        console.log("ExecutionEngine:", executionEngine);
        console.log("InsuranceFund:", insuranceFund);

        // Get initial insurance fund balance
        uint256 insuranceBalanceBefore = InsuranceFund(insuranceFund).getBalance();
        console.log("Insurance Fund balance before:", insuranceBalanceBefore);

        // Get test market ID (from health check)
        bytes32 marketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        // Test parameters
        uint256 collateral = 100e18; // 100 USDT
        uint256 leverage = 2e18; // 2x leverage
        bool isLong = true;

        // Make sure we have USDT balance
        uint256 usdtBalance = IERC20(usdt).balanceOf(msg.sender);
        console.log("USDT balance:", usdtBalance);

        // Deposit collateral to AccountManager first
        console.log("Depositing collateral to AccountManager...");
        IERC20(usdt).approve(accountManager, collateral);
        AccountManager(accountManager).deposit(collateral);

        // Open position
        console.log("Opening position...");
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: isLong,
            collateral: collateral,
            leverage: leverage,
            slippage: 5e16  // 5% slippage tolerance
        });

        uint256 positionId = ExecutionEngine(executionEngine).openPosition(params);
        console.log("Position opened with ID:", positionId);

        // Wait a moment (simulate time passage for fees to accrue)
        vm.warp(block.timestamp + 1 hours);

        // Close position
        console.log("Closing position...");
        ExecutionEngine(executionEngine).closePosition(positionId);

        // Get final insurance fund balance
        uint256 insuranceBalanceAfter = InsuranceFund(insuranceFund).getBalance();
        console.log("Insurance Fund balance after:", insuranceBalanceAfter);

        uint256 feeIncrease = insuranceBalanceAfter > insuranceBalanceBefore
            ? insuranceBalanceAfter - insuranceBalanceBefore
            : 0;
        console.log("Insurance Fund fee increase:", feeIncrease);

        if (feeIncrease > 0) {
            console.log("SUCCESS: Fee flow working correctly!");
        } else {
            console.log("FAILURE: No fees flowed to insurance fund");
        }

        vm.stopBroadcast();
    }
}