// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/LeverageModelFixed.sol";

/// @title Deploy Fixed LeverageModel
/// @notice Deploy the fixed leverage model with realistic depth thresholds
contract DeployLeverageModelFixed is Script {

    function run() external {
        vm.startBroadcast();

        console2.log("=== Deploying Fixed LeverageModel ===");

        // Deploy new fixed leverage model
        LeverageModelFixed leverageModel = new LeverageModelFixed(
            0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921, // LEVER_VAULT
            0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8,  // INSURANCE_FUND
            0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd,  // OI_LIMITS
            0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7,  // MARKET_REGISTRY
            0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c,  // ORACLE_ADAPTER
            0x0e4D636c6D79c380A137f28EF73E054364cd5434   // DEPLOYER (admin)
        );

        console2.log("LeverageModelFixed deployed to:", address(leverageModel));

        // Test leverage for SpaceX market
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;

        uint256 maxLeverage = leverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("SpaceX max leverage WAD:", maxLeverage);

        if (maxLeverage >= 20e18) {
            console2.log("SUCCESS: Fixed model provides >= 20x leverage!");
        } else {
            console2.log("WARNING: Leverage still low - need parameter fixes");
        }

        console2.log("=== Deployment Complete ===");
        console2.log("Next steps:");
        console2.log("1. Update LEVERAGE_MODEL in deploy-env.sh to:", address(leverageModel));
        console2.log("2. Redeploy ExecutionEngine with new address");
        console2.log("3. Update all contracts that reference LeverageModel");

        vm.stopBroadcast();
    }
}