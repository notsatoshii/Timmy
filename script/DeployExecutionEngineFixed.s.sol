// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/ExecutionEngine.sol";
import "../contracts/LeverageModelFixed.sol";

/// @title Deploy ExecutionEngine with Fixed LeverageModel
/// @notice Deploy new ExecutionEngine pointing to LeverageModelFixed for high leverage support
contract DeployExecutionEngineFixed is Script {

    function run() external {
        vm.startBroadcast();

        console2.log("=== Deploying ExecutionEngine with Fixed LeverageModel ===");

        // Get contract addresses from deployment environment
        address positionManager = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
        address oiLimits = 0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd;
        address marginEngine = 0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce;
        address oracleAdapter = 0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c;
        address marketRegistry = 0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7;
        address feeRouter = 0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F;
        address borrowFeeEngine = 0x706578de003912C71e534949d8b8DDd5108950e1;
        address fundingRateEngine = 0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe;
        address accountManager = 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684;
        address leverVault = 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921;
        address insuranceFund = 0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8;
        address deployer = 0x0e4D636c6D79c380A137f28EF73E054364cd5434;

        // Deploy new LeverageModelFixed
        console2.log("Deploying LeverageModelFixed...");
        LeverageModelFixed newLeverageModel = new LeverageModelFixed(
            leverVault,          // vault
            0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8, // insuranceFund
            oiLimits,           // oiLimits
            marketRegistry,     // marketRegistry
            oracleAdapter,      // oracleAdapter
            deployer            // admin
        );

        console2.log("LeverageModelFixed deployed at:", address(newLeverageModel));

        // Set realistic risk parameters for all markets
        bytes32 spacexMarketId = 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1;
        bytes32 usIranMarketId = 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a;
        bytes32 fifaSpainMarketId = 0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7;
        bytes32 argentinaMarketId = 0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea;
        bytes32 fedRateMarketId = 0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554;

        console2.log("Setting risk parameters for high leverage...");
        uint256 sigmaBaseline = 0.15e18;  // Lower baseline volatility for higher leverage
        uint256 depthThreshold = 0.5e18;  // Very low depth threshold

        newLeverageModel.setMarketRiskParams(spacexMarketId, sigmaBaseline, depthThreshold);
        newLeverageModel.setMarketRiskParams(usIranMarketId, sigmaBaseline, depthThreshold);
        newLeverageModel.setMarketRiskParams(fifaSpainMarketId, sigmaBaseline, depthThreshold);
        newLeverageModel.setMarketRiskParams(argentinaMarketId, sigmaBaseline, depthThreshold);
        newLeverageModel.setMarketRiskParams(fedRateMarketId, sigmaBaseline, depthThreshold);

        // Test leverage on the new model
        uint256 maxLev = newLeverageModel.getEffectiveMaxLeverage(spacexMarketId);
        console2.log("SpaceX max leverage with new model:", maxLev / 1e18, "x");

        if (maxLev >= 20e18) {
            console2.log("SUCCESS: New leverage model provides 20x+ leverage!");
        } else {
            console2.log("WARNING: Still not achieving 20x+ leverage");

            // Debug components
            uint256 ceiling = newLeverageModel.getPlatformCeiling();
            uint256 compressed = newLeverageModel.getCompressedLeverage(spacexMarketId);
            uint256 marketAdj = newLeverageModel.getMarketAdjustment(spacexMarketId);

            console2.log("Platform ceiling:", ceiling / 1e18);
            console2.log("Compressed leverage:", compressed / 1e18);
            console2.log("Market adjustment:", marketAdj);
        }

        // Deploy new ExecutionEngine with the fixed leverage model
        console2.log("Deploying ExecutionEngine with fixed LeverageModel...");
        ExecutionEngine newExecutionEngine = new ExecutionEngine(
            positionManager,
            oiLimits,
            marginEngine,
            oracleAdapter,
            marketRegistry,
            address(newLeverageModel), // Use the new fixed leverage model
            feeRouter,
            borrowFeeEngine,
            fundingRateEngine,
            accountManager,
            leverVault,
            insuranceFund,
            deployer
        );

        console2.log("ExecutionEngine deployed at:", address(newExecutionEngine));

        vm.stopBroadcast();

        console2.log("=== Deployment Complete ===");
        console2.log("NEW ADDRESSES TO UPDATE:");
        console2.log("LEVERAGE_MODEL=", address(newLeverageModel));
        console2.log("EXECUTION_ENGINE=", address(newExecutionEngine));
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Update deploy-env.sh with new addresses");
        console2.log("2. Grant roles to new ExecutionEngine in other contracts");
        console2.log("3. Test opening high-leverage positions");
    }
}