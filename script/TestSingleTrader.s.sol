// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

contract TestSingleTrader is Script {
    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;

    uint256 constant COLLATERAL_DEPOSIT = 30_000 * 1e6; // 30K USDT

    function run() external {
        console.log("=== Testing Single Trader Bot ===");

        // Use first trader bot
        string memory traderKey = "46227d5fa1d8e9d74dadc2133cba57fec4f80e5e2cab6dd4bd49f949619a5449";
        uint256 privateKey = vm.parseUint(string.concat("0x", traderKey));
        address trader = vm.addr(privateKey);

        console.log("Trader address:", trader);

        IERC20 usdt = IERC20(USDT);
        AccountManager accountManager = AccountManager(ACCOUNT_MANAGER);
        ExecutionEngine executionEngine = ExecutionEngine(EXECUTION_ENGINE);

        // Check trader's USDT balance
        uint256 usdtBalance = usdt.balanceOf(trader);
        console.log("USDT balance:", usdtBalance);

        if (usdtBalance < COLLATERAL_DEPOSIT) {
            console.log("ERROR: Insufficient USDT balance");
            return;
        }

        vm.startBroadcast(privateKey);

        // Step 1: Deposit collateral
        console.log("Step 1: Depositing collateral");
        usdt.approve(ACCOUNT_MANAGER, COLLATERAL_DEPOSIT);
        accountManager.deposit(COLLATERAL_DEPOSIT);
        console.log("SUCCESS: Deposited", COLLATERAL_DEPOSIT);

        // Step 2: Check account balance
        uint256 accountBalance = accountManager.getBalance(trader);
        console.log("Account balance:", accountBalance);

        // Step 3: Open position
        console.log("Step 2: Opening position");
        bytes32 marketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1; // SpaceX IPO
        uint256 positionCollateral = 10_000 * 1e6; // 10K USDT

        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: positionCollateral,
            leverage: 3 * 1e18 // 3x leverage
        });

        uint256 positionId = executionEngine.openPosition(params);
        console.log("SUCCESS: Position opened! ID:", positionId);

        vm.stopBroadcast();

        console.log("=== Test Complete ===");
    }
}