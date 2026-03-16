// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/core/AccountManager.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

/**
 * @title MarketMakerActivity
 * @notice Creates market making activity across all 3 market maker bots:
 *         1. Each MM bot deposits collateral to AccountManager
 *         2. Each MM bot opens positions on BOTH sides of selected markets
 *         3. Uses 5x-10x leverage range for realistic liquidity provision
 *         4. Focuses on top volume markets for maximum impact
 */
contract MarketMakerActivity is Script {

    // Contract addresses on Base Sepolia
    address constant USDT = 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E;
    address constant ACCOUNT_MANAGER = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
    address constant EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;

    // Each MM bot deposits 500K USDT as collateral (6 decimals), keeps 500K in reserve
    uint256 constant COLLATERAL_DEPOSIT = 500_000 * 1e6;

    // MM position sizing - smaller than trader bots but more frequent
    uint256 constant MIN_POSITION_SIZE = 10_000 * 1e6; // 10K USDT
    uint256 constant MAX_POSITION_SIZE = 50_000 * 1e6; // 50K USDT

    // MM leverage range: 5x-10x as specified
    uint256 constant MIN_LEVERAGE = 5;
    uint256 constant MAX_LEVERAGE = 10;

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

    // Top 5 markets for MM activity (highest volume/interest)
    uint256[5] topMarkets = [0, 1, 4, 6, 9]; // SpaceX, US-Iran, Fed Rate, AAPL, Argentina

    // Market maker bot private keys (from control-plane/bot-wallets.json)
    string[3] mmBotKeys = [
        "e650b182e7bc42e68feaf60d34d16095dfb5ebf7562dc71260d8779f13129998", // market_maker_000
        "3ccff497d95ce0a4c042149212d26fd3a7463aa81b8d332f58ca550f52256495", // market_maker_001
        "e2d9519c5f5aa1f261e46d8f58298beb889eef2a8430f505bb01803b4722757c"  // market_maker_002
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

    function generateLeverage(uint256 seed) internal pure returns (uint256) {
        // 5x-10x leverage, weighted toward 7x-8x (middle range)
        uint256 roll = seed % 100;
        if (roll < 20) return 5; // 20%
        if (roll < 35) return 6; // 15%
        if (roll < 55) return 7; // 20%
        if (roll < 75) return 8; // 20%
        if (roll < 90) return 9; // 15%
        return 10; // 10%
    }

    function run() external {
        console.log("=== Starting Market Maker Activity ===");
        console.log("MM bots: 3");
        console.log("Target markets: 5");
        console.log("Leverage range: 5x-10x");
        console.log("Collateral per MM: 500K USDT");

        IERC20 usdt = IERC20(USDT);
        AccountManager accountManager = AccountManager(ACCOUNT_MANAGER);
        ExecutionEngine executionEngine = ExecutionEngine(EXECUTION_ENGINE);

        uint256 totalPositionsOpened = 0;
        uint256 totalCollateralDeposited = 0;

        // Process each market maker bot
        for (uint i = 0; i < 3; i++) {
            uint256 privateKey = vm.parseUint(string.concat("0x", mmBotKeys[i]));
            address mmBot = vm.addr(privateKey);

            console.log("=== Processing Market Maker Bot", i);
            console.log("  Address:", mmBot);

            // Check bot's USDT balance
            uint256 usdtBalance = usdt.balanceOf(mmBot);
            console.log("  USDT balance:", usdtBalance / 1e6);

            if (usdtBalance < COLLATERAL_DEPOSIT) {
                console.log("  ERROR: Insufficient USDT balance");
                console.log("  Need USDT:", COLLATERAL_DEPOSIT / 1e6);
                continue;
            }

            // Switch to MM bot's context
            vm.startBroadcast(privateKey);

            // Step 1: Deposit collateral to AccountManager
            usdt.approve(ACCOUNT_MANAGER, COLLATERAL_DEPOSIT);
            accountManager.deposit(COLLATERAL_DEPOSIT);
            console.log("  SUCCESS Deposited collateral:", COLLATERAL_DEPOSIT / 1e6);
            totalCollateralDeposited += COLLATERAL_DEPOSIT;

            // Step 2: Open positions on both sides of selected markets
            // MM bot i focuses on 2 markets each: MM0=(0,1), MM1=(2,3), MM2=(4,)
            uint256 marketsPerMM = 2;
            if (i == 2) marketsPerMM = 1; // Last MM only gets 1 market

            for (uint j = 0; j < marketsPerMM; j++) {
                uint256 marketIndex = topMarkets[i * 2 + j];
                bytes32 marketId = getMarketId(marketIndex);
                string memory marketName = marketNames[marketIndex];

                console.log("  Market:", marketName);
                console.log("  Market index:", marketIndex);

                // Generate position parameters
                uint256 seed = uint256(keccak256(abi.encode(i, j, block.timestamp, mmBot)));

                // Position size varies by market maker and position
                uint256 baseSize = MIN_POSITION_SIZE + (seed % (MAX_POSITION_SIZE - MIN_POSITION_SIZE));
                uint256 leverage = generateLeverage(seed);
                uint256 collateralNeeded = baseSize / leverage;

                // Check available balance
                uint256 accountBalance = accountManager.getBalance(mmBot);
                if (collateralNeeded > accountBalance / 2) { // Reserve half for second position
                    collateralNeeded = accountBalance / 4; // Use quarter for each side
                }

                console.log("    Leverage:", leverage);
                console.log("    Collateral per side:", collateralNeeded / 1e6);
                console.log("    Notional per side:", (collateralNeeded * leverage) / 1e6);

                // Position 1: LONG side
                IExecutionEngine.OpenParams memory longParams = IExecutionEngine.OpenParams({
                    marketId: marketId,
                    isLong: true,
                    collateral: collateralNeeded,
                    leverage: leverage * 1e18
                });

                try executionEngine.openPosition(longParams) returns (uint256 positionId) {
                    console.log("    SUCCESS LONG position opened! ID:", positionId);
                    totalPositionsOpened++;
                } catch Error(string memory reason) {
                    console.log("    FAILED LONG position:", reason);
                } catch {
                    console.log("    FAILED LONG position: Unknown error");
                }

                // Small delay between sides
                vm.sleep(500);

                // Position 2: SHORT side
                IExecutionEngine.OpenParams memory shortParams = IExecutionEngine.OpenParams({
                    marketId: marketId,
                    isLong: false,
                    collateral: collateralNeeded,
                    leverage: leverage * 1e18
                });

                try executionEngine.openPosition(shortParams) returns (uint256 positionId) {
                    console.log("    SUCCESS SHORT position opened! ID:", positionId);
                    totalPositionsOpened++;
                } catch Error(string memory reason) {
                    console.log("    FAILED SHORT position:", reason);
                } catch {
                    console.log("    FAILED SHORT position: Unknown error");
                }

                // Delay between markets
                if (j < marketsPerMM - 1) {
                    console.log("    Waiting 1 second...");
                    vm.sleep(1000);
                }
            }

            vm.stopBroadcast();

            // Delay between MM bots
            if (i < 2) {
                console.log("  Waiting 2 seconds...");
                vm.sleep(2000);
            }
        }

        console.log("\n=== Market Maker Activity Summary ===");
        console.log("Total MM bots processed: 3");
        console.log("Total collateral deposited:", totalCollateralDeposited / 1e6);
        console.log("Total positions opened:", totalPositionsOpened);
        console.log("Target positions: 10 (5 markets x 2 sides)");

        uint256 successRate = totalPositionsOpened > 0 ? (totalPositionsOpened * 100) / 10 : 0;
        console.log("Success rate %:", successRate);

        if (totalPositionsOpened >= 8) { // 8/10 = 80% success rate
            console.log("SUCCESS: Market making activity created!");
            console.log("Both-sided liquidity provided across markets:", totalPositionsOpened / 2);
        } else {
            console.log("WARNING: Lower than expected position count");
            console.log("Expected 10 positions, got:", totalPositionsOpened);
        }

        // Calculate total notional volume added
        uint256 avgLeverage = 7; // Middle of 5x-10x range
        uint256 avgCollateralPerPosition = 30_000; // ~30K USDT average
        uint256 totalNotional = totalPositionsOpened * avgCollateralPerPosition * avgLeverage;
        console.log("Estimated total notional added USDT:", totalNotional / 1e6);
    }
}