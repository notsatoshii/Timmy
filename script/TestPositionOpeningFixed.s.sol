// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/ILeverageModel.sol";
import "../contracts/interfaces/IAccountManager.sol";

/// @title Test Position Opening with Fixed ExecutionEngine
/// @notice Test opening positions at 2x, 5x, 10x leverage to verify fix
contract TestPositionOpeningFixed is Script {

    function run() external {
        vm.startBroadcast();

        console2.log("=== Testing Position Opening with Fixed ExecutionEngine ===");

        // Use the new ExecutionEngine address
        IExecutionEngine executionEngine = IExecutionEngine(0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519);
        IAccountManager accountManager = IAccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);

        // Use SpaceX market for testing
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        // Check max leverage first
        ILeverageModel leverageModel = ILeverageModel(0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF);
        uint256 maxLeverage = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("Max leverage for SpaceX market:", maxLeverage / 1e18, "x");

        // Account balance check skipped - will see if transactions fail due to insufficient funds

        // Test 2x leverage
        console2.log("\n--- Testing 2x Leverage ---");
        try executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId: spacexMarketId,
            isLong: true,
            collateral: 50e6, // 50 USDT
            leverage: 2e18     // 2x
        })) returns (uint256 positionId) {
            console2.log("SUCCESS: 2x position opened, ID:", positionId);
        } catch Error(string memory reason) {
            console2.log("FAILED 2x: ", reason);
        } catch {
            console2.log("FAILED 2x: Unknown error");
        }

        // Test 5x leverage
        console2.log("\n--- Testing 5x Leverage ---");
        try executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId: spacexMarketId,
            isLong: true,
            collateral: 20e6, // 20 USDT
            leverage: 5e18    // 5x
        })) returns (uint256 positionId) {
            console2.log("SUCCESS: 5x position opened, ID:", positionId);
        } catch Error(string memory reason) {
            console2.log("FAILED 5x: ", reason);
        } catch {
            console2.log("FAILED 5x: Unknown error");
        }

        // Test 10x leverage
        console2.log("\n--- Testing 10x Leverage ---");
        try executionEngine.openPosition(IExecutionEngine.OpenParams({
            marketId: spacexMarketId,
            isLong: true,
            collateral: 10e6, // 10 USDT
            leverage: 10e18   // 10x
        })) returns (uint256 positionId) {
            console2.log("SUCCESS: 10x position opened, ID:", positionId);
        } catch Error(string memory reason) {
            console2.log("FAILED 10x: ", reason);
        } catch {
            console2.log("FAILED 10x: Unknown error");
        }

        vm.stopBroadcast();

        console2.log("\n=== Test Complete ===");
        console2.log("If all three leverage levels opened successfully, the fix is working!");
    }
}