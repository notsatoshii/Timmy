// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/LeverageModelFixed.sol";

/// @title Deploy Fixed LeverageModel
/// @notice Deploy the fixed version and test it immediately
contract DeployFixedLeverageModel is Script {

    function run() external {
        vm.startBroadcast();

        console2.log("=== Deploying Fixed LeverageModel ===");

        // Get contract addresses from environment
        address vault = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;
        address insuranceFund = 0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8;
        address oiLimits = 0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd;
        address marketRegistry = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;
        address oracleAdapter = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c;
        address admin = 0x0e4D636c6D79c380A137f28EF73E054364cd5434; // Deployer address

        console2.log("Deploying with admin:", admin);

        // Deploy the fixed LeverageModel
        LeverageModelFixed newLeverageModel = new LeverageModelFixed(
            vault,
            insuranceFund,
            oiLimits,
            marketRegistry,
            oracleAdapter,
            admin
        );

        console2.log("New LeverageModel deployed at:", address(newLeverageModel));

        // Test immediately with SpaceX market
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        uint256 maxLev = newLeverageModel.getEffectiveMaxLeverage(spacexMarketId);
        
        console2.log("SpaceX max leverage (new contract):", maxLev / 1e18, "x");
        console2.log("SpaceX max leverage WAD:", maxLev);

        if (maxLev >= 20e18) {
            console2.log("SUCCESS: Fixed leverage model works! Max leverage >= 20x");
        } else {
            console2.log("Issue persists - debugging components...");
            
            uint256 ceiling = newLeverageModel.getPlatformCeiling();
            uint256 compressed = newLeverageModel.getCompressedLeverage(spacexMarketId);
            uint256 marketAdj = newLeverageModel.getMarketAdjustment(spacexMarketId);
            
            console2.log("Platform ceiling WAD:", ceiling);
            console2.log("Compressed leverage WAD:", compressed);
            console2.log("Market adjustment WAD:", marketAdj);
        }

        vm.stopBroadcast();

        console2.log("=== Deployment Complete ===");
        console2.log("Next steps if successful:");
        console2.log("1. Update deploy-env.sh: LEVERAGE_MODEL=", address(newLeverageModel));
        console2.log("2. Re-run role configuration for all contracts");
        console2.log("3. Update frontend contract addresses");
    }
}
