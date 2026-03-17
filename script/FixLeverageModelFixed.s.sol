// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/LeverageModelFixed.sol";

/// @title Fix LeverageModelFixed Risk Parameters
/// @notice Fix unrealistic depth thresholds for realistic prediction market depths
contract FixLeverageModelFixed is Script {

    function run() external {
        vm.startBroadcast();

        LeverageModelFixed leverageModel = LeverageModelFixed(0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF);

        // SpaceX market ID
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        console2.log("=== Fixing LeverageModelFixed Risk Parameters ===");

        // Check current parameters
        console2.log("Checking current max leverage for SpaceX...");
        uint256 currentMax = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("Current max leverage WAD:", currentMax);

        // The problem: depth threshold of 500 USDT is unrealistic when oracle returns ~5 USDT depth
        // Fix: Set depth threshold to 5 USDT (realistic for prediction market depth)
        uint256 sigmaBaseline = 0.25e18;  // Keep 25% baseline volatility
        uint256 depthThreshold = 5e18;    // Change from 500 to 5 USDT

        console2.log("Setting new risk parameters...");
        console2.log("Sigma baseline WAD:", sigmaBaseline);
        console2.log("Depth threshold WAD:", depthThreshold);

        leverageModel.setMarketRiskParams(
            spacexMarketId,
            sigmaBaseline,
            depthThreshold
        );

        console2.log("Risk parameters updated!");

        // Check new max leverage
        uint256 newMax = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("New max leverage WAD:", newMax);

        if (newMax >= 20e18) {
            console2.log("SUCCESS: Max leverage >= 20x");
        } else {
            console2.log("Need more fixes - leverage still low");
        }
    }
}