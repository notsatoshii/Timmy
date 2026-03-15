// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/// @title DeployAll — Complete LEVER Protocol deployment orchestrator
/// @notice Runs all deployment phases in sequence: Core -> Pool -> Engines -> Roles
/// @dev Usage:
///   forge script script/DeployAll.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
///
/// Environment variables required:
///   - PRIVATE_KEY: Deployer private key
///   - ORACLE_KEEPER: Oracle keeper address
///   - PROTOCOL_TREASURY: Protocol treasury address (optional, defaults to deployer)
///   - MARKET_MANAGER: Market manager address (optional, defaults to admin)
///   - ADMIN_ADDRESS: Admin address (optional, defaults to deployer)
///   - USDT_ADDRESS: Existing USDT address (optional, deploys MockUSDT if not provided)
contract DeployAll is Script {

    function run() external {
        console.log("=== LEVER Protocol Complete Deployment ===");
        console.log("Running all phases in sequence...");

        // Validate required environment variables
        _validateEnvironment();

        // Phase 1: Core contracts
        console.log("\n>>> Phase 1: Core Contracts <<<");
        _runScript("DeployCore");

        // Phase 2: LP Pool & Fee routing
        console.log("\n>>> Phase 2: LP Pool & Fee Routing <<<");
        _runScript("DeployPool");

        // Phase 3: Engines
        console.log("\n>>> Phase 3: Risk & Execution Engines <<<");
        _runScript("DeployEngines");

        // Phase 4: Role configuration
        console.log("\n>>> Phase 4: Role Configuration <<<");
        _runScript("ConfigureRoles");

        // Phase 5: Final consolidation
        console.log("\n>>> Phase 5: Final Consolidation <<<");
        _consolidateDeploymentFiles();

        console.log("\n=== LEVER Protocol Deployment Complete ===");
        console.log("All contracts deployed and configured successfully!");
        console.log("\nDeployment artifacts:");
        console.log("  - deployment.json: All contract addresses");
        console.log("  - core-deployment.json: Phase 1 artifacts");
        console.log("  - pool-deployment.json: Phase 2 artifacts");
        console.log("  - engines-deployment.json: Phase 3 artifacts");

        console.log("\nNext steps:");
        console.log("  1. Verify contracts: forge script script/Verify.s.sol --verify");
        console.log("  2. Create markets: forge script script/OnboardMarkets.s.sol --broadcast");
        console.log("  3. Start oracle feeds: python scripts/oracle/keeper.py");
    }

    function _validateEnvironment() internal view {
        console.log("Validating environment variables...");

        require(vm.envUint("PRIVATE_KEY") != 0, "PRIVATE_KEY required");
        require(vm.envAddress("ORACLE_KEEPER") != address(0), "ORACLE_KEEPER required");

        console.log("  PRIVATE_KEY: Set");
        console.log("  ORACLE_KEEPER:", vm.envAddress("ORACLE_KEEPER"));

        address protocolTreasury = vm.envOr("PROTOCOL_TREASURY", vm.addr(vm.envUint("PRIVATE_KEY")));
        console.log("  PROTOCOL_TREASURY:", protocolTreasury);

        address existingUSDT = vm.envOr("USDT_ADDRESS", address(0));
        if (existingUSDT != address(0)) {
            console.log("  USDT_ADDRESS:", existingUSDT);
        } else {
            console.log("  USDT_ADDRESS: Not set, will deploy MockUSDT");
        }

        console.log("Environment validation complete.");
    }

    function _runScript(string memory scriptName) internal {
        string[] memory cmd = new string[](4);
        cmd[0] = "forge";
        cmd[1] = "script";
        cmd[2] = string(abi.encodePacked("script/", scriptName, ".s.sol"));
        cmd[3] = "--broadcast";

        try vm.ffi(cmd) returns (bytes memory result) {
            console.log(scriptName, "completed successfully");
        } catch Error(string memory reason) {
            console.log("ERROR in", scriptName, ":", reason);
            revert(string(abi.encodePacked("Deployment failed at phase: ", scriptName)));
        }
    }

    function _consolidateDeploymentFiles() internal {
        console.log("Consolidating deployment files...");

        // Read all phase outputs
        string memory coreJson = vm.readFile("core-deployment.json");
        string memory poolJson = vm.readFile("pool-deployment.json");
        string memory enginesJson = vm.readFile("engines-deployment.json");

        // Extract all addresses
        address usdt = vm.parseJsonAddress(coreJson, ".usdt");
        address marketRegistry = vm.parseJsonAddress(coreJson, ".marketRegistry");
        address oracleAdapter = vm.parseJsonAddress(coreJson, ".oracleAdapter");
        address accountManager = vm.parseJsonAddress(coreJson, ".accountManager");
        address positionManager = vm.parseJsonAddress(coreJson, ".positionManager");

        address leverVault = vm.parseJsonAddress(poolJson, ".leverVault");
        address rewardsDistributor = vm.parseJsonAddress(poolJson, ".rewardsDistributor");
        address insuranceFund = vm.parseJsonAddress(poolJson, ".insuranceFund");
        address feeRouter = vm.parseJsonAddress(poolJson, ".feeRouter");

        address leverageModel = vm.parseJsonAddress(enginesJson, ".leverageModel");
        address oiLimits = vm.parseJsonAddress(enginesJson, ".oiLimits");
        address borrowFeeEngine = vm.parseJsonAddress(enginesJson, ".borrowFeeEngine");
        address fundingRateEngine = vm.parseJsonAddress(enginesJson, ".fundingRateEngine");
        address marginEngine = vm.parseJsonAddress(enginesJson, ".marginEngine");
        address executionEngine = vm.parseJsonAddress(enginesJson, ".executionEngine");
        address liquidationEngine = vm.parseJsonAddress(enginesJson, ".liquidationEngine");
        address settlementEngine = vm.parseJsonAddress(enginesJson, ".settlementEngine");

        // Create consolidated deployment.json
        string memory consolidated = string(abi.encodePacked(
            '{\n',
            '  "usdt": "', vm.toString(usdt), '",\n',
            '  "marketRegistry": "', vm.toString(marketRegistry), '",\n',
            '  "oracleAdapter": "', vm.toString(oracleAdapter), '",\n',
            '  "accountManager": "', vm.toString(accountManager), '",\n',
            '  "positionManager": "', vm.toString(positionManager), '",\n',
            '  "leverageModel": "', vm.toString(leverageModel), '",\n',
            '  "oiLimits": "', vm.toString(oiLimits), '",\n',
            '  "borrowFeeEngine": "', vm.toString(borrowFeeEngine), '",\n',
            '  "fundingRateEngine": "', vm.toString(fundingRateEngine), '",\n',
            '  "marginEngine": "', vm.toString(marginEngine), '",\n',
            '  "executionEngine": "', vm.toString(executionEngine), '",\n',
            '  "feeRouter": "', vm.toString(feeRouter), '",\n',
            '  "insuranceFund": "', vm.toString(insuranceFund), '",\n',
            '  "leverVault": "', vm.toString(leverVault), '",\n',
            '  "rewardsDistributor": "', vm.toString(rewardsDistributor), '",\n',
            '  "liquidationEngine": "', vm.toString(liquidationEngine), '",\n',
            '  "settlementEngine": "', vm.toString(settlementEngine), '"\n',
            '}'
        ));

        vm.writeFile("deployment.json", consolidated);
        console.log("Consolidated deployment.json created");
    }
}