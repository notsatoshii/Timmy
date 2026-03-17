// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/IPositionManager.sol";

contract OpenMaxLeveragePositions is Script {

    // Long-dated markets from demo_markets.json (>90 days to resolution)
    bytes32 constant SPACEX_IPO = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
    bytes32 constant SPACEX_ACKMAN = 0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2;
    bytes32 constant NOTHING_HAPPENS = 0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d;
    bytes32 constant FED_RATE = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
    bytes32 constant OPENSEA_TOKEN = 0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc;

    // WAD constants
    uint256 constant WAD = 1e18;

    function run() external {
        IExecutionEngine executionEngine = IExecutionEngine(vm.envAddress("EXECUTION_ENGINE"));
        IPositionManager positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER"));

        uint256 testWalletKey;
        string memory keyStr = vm.envString("TEST_WALLET_KEY");
        if (bytes(keyStr).length == 64) {
            // Raw hex string without 0x prefix
            testWalletKey = vm.parseUint(string.concat("0x", keyStr));
        } else {
            // Has 0x prefix
            testWalletKey = vm.parseUint(keyStr);
        }

        vm.startBroadcast(testWalletKey);

        console2.log("=== Opening High-Leverage Positions ===");
        console2.log("Test wallet:", msg.sender);

        // Position 1: SpaceX IPO - 10x leverage with 100 USDT
        IExecutionEngine.OpenParams memory params1 = IExecutionEngine.OpenParams({
            marketId: SPACEX_IPO,
            isLong: true,
            collateral: 100 * WAD, // 100 USDT in WAD format
            leverage: 10 * WAD      // 10x leverage
        });
        uint256 positionId1 = executionEngine.openPosition(params1);
        console2.log("Position 1 opened: ID =", positionId1, "| SpaceX IPO | 10x leverage");

        // Position 2: SpaceX via Ackman - 15x leverage with 100 USDT
        IExecutionEngine.OpenParams memory params2 = IExecutionEngine.OpenParams({
            marketId: SPACEX_ACKMAN,
            isLong: true,
            collateral: 100 * WAD, // 100 USDT
            leverage: 15 * WAD      // 15x leverage
        });
        uint256 positionId2 = executionEngine.openPosition(params2);
        console2.log("Position 2 opened: ID =", positionId2, "| SpaceX Ackman | 15x leverage");

        // Position 3: Nothing Ever Happens - 20x leverage with 50 USDT
        IExecutionEngine.OpenParams memory params3 = IExecutionEngine.OpenParams({
            marketId: NOTHING_HAPPENS,
            isLong: false, // Short position for diversity
            collateral: 50 * WAD,  // 50 USDT
            leverage: 20 * WAD     // 20x leverage
        });
        uint256 positionId3 = executionEngine.openPosition(params3);
        console2.log("Position 3 opened: ID =", positionId3, "| Nothing Happens | 20x leverage");

        // Position 4: Fed Rate - 25x leverage with 40 USDT
        IExecutionEngine.OpenParams memory params4 = IExecutionEngine.OpenParams({
            marketId: FED_RATE,
            isLong: true,
            collateral: 40 * WAD,  // 40 USDT
            leverage: 25 * WAD     // 25x leverage
        });
        uint256 positionId4 = executionEngine.openPosition(params4);
        console2.log("Position 4 opened: ID =", positionId4, "| Fed Rate | 25x leverage");

        // Position 5: OpenSea Token - 30x leverage with 30 USDT
        IExecutionEngine.OpenParams memory params5 = IExecutionEngine.OpenParams({
            marketId: OPENSEA_TOKEN,
            isLong: false, // Short position for diversity
            collateral: 30 * WAD,  // 30 USDT
            leverage: 30 * WAD     // 30x leverage
        });
        uint256 positionId5 = executionEngine.openPosition(params5);
        console2.log("Position 5 opened: ID =", positionId5, "| OpenSea Token | 30x leverage");

        vm.stopBroadcast();

        console2.log("");
        console2.log("All 5 high-leverage positions opened successfully!");
        console2.log("Position IDs:", positionId1, positionId2, positionId3);
        console2.log("Position IDs cont:", positionId4, positionId5);
        console2.log("Use 'cast call $POSITION_MANAGER getPosition(uint256)' to verify leverage levels");
    }
}