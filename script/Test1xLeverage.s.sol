// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/ILeverageModel.sol";

/// @title Test 1x Leverage Position Opening
/// @notice Test that 1x leverage positions can now be opened (baseline test)
contract Test1xLeverage is Script {

    function run() external {
        vm.startBroadcast();

        console2.log("=== Testing 1x Leverage Position Opening ===");

        // Use the new ExecutionEngine address
        IExecutionEngine executionEngine = IExecutionEngine(0x15a05b36D68e88f3264157dDa034f6C1e666065b);

        // Use SpaceX market for testing
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        // Check max leverage first
        ILeverageModel leverageModel = ILeverageModel(0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF);
        uint256 maxLeverage = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("Max leverage for SpaceX market:", maxLeverage / 1e18, "x");

        // Test 1x leverage (should always work)
        console2.log("\n--- Testing 1x Leverage ---");
        try executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId: spacexMarketId,
            isLong: true,
            collateral: 100e6, // 100 USDT
            leverage: 1e18     // 1x
        })) returns (uint256 positionId) {
            console2.log("SUCCESS: 1x position opened, ID:", positionId);
        } catch Error(string memory reason) {
            console2.log("FAILED 1x: ", reason);
        } catch {
            console2.log("FAILED 1x: Unknown error");
        }

        vm.stopBroadcast();

        console2.log("\n=== Test Complete ===");
        console2.log("If 1x leverage opened successfully, basic position opening is fixed!");
    }
}