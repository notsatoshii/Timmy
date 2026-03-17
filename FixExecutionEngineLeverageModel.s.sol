// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/LeverageModel.sol";

/// @title Fix ExecutionEngine's LeverageModel Risk Parameters
/// @notice Fix risk parameters on the LeverageModel that ExecutionEngine is actually using
contract FixExecutionEngineLeverageModel is Script {

    function run() external {
        vm.startBroadcast();

        // This is the LeverageModel address that ExecutionEngine is actually pointing to
        LeverageModel leverageModel = LeverageModel(0x63B98Ec1e559E3b24199eb2115F0a57222e9818c);

        // Market IDs we need to fix
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        bytes32 usIranMarketId = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
        bytes32 fifaSpainMarketId = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
        bytes32 argentinaMarketId = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea;
        bytes32 fedRateMarketId = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554;

        console2.log("=== Fixing LeverageModel Risk Parameters ===");
        console2.log("LeverageModel address:", address(leverageModel));

        // Fix parameters for all markets to allow high leverage
        // The problem: unrealistic depth thresholds causing extreme M_market penalties
        // Fix: Set depth threshold to 5 USDT (realistic for prediction market depth)
        uint256 sigmaBaseline = 0.25e18;  // 25% baseline volatility
        uint256 depthThreshold = 5e18;    // 5 USDT (realistic depth)

        console2.log("New parameters:");
        console2.log("Sigma baseline WAD:", sigmaBaseline);
        console2.log("Depth threshold WAD:", depthThreshold);

        // Fix SpaceX
        console2.log("Fixing SpaceX market...");
        uint256 currentMax = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("SpaceX current max leverage WAD:", currentMax);

        leverageModel.setMarketRiskParams(spacexMarketId, sigmaBaseline, depthThreshold);

        uint256 newMax = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("SpaceX new max leverage WAD:", newMax);

        // Fix US-Iran
        console2.log("Fixing US-Iran market...");
        leverageModel.setMarketRiskParams(usIranMarketId, sigmaBaseline, depthThreshold);

        // Fix FIFA Spain
        console2.log("Fixing FIFA Spain market...");
        leverageModel.setMarketRiskParams(fifaSpainMarketId, sigmaBaseline, depthThreshold);

        // Fix Argentina
        console2.log("Fixing Argentina market...");
        leverageModel.setMarketRiskParams(argentinaMarketId, sigmaBaseline, depthThreshold);

        // Fix Fed Rate
        console2.log("Fixing Fed Rate market...");
        leverageModel.setMarketRiskParams(fedRateMarketId, sigmaBaseline, depthThreshold);

        // Check final results
        console2.log("=== Final Results ===");
        uint256 spacexFinal = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("SpaceX final max leverage WAD:", spacexFinal);

        if (spacexFinal >= 20e18) {
            console2.log("SUCCESS: Max leverage >= 20x for SpaceX");
        } else {
            console2.log("STILL ISSUES: Max leverage < 20x for SpaceX");
        }

        console2.log("All markets should now support high leverage positions");
    }
}