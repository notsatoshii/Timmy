// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/LeverageModel.sol";

/// @title Fix Leverage Parameters on Current Model
/// @notice Fix risk parameters on the actual LeverageModel that ExecutionEngine is using
contract FixLeverageParameters is Script {

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
        // Set extremely low depth threshold to minimize M_market penalties
        uint256 sigmaBaseline = 0.01e18;   // 1% baseline volatility (extremely low)
        uint256 depthThreshold = 0.01e18;  // 0.01 USDT (extremely low threshold)

        console2.log("New parameters:");
        console2.log("Sigma baseline WAD:", sigmaBaseline);
        console2.log("Depth threshold WAD:", depthThreshold);

        // Fix all markets
        bytes32[] memory markets = new bytes32[](5);
        markets[0] = spacexMarketId;
        markets[1] = usIranMarketId;
        markets[2] = fifaSpainMarketId;
        markets[3] = argentinaMarketId;
        markets[4] = fedRateMarketId;

        string[] memory names = new string[](5);
        names[0] = "SpaceX";
        names[1] = "US-Iran";
        names[2] = "FIFA Spain";
        names[3] = "Argentina";
        names[4] = "Fed Rate";

        for (uint256 i = 0; i < markets.length; i++) {
            console2.log("Fixing", names[i], "market...");

            uint256 currentMax = leverageModel.getEffectiveMaxLeverage(markets[i]);
            console2.log("Current max leverage WAD:", currentMax);

            leverageModel.setMarketRiskParams(markets[i], sigmaBaseline, depthThreshold);

            uint256 newMax = leverageModel.getEffectiveMaxLeverage(markets[i]);
            console2.log("New max leverage WAD:", newMax);

            if (newMax >= 10e18) {
                console2.log("SUCCESS:", names[i], "now supports >= 10x leverage");
            } else {
                console2.log("STILL ISSUES:", names[i], "max leverage < 10x");
            }
            console2.log("---");
        }

        console2.log("=== LEVERAGE FIX COMPLETE ===");
    }
}