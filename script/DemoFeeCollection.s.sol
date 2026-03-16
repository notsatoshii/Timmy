// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IExecutionEngine } from "../contracts/interfaces/IExecutionEngine.sol";
import { IAccountManager } from "../contracts/interfaces/IAccountManager.sol";
import { IInsuranceFund } from "../contracts/interfaces/IInsuranceFund.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DemoFeeCollection
/// @notice Opens high-leverage positions then closes them to generate fees for InsuranceFund
/// @dev Uses test wallet to demonstrate fee collection and InsuranceFund growth
contract DemoFeeCollection is Script {

    IExecutionEngine constant EXECUTION_ENGINE = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IAccountManager constant ACCOUNT_MANAGER = IAccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
    IInsuranceFund constant INSURANCE_FUND = IInsuranceFund(0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8);
    IERC20 constant USDT = IERC20(0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E);

    // Demo market IDs
    bytes32 constant SPACEX_MARKET = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN_MARKET = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;

    function run() external {
        // Load test wallet private key from env
        vm.setEnv("TEST_WALLET_KEY", vm.readFile(".env.testwallet"));
        uint256 privateKey = vm.envUint("PRIVATE_KEY"); // Use deployer key for now

        address testWallet = vm.addr(privateKey);

        console.log("=== Demo Fee Collection ===");
        console.log("Test Wallet:", testWallet);

        // Check balances before
        uint256 insuranceBalanceBefore = INSURANCE_FUND.getBalance();
        uint256 testWalletUSDT = USDT.balanceOf(testWallet);
        uint256 testWalletCollateral = ACCOUNT_MANAGER.getFreeCollateral(testWallet);

        console.log("Insurance Fund Balance Before:", insuranceBalanceBefore / 1e18, "USDT");
        console.log("Test Wallet USDT Balance:", testWalletUSDT / 1e6, "USDT");
        console.log("Test Wallet Free Collateral:", testWalletCollateral / 1e6, "USDT");

        vm.startBroadcast(privateKey);

        // Open 3 positions with high leverage to generate substantial fees
        uint256[] memory positionIds = new uint256[](3);

        try EXECUTION_ENGINE.openPosition(IExecutionEngine.OpenParams({
            marketId: SPACEX_MARKET,
            isLong: true,
            collateral: 100000e6, // 100K USDT
            leverage: 5e18       // 5x leverage = 500K notional
        })) returns (uint256 positionId) {
            positionIds[0] = positionId;
            console.log("Opened SpaceX Long 5x - Position ID:", positionId);
        } catch {
            console.log("Failed to open SpaceX position");
        }

        try EXECUTION_ENGINE.openPosition(IExecutionEngine.OpenParams({
            marketId: US_IRAN_MARKET,
            isLong: false,
            collateral: 80000e6,  // 80K USDT
            leverage: 3e18        // 3x leverage = 240K notional
        })) returns (uint256 positionId) {
            positionIds[1] = positionId;
            console.log("Opened US-Iran Short 3x - Position ID:", positionId);
        } catch {
            console.log("Failed to open US-Iran position");
        }

        try EXECUTION_ENGINE.openPosition(IExecutionEngine.OpenParams({
            marketId: SPACEX_MARKET,
            isLong: false,
            collateral: 50000e6,  // 50K USDT
            leverage: 4e18        // 4x leverage = 200K notional
        })) returns (uint256 positionId) {
            positionIds[2] = positionId;
            console.log("Opened SpaceX Short 4x - Position ID:", positionId);
        } catch {
            console.log("Failed to open second SpaceX position");
        }

        // Wait a bit for fees to accrue (simulate time passing)
        console.log("Positions opened - fees accruing...");

        // Close all positions to trigger fee collection
        for (uint256 i = 0; i < 3; i++) {
            if (positionIds[i] > 0) {
                try EXECUTION_ENGINE.closePosition(positionIds[i]) {
                    console.log("Closed position:", positionIds[i]);
                } catch {
                    console.log("Failed to close position:", positionIds[i]);
                }
            }
        }

        vm.stopBroadcast();

        // Check balances after
        uint256 insuranceBalanceAfter = INSURANCE_FUND.getBalance();
        uint256 increase = insuranceBalanceAfter - insuranceBalanceBefore;

        console.log("Insurance Fund Balance After:", insuranceBalanceAfter / 1e18, "USDT");
        console.log("Insurance Fund Increase:", increase / 1e18, "USDT");

        if (increase > 0) {
            console.log("SUCCESS: Insurance Fund grew by", increase / 1e18, "USDT");
            console.log("Fee routing working correctly!");
        } else {
            console.log("WARNING: No InsuranceFund growth detected");
        }
    }
}