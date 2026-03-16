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
 * @dev Opens positions on multiple markets with varying sizes and leverage
 */
contract SeedTrading is Script {

    // Deployed contract addresses
    address constant USDT = 0xf846E395219200cAeB12e802349EC67fecB28Ea8;
    address constant EXECUTION_ENGINE = 0x913aAf91bf11A281f74BF5A47a05b44Ad1E123E4;
    address constant ACCOUNT_MANAGER = 0xdA4163d7b04eE74016962A3AB121fcb103041709;
    address constant MARKET_REGISTRY = 0x89398FECE023cDD8c53eFD9a7C68a227eA139e1E;

    // Trading parameters
    uint256 constant MIN_POSITION_SIZE = 100e6; // $100 USDT (6 decimals)
    uint256 constant MAX_POSITION_SIZE = 2000e6; // $2000 USDT
    uint256 constant MAX_LEVERAGE = 10e18; // 10x leverage

    // Market IDs for demo markets
    bytes32[] public marketIds;
    string[] public marketNames;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
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

        // Call faucet to get USDT
        usdt.faucet();

        uint256 newBalance = usdt.balanceOf(trader);
        console2.log("USDT balance:", (newBalance - initialBalance) / 1e6, "USDT");
    }

    function _depositToAccount(address trader) internal {
        IERC20 usdt = IERC20(USDT);
        IAccountManager accountManager = IAccountManager(ACCOUNT_MANAGER);

        uint256 depositAmount = 5000e6; // $5000 USDT

        // Approve and deposit
        usdt.approve(ACCOUNT_MANAGER, depositAmount);
        accountManager.deposit(depositAmount);

        uint256 balance = accountManager.getBalance(trader);
        console2.log("AccountManager balance:", balance / 1e6, "USDT");
    }

    function _openPositions() internal {
        IExecutionEngine executionEngine = IExecutionEngine(EXECUTION_ENGINE);

        // Open positions on first 5 markets to demonstrate trading activity
        for (uint256 i = 0; i < 5 && i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];

            // Vary position parameters for realistic activity
            uint256 collateral;
            uint256 leverage;
            uint8 direction;

            if (i % 2 == 0) {
                // Even markets: smaller positions, higher leverage, long bias
                collateral = 50e18; // $50 USDT (converted to WAD)
                leverage = 5e18;    // 5x leverage
                direction = 0;      // LONG
            } else {
                // Odd markets: larger positions, lower leverage, short bias
                collateral = 100e18; // $100 USDT (converted to WAD)
                leverage = 3e18;     // 3x leverage
                direction = 1;       // SHORT
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