// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/interfaces/IExecutionEngine.sol";

/**
 * @title Open5TestPositions
 * @notice Open 5 test positions across different markets using test wallet
 */
contract Open5TestPositions is Script {

    function run() external {
        // Get contract addresses from environment
        address executionEngineAddr = vm.envAddress("EXECUTION_ENGINE");
        ExecutionEngine executionEngine = ExecutionEngine(executionEngineAddr);

        // Use test wallet key
        string memory testKeyString = vm.envString("TEST_WALLET_KEY");
        uint256 testKey = vm.parseUint(string(abi.encodePacked("0x", testKeyString)));

        // Market IDs (from OnboardDemoMarkets broadcast logs)
        bytes32 spacexMarket = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1; // SpaceX IPO
        bytes32 iranMarket = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a; // US-Iran Ceasefire
        bytes32 fedMarket = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7; // Fed Rate
        bytes32 aaplMarket = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554; // AAPL Above $250
        bytes32 argentinaMarket = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea; // Argentina USD

        console.log("=== Opening 5 Test Positions ===");

        vm.startBroadcast(testKey);

        // Position 1: Long SpaceX IPO 1.5x leverage (reduced to match max allowed)
        console.log("\nOpening Position 1: Long SpaceX IPO 1.5x");
        IExecutionEngine.OpenParams memory params1 = IExecutionEngine.OpenParams({
            marketId: spacexMarket,
            isLong: true,
            collateral: 100 * 1e6, // 100 USDT
            leverage: 15 * 1e17 // 1.5x
        });
        uint256 positionId1 = executionEngine.openPosition(params1);
        console.log("Position 1 ID:", positionId1);

        // Position 2: Short US-Iran Ceasefire 1.5x leverage
        console.log("\nOpening Position 2: Short US-Iran Ceasefire 1.5x");
        IExecutionEngine.OpenParams memory params2 = IExecutionEngine.OpenParams({
            marketId: iranMarket,
            isLong: false,
            collateral: 150 * 1e6, // 150 USDT
            leverage: 15 * 1e17 // 1.5x
        });
        uint256 positionId2 = executionEngine.openPosition(params2);
        console.log("Position 2 ID:", positionId2);

        // Position 3: Long Fed Rate Below 4% 1.5x leverage
        console.log("\nOpening Position 3: Long Fed Rate Below 4% 1.5x");
        IExecutionEngine.OpenParams memory params3 = IExecutionEngine.OpenParams({
            marketId: fedMarket,
            isLong: true,
            collateral: 200 * 1e6, // 200 USDT
            leverage: 15 * 1e17 // 1.5x
        });
        uint256 positionId3 = executionEngine.openPosition(params3);
        console.log("Position 3 ID:", positionId3);

        // Position 4: Long AAPL Above $250 1.5x leverage
        console.log("\nOpening Position 4: Long AAPL Above $250 1.5x");
        IExecutionEngine.OpenParams memory params4 = IExecutionEngine.OpenParams({
            marketId: aaplMarket,
            isLong: true,
            collateral: 125 * 1e6, // 125 USDT
            leverage: 15 * 1e17 // 1.5x
        });
        uint256 positionId4 = executionEngine.openPosition(params4);
        console.log("Position 4 ID:", positionId4);

        // Position 5: Short Argentina USD Rate 1.5x leverage
        console.log("\nOpening Position 5: Short Argentina USD Rate 1.5x");
        IExecutionEngine.OpenParams memory params5 = IExecutionEngine.OpenParams({
            marketId: argentinaMarket,
            isLong: false,
            collateral: 175 * 1e6, // 175 USDT
            leverage: 15 * 1e17 // 1.5x
        });
        uint256 positionId5 = executionEngine.openPosition(params5);
        console.log("Position 5 ID:", positionId5);

        vm.stopBroadcast();

        console.log("\n=== 5 Test Positions Summary ===");
        console.log("Position 1 (Long SpaceX 1.5x):", positionId1);
        console.log("Position 2 (Short US-Iran 1.5x):", positionId2);
        console.log("Position 3 (Long Fed Rate 1.5x):", positionId3);
        console.log("Position 4 (Long AAPL 1.5x):", positionId4);
        console.log("Position 5 (Short Argentina 1.5x):", positionId5);
        console.log("\n5 test positions opened successfully!");
    }
}