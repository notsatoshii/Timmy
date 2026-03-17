// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { LeverageModel } from "../contracts/LeverageModel.sol";

/// @title FixLeverageModel — Quick fix deployment for critical TVL decimal bug
/// @notice Redeploys LeverageModel with proper USDT-to-WAD conversion
contract FixLeverageModel is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== LEVER LeverageModel Fix Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Fixing critical TVL decimal conversion bug");

        // Load existing contract addresses
        string memory coreJson = vm.readFile("core-deployment.json");
        string memory poolJson = vm.readFile("pool-deployment.json");
        string memory enginesJson = vm.readFile("engines-deployment.json");

        address marketRegistry = vm.parseJsonAddress(coreJson, ".marketRegistry");
        address oracleAdapter = vm.parseJsonAddress(coreJson, ".oracleAdapter");
        address leverVault = vm.parseJsonAddress(poolJson, ".leverVault");
        address insuranceFund = vm.parseJsonAddress(poolJson, ".insuranceFund");
        address oiLimits = vm.parseJsonAddress(enginesJson, ".oiLimits");

        console.log("Using existing addresses:");
        console.log("  LeverVault:", leverVault);
        console.log("  InsuranceFund:", insuranceFund);
        console.log("  OILimits:", oiLimits);
        console.log("  MarketRegistry:", marketRegistry);
        console.log("  OracleAdapter:", oracleAdapter);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new LeverageModel with fixed decimal conversion
        address newLeverageModel = address(new LeverageModel(
            leverVault,
            insuranceFund,
            oiLimits,
            marketRegistry,
            oracleAdapter,
            deployer
        ));

        vm.stopBroadcast();

        console.log("=== LeverageModel Fix Complete ===");
        console.log("New LeverageModel:", newLeverageModel);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Update deploy-env.sh with new LEVERAGE_MODEL address");
        console.log("2. Update engines-deployment.json");
        console.log("3. Verify TVL multiplier returns 1.0 instead of 0.1");
        console.log("4. Update ExecutionEngine to use new LeverageModel");
    }
}