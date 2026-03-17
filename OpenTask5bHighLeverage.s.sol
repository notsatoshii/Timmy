// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/core/PositionManager.sol";
import "./contracts/core/AccountManager.sol";
import "./contracts/LeverageModelFixed.sol";

contract OpenTask5bHighLeverage is Script {

    // Demo markets from demo_markets.json
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant US_IRAN = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
    bytes32 constant FIFA_SPAIN = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
    bytes32 constant FED_RATE = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554;
    bytes32 constant ARGENTINA = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea;

    struct OpenParams {
        bytes32 marketId;
        bool isLong;
        uint256 collateral;
        uint256 leverage;
    }

    function run() external {
        string memory testWalletKeyHex = vm.envString("TEST_WALLET_KEY");
        uint256 testWalletKey = vm.parseUint(string.concat("0x", testWalletKeyHex));
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address accountManager = vm.envAddress("ACCOUNT_MANAGER");
        address leverageModel = vm.envAddress("LEVERAGE_MODEL");

        AccountManager am = AccountManager(accountManager);
        LeverageModelFixed lm = LeverageModelFixed(leverageModel);

        // Check available leverage for each market
        uint256 spacexMaxLev = lm.getEffectiveMaxLeverage(SPACEX_IPO);
        uint256 usIranMaxLev = lm.getEffectiveMaxLeverage(US_IRAN);
        uint256 fifaMaxLev = lm.getEffectiveMaxLeverage(FIFA_SPAIN);
        uint256 fedMaxLev = lm.getEffectiveMaxLeverage(FED_RATE);
        uint256 argMaxLev = lm.getEffectiveMaxLeverage(ARGENTINA);

        console.log("=== AVAILABLE MAX LEVERAGE ===");
        console.log("SpaceX max leverage:", spacexMaxLev / 1e18, "x");
        console.log("US-Iran max leverage:", usIranMaxLev / 1e18, "x");
        console.log("FIFA Spain max leverage:", fifaMaxLev / 1e18, "x");
        console.log("Fed Rate max leverage:", fedMaxLev / 1e18, "x");
        console.log("Argentina max leverage:", argMaxLev / 1e18, "x");
        console.log("");

        // Open positions using 95% of max leverage to avoid rounding issues
        OpenParams[] memory positions = new OpenParams[](5);

        // Use slightly less than max to avoid edge case failures
        uint256 spacexLev = (spacexMaxLev * 95) / 100;  // 95% of max
        uint256 usIranLev = (usIranMaxLev * 95) / 100;
        uint256 fifaLev = (fifaMaxLev * 95) / 100;
        uint256 fedLev = (fedMaxLev * 95) / 100;
        uint256 argLev = (argMaxLev * 95) / 100;

        // Position 1: Long SpaceX
        positions[0] = OpenParams(SPACEX_IPO, true, 500_000000, spacexLev);

        // Position 2: Long US-Iran (highest leverage available)
        positions[1] = OpenParams(US_IRAN, true, 400_000000, usIranLev);

        // Position 3: Long FIFA Spain
        positions[2] = OpenParams(FIFA_SPAIN, true, 300_000000, fifaLev);

        // Position 4: Short Fed Rate
        positions[3] = OpenParams(FED_RATE, false, 300_000000, fedLev);

        // Position 5: Long Argentina
        positions[4] = OpenParams(ARGENTINA, true, 200_000000, argLev);

        vm.startBroadcast(testWalletKey);

        // Check test wallet balance first
        uint256 balance = am.getBalance(vm.addr(testWalletKey));
        console.log("Test wallet balance:", balance / 1e6, "USDT");
        console.log("");

        for (uint256 i = 0; i < positions.length; i++) {
            OpenParams memory params = positions[i];

            console.log("Opening position", i + 1);
            console.log("  Market:", vm.toString(params.marketId));
            console.log("  Direction:", params.isLong ? "LONG" : "SHORT");
            console.log("  Collateral:", params.collateral / 1e6, "USDT");
            console.log("  Leverage:", params.leverage / 1e18, "x");

            // Open position
            (bool success,) = executionEngine.call(
                abi.encodeWithSignature(
                    "openPosition((bytes32,bool,uint256,uint256))",
                    params
                )
            );

            if (success) {
                console.log("  SUCCESS");
            } else {
                console.log("  FAILED");
            }
            console.log("---");
        }

        vm.stopBroadcast();
    }
}

