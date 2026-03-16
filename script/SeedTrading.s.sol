// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExecutionEngine} from "../contracts/interfaces/IExecutionEngine.sol";
import {IAccountManager} from "../contracts/interfaces/IAccountManager.sol";
import {IMarketRegistry} from "../contracts/interfaces/IMarketRegistry.sol";
import {MockUSDT} from "../contracts/periphery/MockUSDT.sol";

/**
 * @title SeedTrading
 * @notice Seed trading activity across demo markets
 * @dev Opens realistic leveraged positions on all 10 demo markets (3x-15x leverage range)
 */
contract SeedTrading is Script {

    // Deployed contract addresses
    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant MARKET_REGISTRY = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;

    // Trading parameters
    uint256 constant MIN_POSITION_SIZE = 100e6; // $100 USDT (6 decimals)
    uint256 constant MAX_POSITION_SIZE = 2000e6; // $2000 USDT
    uint256 constant MAX_LEVERAGE = 10e18; // 10x leverage

    // Market IDs for demo markets
    bytes32[] public marketIds;
    string[] public marketNames;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address trader = vm.addr(deployerPrivateKey);

        console2.log("=== LEVER Protocol Trading Seeding ===");
        console2.log("Trader address:", trader);

        // Load market IDs from registry
        _loadMarketIds();

        vm.startBroadcast(deployerPrivateKey);

        // Get USDT for trading
        console2.log("\n1. Getting USDT from faucet...");
        _fundTrader(trader);

        // Deposit USDT to AccountManager
        console2.log("\n2. Depositing USDT to AccountManager...");
        _depositToAccount(trader);

        // Open positions across markets
        console2.log("\n3. Opening positions across markets...");
        _openPositions();

        vm.stopBroadcast();

        console2.log("");
        console2.log("==> Trading seeding complete!");
        console2.log("Opened positions across", marketIds.length, "demo markets");
    }

    function _loadMarketIds() internal {
        // These are the EXACT market names from demo_markets.json
        marketNames.push("Largest IPO by Market Cap 2026: SpaceX?");
        marketNames.push("US-Iran Ceasefire by April 30, 2026?");
        marketNames.push("Nothing Ever Happens: 2026");
        marketNames.push("2026 FIFA World Cup Winner: Spain?");
        marketNames.push("Fed Rate End of 2026: Below 4%?");
        marketNames.push("SpaceX IPO via Ackman SPAR?");
        marketNames.push("AAPL Above $250 in April 2026?");
        marketNames.push("OpenSea Token Launch by 2026?");
        marketNames.push("Fed April 2026: Rate Cut?");
        marketNames.push("Argentina USD Rate Above 1500 ARS End of 2026?");

        // Convert names to market IDs using SHA256 hash (same as Python script)
        for (uint256 i = 0; i < marketNames.length; i++) {
            bytes32 marketId = sha256(bytes(marketNames[i]));
            marketIds.push(marketId);
        }

        console2.log("Loaded", marketIds.length, "demo markets");
    }

    function _fundTrader(address trader) internal {
        MockUSDT usdt = MockUSDT(USDT);
        uint256 initialBalance = usdt.balanceOf(trader);

        // Only call faucet if balance is insufficient
        if (initialBalance < 10000e6) { // Need at least 10K USDT for realistic trading
            usdt.faucet();
        }

        uint256 newBalance = usdt.balanceOf(trader);
        console2.log("USDT balance:", newBalance / 1e6, "USDT");
    }

    function _depositToAccount(address trader) internal {
        IERC20 usdt = IERC20(USDT);
        IAccountManager accountManager = IAccountManager(ACCOUNT_MANAGER);

        uint256 depositAmount = 8000e6; // $8000 USDT (increased for larger positions)

        // Approve and deposit
        usdt.approve(ACCOUNT_MANAGER, depositAmount);
        accountManager.deposit(depositAmount);

        uint256 balance = accountManager.getBalance(trader);
        console2.log("AccountManager balance:", balance / 1e6, "USDT");
    }

    function _openPositions() internal {
        IExecutionEngine executionEngine = IExecutionEngine(EXECUTION_ENGINE);

        // Open positions on all 10 markets for realistic trading activity
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];

            // Vary position parameters for realistic trading activity
            uint256 collateral;
            uint256 leverage;
            uint8 direction;

            // Realistic position sizes and leverage for demo (vary across all 10 markets)
            if (i % 5 == 0) {
                // Conservative positions
                collateral = 600e6; // $600 USDT (6 decimals)
                leverage = 3e18;    // 3x leverage
                direction = 0;      // LONG
            } else if (i % 5 == 1) {
                // Moderate positions
                collateral = 400e6; // $400 USDT (6 decimals)
                leverage = 5e18;    // 5x leverage
                direction = 1;      // SHORT
            } else if (i % 5 == 2) {
                // Aggressive positions
                collateral = 300e6; // $300 USDT (6 decimals)
                leverage = 8e18;    // 8x leverage
                direction = 0;      // LONG
            } else if (i % 5 == 3) {
                // High leverage positions
                collateral = 200e6; // $200 USDT (6 decimals)
                leverage = 12e18;   // 12x leverage
                direction = 1;      // SHORT
            } else {
                // Maximum leverage positions
                collateral = 150e6; // $150 USDT (6 decimals)
                leverage = 15e18;   // 15x leverage
                direction = 0;      // LONG
            }

            console2.log("\nOpening position on market:", i);
            console2.log("  Direction:", direction == 0 ? "LONG" : "SHORT");
            console2.log("  Collateral:", collateral / 1e18, "USDT");
            console2.log("  Leverage:", leverage / 1e18, "x");

            IExecutionEngine.OpenParams memory params = IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: direction == 0,
                collateral: collateral,
                leverage: leverage
            });

            uint256 positionId = executionEngine.openPosition(params);

            console2.log("  ==> Position opened:", positionId);
        }
    }
}