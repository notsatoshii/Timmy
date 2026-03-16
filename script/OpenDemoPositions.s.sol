// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

/**
 * @title OpenDemoPositions
 * @notice Open 3 demo positions via test wallet for investor demo:
 *         1. Long SpaceX IPO 5x leverage
 *         2. Short US-Iran Ceasefire 3x leverage
 *         3. Long Fed Rate Below 4% 2x leverage
 */
contract OpenDemoPositions is Script {

    function run() external {
        // Get contract addresses from environment
        address executionEngineAddr = vm.envAddress("EXECUTION_ENGINE");
        ExecutionEngine executionEngine = ExecutionEngine(executionEngineAddr);

        // Use test wallet key
        string memory testKeyString = vm.envString("TEST_WALLET_KEY");
        uint256 testKey = vm.parseUint(string(abi.encodePacked("0x", testKeyString)));

        // Market IDs (from OnboardDemoMarkets.s.sol deployment)
        bytes32 spacexMarket = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        bytes32 iranMarket = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
        bytes32 fedMarket = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;

        console.log("=== Opening Demo Positions ===");
        console.log("SpaceX market ID:", vm.toString(spacexMarket));
        console.log("US-Iran market ID:", vm.toString(iranMarket));
        console.log("Fed Rate market ID:", vm.toString(fedMarket));

        vm.startBroadcast(testKey);

        // Position 1: Long SpaceX IPO 2x leverage (reduced from 5x due to market conditions)
        // Collateral: 100 USDT, Size: 200 USDT notional
        console.log("\nOpening Position 1: Long SpaceX IPO 2x");
        IExecutionEngine.OpenParams memory params1 = IExecutionEngine.OpenParams({
            marketId: spacexMarket,
            isLong: true, // direction: true = long
            collateral: 100 * 1e6, // collateral: 100 USDT in 6 decimals (native USDT format)
            leverage: 2 * 1e18 // leverage: 2x in WAD
        });
        uint256 positionId1 = executionEngine.openPosition(params1);
        console.log("Position 1 ID:", positionId1);

        // Position 2: Short US-Iran Ceasefire 2x leverage (reduced from 3x due to market conditions)
        // Collateral: 150 USDT, Size: 300 USDT notional
        console.log("\nOpening Position 2: Short US-Iran Ceasefire 2x");
        IExecutionEngine.OpenParams memory params2 = IExecutionEngine.OpenParams({
            marketId: iranMarket,
            isLong: false, // direction: false = short
            collateral: 150 * 1e6, // collateral: 150 USDT in 6 decimals (native USDT format)
            leverage: 2 * 1e18 // leverage: 2x in WAD
        });
        uint256 positionId2 = executionEngine.openPosition(params2);
        console.log("Position 2 ID:", positionId2);

        // Position 3: Long Fed Rate Below 4% 2x leverage
        // Collateral: 200 USDT, Size: 400 USDT notional
        console.log("\nOpening Position 3: Long Fed Rate Below 4% 2x");
        IExecutionEngine.OpenParams memory params3 = IExecutionEngine.OpenParams({
            marketId: fedMarket,
            isLong: true, // direction: true = long
            collateral: 200 * 1e6, // collateral: 200 USDT in 6 decimals (native USDT format)
            leverage: 2 * 1e18 // leverage: 2x in WAD
        });
        uint256 positionId3 = executionEngine.openPosition(params3);
        console.log("Position 3 ID:", positionId3);

        vm.stopBroadcast();

        console.log("\n=== Demo Positions Summary ===");
        console.log("Position 1 (Long SpaceX 5x):", positionId1);
        console.log("Position 2 (Short US-Iran 3x):", positionId2);
        console.log("Position 3 (Long Fed Rate 2x):", positionId3);
        console.log("\nDemo positions opened successfully!");
    }
}