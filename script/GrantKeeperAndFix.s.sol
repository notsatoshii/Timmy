// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/LeverageModel.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title Grant KEEPER role and fix LeverageModel parameters
contract GrantKeeperAndFix is Script {

    function run() external {
        vm.startBroadcast();

        address leverageModel = 0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF;
        IAccessControl accessControl = IAccessControl(leverageModel);

        // Grant KEEPER role to deployer
        bytes32 KEEPER_ROLE = keccak256("KEEPER_ROLE");
        console2.log("Granting KEEPER role...");
        accessControl.grantRole(KEEPER_ROLE, msg.sender);
        console2.log("KEEPER role granted to:", msg.sender);

        LeverageModel leverageModelContract = LeverageModel(leverageModel);

        // SpaceX market ID
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        // Check current max leverage
        uint256 currentMax = leverageModelContract.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("Current max leverage WAD:", currentMax);

        // Fix the depth threshold - oracle returns ~1-5 USDT depth, so set threshold to 1 USDT
        uint256 sigmaBaseline = 0.25e18;  // Keep 25% baseline volatility
        uint256 depthThreshold = 1e18;    // Set to 1 USDT (matches typical oracle depth)

        console2.log("Setting realistic risk parameters...");
        console2.log("Depth threshold: 1 USDT (was 500)");

        leverageModelContract.setMarketRiskParams(
            spacexMarketId,
            sigmaBaseline,
            depthThreshold
        );

        // Check new max leverage
        uint256 newMax = leverageModelContract.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("New max leverage WAD:", newMax);

        if (newMax >= 20e18) {
            console2.log("SUCCESS: Max leverage >= 20x");
        } else {
            console2.log("Still need fixes - checking components...");
            
            // Debug the components
            uint256 ceiling = leverageModelContract.getPlatformCeiling();
            uint256 compressed = leverageModelContract.getCompressedLeverage(spacexMarketId);
            uint256 marketAdj = leverageModelContract.getMarketAdjustment(spacexMarketId);
            
            console2.log("Platform ceiling WAD:", ceiling);
            console2.log("Compressed leverage WAD:", compressed);
            console2.log("Market adjustment WAD:", marketAdj);
        }

        vm.stopBroadcast();
    }
}
