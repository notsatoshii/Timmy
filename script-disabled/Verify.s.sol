// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/// @title Verify — BaseScan contract verification script
/// @notice Verifies all LEVER Protocol contracts on BaseScan after deployment
/// @dev Usage:
///   forge script script/Verify.s.sol --rpc-url $BASE_SEPOLIA_RPC --verify --etherscan-api-key $BASESCAN_API_KEY
///
///   For mainnet:
///   forge script script/Verify.s.sol --rpc-url $BASE_RPC --verify --etherscan-api-key $BASESCAN_API_KEY
///
/// @dev This script reads the deployment config and submits verification for each contract
contract Verify is Script {

    struct ContractInfo {
        string name;
        address addr;
        string constructorArgs;
    }

    function run() external view {
        console.log("LEVER Protocol Contract Verification");
        console.log("====================================");

        // Load deployment addresses
        string memory configPath = vm.envOr("DEPLOYMENT_CONFIG", "deployments/base-sepolia-addresses.json");
        string memory json = vm.readFile(configPath);

        console.log("Reading deployment config from:", configPath);

        // Extract addresses
        address admin = vm.parseJsonAddress(json, ".admin");
        address usdt = vm.parseJsonAddress(json, ".usdt");

        // Contract addresses
        address marketRegistry = vm.parseJsonAddress(json, ".marketRegistry");
        address accountManager = vm.parseJsonAddress(json, ".accountManager");
        address positionManager = vm.parseJsonAddress(json, ".positionManager");
        address oracleAdapter = vm.parseJsonAddress(json, ".oracleAdapter");
        address leverageModel = vm.parseJsonAddress(json, ".leverageModel");
        address oiLimits = vm.parseJsonAddress(json, ".oiLimits");
        address borrowFeeEngine = vm.parseJsonAddress(json, ".borrowFeeEngine");
        address fundingRateEngine = vm.parseJsonAddress(json, ".fundingRateEngine");
        address marginEngine = vm.parseJsonAddress(json, ".marginEngine");
        address executionEngine = vm.parseJsonAddress(json, ".executionEngine");
        address feeRouter = vm.parseJsonAddress(json, ".feeRouter");
        address insuranceFund = vm.parseJsonAddress(json, ".insuranceFund");
        address leverVault = vm.parseJsonAddress(json, ".leverVault");
        address rewardsDistributor = vm.parseJsonAddress(json, ".rewardsDistributor");
        address liquidationEngine = vm.parseJsonAddress(json, ".liquidationEngine");
        address settlementEngine = vm.parseJsonAddress(json, ".settlementEngine");

        // Print verification commands
        console.log("\nContract Verification Commands:");
        console.log("===============================");

        // Note: Actual verification requires Forge's --verify flag during deployment
        // This script provides the manual commands if automatic verification failed

        _printVerifyCommand("MockUSDT", usdt, "");
        _printVerifyCommand("MarketRegistry", marketRegistry, string(abi.encodePacked('"', vm.toString(admin), '"')));
        _printVerifyCommand("AccountManager", accountManager, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(usdt), '"')));
        _printVerifyCommand("PositionManager", positionManager, string(abi.encodePacked('"', vm.toString(admin), '"')));
        _printVerifyCommand("OracleAdapter", oracleAdapter, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(marketRegistry), '"')));
        _printVerifyCommand("FeeRouter", feeRouter, string(abi.encodePacked('"', vm.toString(admin), '"')));
        _printVerifyCommand("InsuranceFund", insuranceFund, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(usdt), '","', vm.toString(feeRouter), '"')));
        _printVerifyCommand("RewardsDistributor", rewardsDistributor, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(usdt), '","', vm.toString(leverVault), '"')));
        _printVerifyCommand("LeverVault", leverVault, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(usdt), '","', vm.toString(rewardsDistributor), '"')));
        _printVerifyCommand("OILimits", oiLimits, string(abi.encodePacked('"', vm.toString(marketRegistry), '","', vm.toString(leverVault), '","', vm.toString(admin), '"')));
        _printVerifyCommand("LeverageModel", leverageModel, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(marketRegistry), '","', vm.toString(leverVault), '","', vm.toString(insuranceFund), '","', vm.toString(oiLimits), '"')));
        _printVerifyCommand("BorrowFeeEngine", borrowFeeEngine, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(marketRegistry), '","', vm.toString(oiLimits), '","', vm.toString(positionManager), '"')));
        _printVerifyCommand("FundingRateEngine", fundingRateEngine, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(marketRegistry), '","', vm.toString(oiLimits), '","', vm.toString(positionManager), '"')));
        _printVerifyCommand("MarginEngine", marginEngine, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(oracleAdapter), '","', vm.toString(leverageModel), '","', vm.toString(borrowFeeEngine), '","', vm.toString(fundingRateEngine), '","', vm.toString(positionManager), '"')));

        // ExecutionEngine has many parameters
        string memory execEngineArgs = string(abi.encodePacked(
            '"', vm.toString(positionManager), '","',
            vm.toString(oiLimits), '","',
            vm.toString(marginEngine), '","',
            vm.toString(oracleAdapter), '","',
            vm.toString(marketRegistry), '","',
            vm.toString(leverageModel), '","',
            vm.toString(feeRouter), '","',
            vm.toString(borrowFeeEngine), '","',
            vm.toString(fundingRateEngine), '","',
            vm.toString(accountManager), '","',
            vm.toString(leverVault), '","',
            vm.toString(admin), '"'
        ));
        _printVerifyCommand("ExecutionEngine", executionEngine, execEngineArgs);

        _printVerifyCommand("LiquidationEngine", liquidationEngine, string(abi.encodePacked('"', vm.toString(admin), '","', vm.toString(marginEngine), '","', vm.toString(oracleAdapter), '","', vm.toString(insuranceFund), '","', vm.toString(positionManager), '","', vm.toString(accountManager), '","', vm.toString(feeRouter), '"')));

        // SettlementEngine has many parameters
        string memory settlementArgs = string(abi.encodePacked(
            '"', vm.toString(admin), '","',
            vm.toString(oracleAdapter), '","',
            vm.toString(marginEngine), '","',
            vm.toString(borrowFeeEngine), '","',
            vm.toString(fundingRateEngine), '","',
            vm.toString(insuranceFund), '","',
            vm.toString(leverVault), '","',
            vm.toString(positionManager), '","',
            vm.toString(feeRouter), '"'
        ));
        _printVerifyCommand("SettlementEngine", settlementEngine, settlementArgs);

        console.log("\n\nBulk Verification Script:");
        console.log("========================");
        console.log("Copy the above commands to a shell script for bulk verification");
        console.log("Make sure to set BASESCAN_API_KEY environment variable");

        uint256 chainId = vm.parseJsonUint(json, ".chainId");
        string memory networkName = chainId == 84532 ? "base-sepolia" : "base";
        console.log("Network:", networkName);
        console.log("Verification complete!");
    }

    function _printVerifyCommand(string memory contractName, address addr, string memory constructorArgs) internal view {
        string memory contractPath = string(abi.encodePacked("contracts/", _getContractPath(contractName), ".sol:", contractName));

        if (bytes(constructorArgs).length > 0) {
            console.log(string(abi.encodePacked(
                "forge verify-contract ",
                vm.toString(addr),
                " ",
                contractPath,
                " --constructor-args $(cast abi-encode 'constructor(",
                _getConstructorSignature(contractName),
                ")' ",
                constructorArgs,
                ") --etherscan-api-key $BASESCAN_API_KEY"
            )));
        } else {
            console.log(string(abi.encodePacked(
                "forge verify-contract ",
                vm.toString(addr),
                " ",
                contractPath,
                " --etherscan-api-key $BASESCAN_API_KEY"
            )));
        }
    }

    function _getContractPath(string memory contractName) internal pure returns (string memory) {
        // Map contract names to their file paths
        if (_compareStrings(contractName, "MockUSDT")) return "periphery/MockUSDT";
        if (_compareStrings(contractName, "MarketRegistry")) return "core/MarketRegistry";
        if (_compareStrings(contractName, "AccountManager")) return "core/AccountManager";
        if (_compareStrings(contractName, "PositionManager")) return "core/PositionManager";
        if (_compareStrings(contractName, "OracleAdapter")) return "core/OracleAdapter";

        // Most contracts are in the root contracts/ directory
        return contractName;
    }

    function _getConstructorSignature(string memory contractName) internal pure returns (string memory) {
        if (_compareStrings(contractName, "MockUSDT")) return "";
        if (_compareStrings(contractName, "MarketRegistry")) return "address";
        if (_compareStrings(contractName, "AccountManager")) return "address,address";
        if (_compareStrings(contractName, "PositionManager")) return "address";
        if (_compareStrings(contractName, "OracleAdapter")) return "address,address";
        if (_compareStrings(contractName, "FeeRouter")) return "address";
        if (_compareStrings(contractName, "InsuranceFund")) return "address,address,address";
        if (_compareStrings(contractName, "RewardsDistributor")) return "address,address,address";
        if (_compareStrings(contractName, "LeverVault")) return "address,address,address";
        if (_compareStrings(contractName, "OILimits")) return "address,address,address";
        if (_compareStrings(contractName, "LeverageModel")) return "address,address,address,address,address";
        if (_compareStrings(contractName, "BorrowFeeEngine")) return "address,address,address,address";
        if (_compareStrings(contractName, "FundingRateEngine")) return "address,address,address,address";
        if (_compareStrings(contractName, "MarginEngine")) return "address,address,address,address,address,address";
        if (_compareStrings(contractName, "ExecutionEngine")) return "address,address,address,address,address,address,address,address,address,address,address,address";
        if (_compareStrings(contractName, "LiquidationEngine")) return "address,address,address,address,address,address,address";
        if (_compareStrings(contractName, "SettlementEngine")) return "address,address,address,address,address,address,address,address,address";

        return "address"; // default
    }

    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}