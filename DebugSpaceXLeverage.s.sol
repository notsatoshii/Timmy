// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/LeverageModel.sol";

/// @title Debug SpaceX Leverage Issue in Detail
contract DebugSpaceXLeverage is Script {

    function run() external view {
        // The ACTUAL LeverageModel address that ExecutionEngine is pointing to
        LeverageModel leverageModel = LeverageModel(0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF);

        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        console2.log("=== DETAILED SPACEX LEVERAGE DEBUG ===");

        // Get platform ceiling components
        uint256 tvlMult = leverageModel.getTVLMultiplier();
        uint256 ifrMult = leverageModel.getIFRMultiplier();
        uint256 utilMult = leverageModel.getUtilizationMultiplier();
        uint256 platformCeiling = leverageModel.getPlatformCeiling();

        console2.log("Platform Ceiling Components:");
        console2.log("  TVL Multiplier:", tvlMult / 1e16, "bps");
        console2.log("  IFR Multiplier:", ifrMult / 1e16, "bps");
        console2.log("  Util Multiplier:", utilMult / 1e16, "bps");
        console2.log("  Platform Ceiling:", platformCeiling / 1e18, "x");

        // Get market-specific factors
        uint256 compressedLeverage = leverageModel.getCompressedLeverage(spacexMarketId);
        uint256 marketAdjustment = leverageModel.getMarketAdjustment(spacexMarketId);
        uint256 effectiveMax = leverageModel.getEffectiveMaxLeverage(spacexMarketId);

        console2.log("\nMarket-Specific Factors:");
        console2.log("  Compressed Leverage:", compressedLeverage / 1e18, "x");
        console2.log("  Market Adjustment (M_market):", marketAdjustment / 1e16, "bps");
        console2.log("  Effective Max Leverage:", effectiveMax / 1e18, "x");

        // Check stored risk parameters
        try leverageModel.getMarketRiskParams(spacexMarketId) {
            console2.log("\nStored Risk Parameters: Available but can't decode without struct");
        } catch {
            console2.log("\nStored Risk Parameters: ERROR or NO INTERFACE");
        }

        // Manual calculation check
        console2.log("\nManual Calculation Check:");
        console2.log("  Step 1 (Platform): ", platformCeiling / 1e18, "x");
        console2.log("  Step 2 (Compressed): ", compressedLeverage / 1e18, "x");
        console2.log("  Step 3 (Final): ", effectiveMax / 1e18, "x");

        // Calculate what each step does
        if (platformCeiling > 0) {
            uint256 step2Factor = (compressedLeverage * 1000) / platformCeiling;
            console2.log("  Step 2 Factor (R_adjusted):", step2Factor, "/ 1000");
        }

        if (compressedLeverage > 0) {
            uint256 step3Factor = (effectiveMax * 1000) / compressedLeverage;
            console2.log("  Step 3 Factor (M_market):", step3Factor, "/ 1000");
        }

        console2.log("\n=== EXPECTED CALCULATION ===");
        console2.log("For a 288-day market that is live:");
        console2.log("  tau = 6863 hours");
        console2.log("  tau_effective = 6863 x 0.3 = 2059 hours (live compression)");
        console2.log("  R(tau) should be close to 1.0 (far from resolution)");
        console2.log("  Expected leverage should be 10x+ with proper parameters");
    }
}