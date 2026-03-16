// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExecutionEngine} from "../contracts/interfaces/IExecutionEngine.sol";
import {IAccountManager} from "../contracts/interfaces/IAccountManager.sol";
import {MockUSDT} from "../contracts/periphery/MockUSDT.sol";

contract TestTrading is Script {
    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address trader = vm.addr(deployerPrivateKey);

        // SpaceX market ID
        bytes32 marketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        console2.log("=== Test Trading with Larger Position ===");
        console2.log("Trader:", trader);

        vm.startBroadcast(deployerPrivateKey);

        // Check current balance
        IAccountManager accountManager = IAccountManager(ACCOUNT_MANAGER);
        uint256 balance = accountManager.getBalance(trader);
        console2.log("AccountManager balance:", balance / 1e18, "USDT");

        // Open larger position: 100 USDT, 2x leverage
        IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
            marketId: marketId,
            isLong: true,
            collateral: 100e18,  // 100 USDT in WAD
            leverage: 2e18       // 2x leverage
        });

        console2.log("Opening position:");
        console2.log("  Market: SpaceX IPO");
        console2.log("  Direction: LONG");
        console2.log("  Collateral:", params.collateral / 1e18, "USDT");
        console2.log("  Leverage:", params.leverage / 1e18, "x");

        IExecutionEngine executionEngine = IExecutionEngine(EXECUTION_ENGINE);
        uint256 positionId = executionEngine.openPosition(params);

        console2.log("==> Position opened:", positionId);

        vm.stopBroadcast();
    }
}