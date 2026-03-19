// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/LeverageModel.sol";

/// @title Fix Actual LeverageModel Used by ExecutionEngine
/// @notice Fix risk parameters on the LeverageModel that ExecutionEngine is actually using
contract FixActualLeverageModel is Script {

    function run() external {
        vm.startBroadcast();

        // This is the ACTUAL LeverageModel address that ExecutionEngine is pointing to
        LeverageModel leverageModel = LeverageModel(0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF);

        // Market IDs we need to fix
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        bytes32 usIranMarketId = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;

        console2.log("=== Fixing ACTUAL LeverageModel Risk Parameters ===");
        console2.log("LeverageModel address:", address(leverageModel));

        // The problem: depth threshold too high for the oracle depth (1 token)
        // Current oracle shows "Depth: 1 tokens" which is 1e18 in WAD
        // Fix: Set depth threshold LOWER than the current oracle depth
        uint256 sigmaBaseline = 0.25e18;  // 25% baseline volatility
        uint256 depthThreshold = 0.5e18;  // 0.5 tokens (lower than current 1 token depth)

        console2.log("New parameters:");
        console2.log("Sigma baseline WAD:", sigmaBaseline);
        console2.log("Depth threshold WAD:", depthThreshold);
        console2.log("Current oracle depth: 1 tokens (1e18)");

        // Check current state
        console2.log("=== BEFORE FIX ===");
        try leverageModel.getEffectiveMaxLeverage(spacexMarketId) returns (uint256 currentMax) {
            console2.log("SpaceX current max leverage WAD:", currentMax);
            console2.log("SpaceX current max leverage x:", currentMax / 1e18);
        } catch {
            console2.log("SpaceX: Could not get current max leverage");
        }

        try leverageModel.getMarketAdjustment(spacexMarketId) returns (uint256 currentMMarket) {
            console2.log("SpaceX current M_market WAD:", currentMMarket);
            console2.log("SpaceX current M_market bps:", currentMMarket / 1e16);
        } catch {
            console2.log("SpaceX: Could not get current M_market");
        }

        // Fix SpaceX parameters
        console2.log("=== APPLYING FIX ===");
        leverageModel.setMarketRiskParams(spacexMarketId, sigmaBaseline, depthThreshold);
        console2.log("SpaceX parameters updated");

        // Fix US-Iran parameters
        leverageModel.setMarketRiskParams(usIranMarketId, sigmaBaseline, depthThreshold);
        console2.log("US-Iran parameters updated");

        // Check results
        console2.log("=== AFTER FIX ===");
        uint256 spacexNewMax = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("SpaceX new max leverage WAD:", spacexNewMax);
        console2.log("SpaceX new max leverage x:", spacexNewMax / 1e18);

        uint256 spacexNewMMarket = leverageModel.getMarketAdjustment(spacexMarketId);
        console2.log("SpaceX new M_market WAD:", spacexNewMMarket);
        console2.log("SpaceX new M_market bps:", spacexNewMMarket / 1e16);

        uint256 usIranNewMax = leverageModel.getEffectiveMaxLeverage(usIranMarketId);
        console2.log("US-Iran new max leverage x:", usIranNewMax / 1e18);

        // Success criteria check
        if (spacexNewMax >= 10e18) {
            console2.log("SUCCESS: SpaceX now allows >= 10x leverage");
        } else {
            console2.log("PARTIAL: SpaceX still below 10x leverage");
        }

        if (usIranNewMax >= 10e18) {
            console2.log("SUCCESS: US-Iran now allows >= 10x leverage");
        } else {
            console2.log("PARTIAL: US-Iran still below 10x leverage");
        }

        vm.stopBroadcast();
    }
}