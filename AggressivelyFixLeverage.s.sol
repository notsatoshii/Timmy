// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/LeverageModel.sol";

/// @title Aggressively Fix Leverage Parameters
/// @notice Use very permissive parameters to ensure high leverage for demo
contract AggressivelyFixLeverage is Script {

    function run() external {
        vm.startBroadcast();

        // The ACTUAL LeverageModel address that ExecutionEngine is pointing to
        LeverageModel leverageModel = LeverageModel(0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF);

        // Market IDs we need to fix
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        bytes32 usIranMarketId = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;

        console2.log("=== AGGRESSIVE LEVERAGE FIX ===");
        console2.log("Current oracle depth: 1 tokens (1e18)");
        console2.log("Current M_market: 73.5%");

        // AGGRESSIVE parameters designed to maximize M_market
        // Set depth threshold VERY LOW so any depth gets full credit
        // Set sigma baseline VERY HIGH so volatility penalty is minimized
        uint256 sigmaBaseline = 2e18;      // 200% - much higher than any real volatility
        uint256 depthThreshold = 1e17;     // 0.1 tokens - 10x smaller than current depth

        console2.log("New AGGRESSIVE parameters:");
        console2.log("Sigma baseline:", sigmaBaseline / 1e16, "bps (200%)");
        console2.log("Depth threshold:", depthThreshold / 1e18, "tokens (0.1)");
        console2.log("Expected depth factor: min(1.0, 1.0 / 0.1) = 1.0 (full)");
        console2.log("Expected vol factor: should be 1.0 (volatility well below baseline)");

        // Check before
        uint256 spacexBefore = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        uint256 spacexMMarketBefore = leverageModel.getMarketAdjustment(spacexMarketId);

        console2.log("\n=== BEFORE ===");
        console2.log("SpaceX max leverage:", spacexBefore / 1e18, "x");
        console2.log("SpaceX M_market:", spacexMMarketBefore / 1e16, "bps");

        // Apply aggressive fix
        leverageModel.setMarketRiskParams(spacexMarketId, sigmaBaseline, depthThreshold);
        leverageModel.setMarketRiskParams(usIranMarketId, sigmaBaseline, depthThreshold);

        // Check after
        uint256 spacexAfter = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        uint256 spacexMMarketAfter = leverageModel.getMarketAdjustment(spacexMarketId);
        uint256 usIranAfter = leverageModel.getEffectiveMaxLeverage(usIranMarketId);

        console2.log("\n=== AFTER ===");
        console2.log("SpaceX max leverage:", spacexAfter / 1e18, "x");
        console2.log("SpaceX M_market:", spacexMMarketAfter / 1e16, "bps");
        console2.log("US-Iran max leverage:", usIranAfter / 1e18, "x");

        // Success check
        if (spacexAfter >= 10e18 && usIranAfter >= 10e18) {
            console2.log("\nSUCCESS: Both markets now allow >= 10x leverage");
        } else {
            console2.log("\nNEEDS MORE WORK: Not all markets at 10x+");
        }

        vm.stopBroadcast();
    }
}