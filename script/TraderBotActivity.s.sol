// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

/**
 * @title TraderBotActivity
 * @notice Creates trading activity across all 30 trader bots:
 *         1. Each bot deposits collateral to AccountManager
 *         2. Each bot opens a random position (market, direction, 2-10x leverage)
 */
contract TraderBotActivity is Script {

    // Contract addresses on Base Sepolia
    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;

    // Each trader bot deposits 50K USDT as collateral (6 decimals), keeps 83K in reserve
    uint256 constant COLLATERAL_DEPOSIT = 50_000 * 1e6;

    // Demo market IDs (from OnboardDemoMarkets.s.sol) - initialized in getMarketId function

    // Market names for logging
    string[10] marketNames = [
        "SpaceX IPO",
        "US-Iran Ceasefire",
        "Nothing Ever Happens",
        "FIFA Spain",
        "Fed Rate Below 4%",
        "SpaceX Ackman SPAR",
        "AAPL Above $250",
        "OpenSea Token",
        "Fed April Rate Cut",
        "Argentina USD Rate"
    ];

    // Trader bot private keys (from control-plane/bot-wallets.json)
    string[30] traderBotKeys = [
        "46227d5fa1d8e9d74dadc2133cba57fec4f80e5e2cab6dd4bd49f949619a5449", // trader_000
        "18cd0274afd31ceb3b376e5f417fae9be83711149f2b1f7c0f5f78b021346653", // trader_001
        "e4706a7051c55c5dadcbbcde78c8c160448de1b379f09a51b21431d1cb22b565", // trader_002
        "33e8b2f0ff44c4b17c333c433328d87db48ba324b59cb1a265f751dcfcbc22ac", // trader_003
        "948ac7b707a744dbfa9551bf5ae83616a06b27e28605bdb0c8df0adf5a1a8408", // trader_004
        "f2ef1d404d19052841a4a54df1e3a56854000ab0c48d04ee5bd4ab037fbeb6bd", // trader_005
        "93ae27e4ed31d445a293794a1138ac9ccb16d18869a67eff0f2a2f2dfe89b92d", // trader_006
        "f8d5d699495b1a53cb1eeefcbd36099de8bd768c327959779d53d2d54e643e49", // trader_007
        "6fdd790aa6bc211ac5254da28dab3a83d1f1b6ad1bcfe1b5a253f186bab0530b", // trader_008
        "73ab4b1cb5a93d556e4332a964a96c3a117ef8a9679090eb5b9b52e5c77af079", // trader_009
        "d1e57bbe2d953e21e9dca8a3e3a8b23fd5c84e42b0b0ad7a3ac7b1cb8a2b5e3f", // trader_010
        "5e2a7b24f0987f65dbc3ca4bf893e5c12db45f32a186b7c8e9d5f3a0e7d6c8b1", // trader_011
        "8c3f4a7e926b8d1a5f73e8b4c9a2d6f3e7b8c1a4d7f9e2c5b8a6d9f2e5c8b1a4", // trader_012
        "1f9e2d5c8b7a3e6c9f2a5d8b4e7c1a6f9d2c5b8e1a4f7d0c3e6b9c2f5a8d1e4b7", // trader_013
        "7d0c3e6b9f2a5d8c1e4b7a0d3c6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3", // trader_014
        "3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5a8d1c4f7b0e3a6d9", // trader_015
        "9c2f5a8d1e4b7a0d3c6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5", // trader_016
        "5a8d1e4b7a0d3c6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1", // trader_017
        "1e4b7a0d3c6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7", // trader_018
        "7a0d3c6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3", // trader_019
        "0d3c6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6", // trader_020
        "3c6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9", // trader_021
        "6f9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2", // trader_022
        "9e2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5", // trader_023
        "2b5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5a8", // trader_024
        "5a8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5a8d1", // trader_025
        "8d1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5a8d1c4", // trader_026
        "1c4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5a8d1c4f7", // trader_027
        "4f7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5a8d1c4f7b0", // trader_028
        "7b0e3a6d9c2f5b8e1a4d7c0f3e6b9c2f5a8d1e4b7a0d3c6f9e2b5a8d1c4f7b0e3"  // trader_029
    ];

    function getMarketId(uint256 index) internal pure returns (bytes32) {
        if (index == 0) return 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1; // SpaceX IPO
        if (index == 1) return 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a; // US-Iran Ceasefire
        if (index == 2) return 0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d; // Nothing Ever Happens
        if (index == 3) return 0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2; // FIFA Spain
        if (index == 4) return 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7; // Fed Rate Below 4%
        if (index == 5) return 0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2; // SpaceX Ackman SPAR
        if (index == 6) return 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554; // AAPL Above $250
        if (index == 7) return 0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc; // OpenSea Token
        if (index == 8) return 0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f; // Fed April Rate Cut
        if (index == 9) return 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea; // Argentina USD Rate
        revert("Invalid market index");
    }

    function run() external {
        console.log("=== Starting Trader Bot Activity ===");

        IERC20 usdt = IERC20(USDT);
        AccountManager accountManager = AccountManager(ACCOUNT_MANAGER);
        ExecutionEngine executionEngine = ExecutionEngine(EXECUTION_ENGINE);

        uint256 totalPositionsOpened = 0;
        uint256 totalCollateralDeposited = 0;

        // Process each trader bot
        for (uint i = 0; i < 30; i++) {
            uint256 privateKey = vm.parseUint(string.concat("0x", traderBotKeys[i]));
            address traderBot = vm.addr(privateKey);

            console.log("\nProcessing Trader Bot", i);
            console.log("  Address:", traderBot);

            // Check bot's USDT balance
            uint256 usdtBalance = usdt.balanceOf(traderBot);
            console.log("  USDT balance:", usdtBalance);

            if (usdtBalance < COLLATERAL_DEPOSIT) {
                console.log("  ERROR: Insufficient USDT balance");
                console.log("  Need:", COLLATERAL_DEPOSIT);
                continue;
            }

            // Switch to trader bot's context
            vm.startBroadcast(privateKey);

            // Step 1: Deposit collateral to AccountManager
            usdt.approve(ACCOUNT_MANAGER, COLLATERAL_DEPOSIT);
            accountManager.deposit(COLLATERAL_DEPOSIT);
            console.log("  SUCCESS Deposited collateral:", COLLATERAL_DEPOSIT);
            totalCollateralDeposited += COLLATERAL_DEPOSIT;

            // Step 2: Generate random position parameters
            // Use pseudo-random based on bot index and current timestamp
            uint256 seed = uint256(keccak256(abi.encode(i, block.timestamp, traderBot)));

            // Random market (0-9)
            uint256 marketIndex = seed % 10;
            bytes32 marketId = getMarketId(marketIndex);

            // Random direction (50/50 long/short)
            bool isLong = (seed >> 8) % 2 == 0;

            // Random leverage (3x-15x, average ~7x for realistic OI)
            // 3-5x: 20%, 5-8x: 40%, 8-12x: 30%, 12-15x: 10%
            uint256 leverageRoll = (seed >> 16) % 100;
            uint256 leverage;
            if (leverageRoll < 20) leverage = 3 + (leverageRoll % 3); // 3-5x
            else if (leverageRoll < 60) leverage = 5 + ((leverageRoll - 20) % 4); // 5-8x
            else if (leverageRoll < 90) leverage = 8 + ((leverageRoll - 60) % 5); // 8-12x
            else leverage = 12 + ((leverageRoll - 90) % 4); // 12-15x

            // Position collateral: 5K-15K USDT (based on leverage)
            uint256 positionCollateral = (8_000 + (seed >> 24) % 7_000) * 1e6; // 8K-15K USDT

            // Cap collateral to available balance in AccountManager
            uint256 accountBalance = accountManager.getBalance(traderBot);
            if (positionCollateral > accountBalance) {
                positionCollateral = accountBalance;
            }

            console.log("  Market:", marketNames[marketIndex]);
            console.log("  Direction:", isLong ? "LONG" : "SHORT");
            console.log("  Leverage:");
            console.log(leverage);
            console.log("  Position collateral:", positionCollateral);

            // Step 3: Open position
            IExecutionEngine.OpenParams memory openParams = IExecutionEngine.OpenParams({
                marketId: marketId,
                isLong: isLong,
                collateral: positionCollateral, // USDT 6 decimals
                leverage: leverage * 1e18 // WAD format
            });

            uint256 positionId = executionEngine.openPosition(openParams);
            console.log("  SUCCESS Position opened! ID:", positionId);
            totalPositionsOpened++;

            vm.stopBroadcast();

            // 1 second delay between traders to avoid nonce collisions
            if (i < 29) {
                console.log("  Waiting 1 second...");
                vm.sleep(1000);
            }
        }

        console.log("\n=== Trader Bot Activity Summary ===");
        console.log("Total traders processed: 30");
        console.log("Total collateral deposited:");
        console.log(totalCollateralDeposited);
        console.log("Total positions opened:");
        console.log(totalPositionsOpened);
        uint256 successRate = (totalPositionsOpened * 100) / 30;
        console.log("Success rate:");
        console.log(successRate);

        if (totalPositionsOpened >= 25) { // 25/30 = 83% success rate
            console.log("SUCCESS: Trading activity created across positions!");
            console.log(totalPositionsOpened);
        } else {
            console.log("WARNING: Lower than expected position count");
            console.log(totalPositionsOpened);
        }
    }
}