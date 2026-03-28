// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/ExecutionEngine.sol";

/// @title Redeploy ExecutionEngine with Fixed LeverageModel
/// @notice Deploy new ExecutionEngine pointing to existing fixed LeverageModel
contract RedeployExecutionEngine is Script {

    function run() external {
        vm.startBroadcast();

        console2.log("=== Redeploying ExecutionEngine with Fixed LeverageModel ===");

        // Use existing contract addresses from deploy-env.sh
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

        // Use the FIXED LeverageModel that was already deployed
        address fixedLeverageModel = 0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF;

        console2.log("Current addresses:");
        console2.log("- PositionManager:", positionManager);
        console2.log("- OILimits:", oiLimits);
        console2.log("- MarginEngine:", marginEngine);
        console2.log("- OracleAdapter:", oracleAdapter);
        console2.log("- MarketRegistry:", marketRegistry);
        console2.log("- Fixed LeverageModel:", fixedLeverageModel);
        console2.log("- FeeRouter:", feeRouter);
        console2.log("- BorrowFeeEngine:", borrowFeeEngine);
        console2.log("- FundingRateEngine:", fundingRateEngine);
        console2.log("- AccountManager:", accountManager);
        console2.log("- LeverVault:", leverVault);
        console2.log("- Deployer:", deployer);

        // Deploy new ExecutionEngine with the fixed leverage model
        console2.log("Deploying ExecutionEngine with fixed LeverageModel...");
        ExecutionEngine newExecutionEngine = new ExecutionEngine(
            positionManager,
            oiLimits,
            marginEngine,
            oracleAdapter,
            marketRegistry,
            fixedLeverageModel, // Use the already-deployed fixed leverage model
            feeRouter,
            borrowFeeEngine,
            fundingRateEngine,
            accountManager,
            leverVault,
            insuranceFund,
            deployer
        );

        console2.log("NEW ExecutionEngine deployed at:", address(newExecutionEngine));

        vm.stopBroadcast();

        console2.log("=== Deployment Complete ===");
        console2.log("NEW ADDRESS TO UPDATE:");
        console2.log("EXECUTION_ENGINE=", address(newExecutionEngine));
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Update deploy-env.sh with new ExecutionEngine address");
        console2.log("2. Update frontend/user-app/src/config/contracts.ts");
        console2.log("3. Grant roles to new ExecutionEngine in other contracts if needed");
        console2.log("4. Test opening high-leverage positions (2x, 5x, 10x)");
    }
}