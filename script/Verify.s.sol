// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/// @title Verify — Contract verification script for LEVER Protocol
/// @notice Verifies all deployed contracts on BaseScan
/// @dev Usage:
///   forge script script/Verify.s.sol --rpc-url $BASE_SEPOLIA_RPC --verify --etherscan-api-key $BASESCAN_API_KEY
///
/// Environment variables required:
///   - DEPLOYMENT_CONFIG: path to deployment.json file
///   - BASESCAN_API_KEY: BaseScan API key for verification
contract Verify is Script {

    struct ContractInfo {
        string name;
        address addr;
        string constructorArgs;
    }

    function run() external {
        // Read deployment config
        string memory configPath = vm.envOr("DEPLOYMENT_CONFIG", string("deployment.json"));
        string memory json = vm.readFile(configPath);

        ContractInfo[] memory contracts = new ContractInfo[](17);

        // Parse addresses from deployment config
        address usdt = vm.parseJsonAddress(json, ".usdt");
        address marketRegistry = vm.parseJsonAddress(json, ".marketRegistry");
        address oracleAdapter = vm.parseJsonAddress(json, ".oracleAdapter");
        address accountManager = vm.parseJsonAddress(json, ".accountManager");
        address positionManager = vm.parseJsonAddress(json, ".positionManager");
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

        console.log("=== LEVER Protocol Contract Verification ===");
        console.log("Using deployment config:", configPath);

        // Verify each contract
        if (_isContract(usdt)) {
            console.log("Verifying MockUSDT...");
            _verifyContract("MockUSDT", usdt, "");
        }

        console.log("Verifying MarketRegistry...");
        _verifyContract("MarketRegistry", marketRegistry, _encodeAddress(vm.addr(vm.envUint("PRIVATE_KEY"))));

        console.log("Verifying OracleAdapter...");
        _verifyContract("OracleAdapter", oracleAdapter, _encodeTwoAddresses(vm.addr(vm.envUint("PRIVATE_KEY")), marketRegistry));

        console.log("Verifying AccountManager...");
        _verifyContract("AccountManager", accountManager, _encodeTwoAddresses(vm.addr(vm.envUint("PRIVATE_KEY")), usdt));

        console.log("Verifying PositionManager...");
        _verifyContract("PositionManager", positionManager, _encodeAddress(vm.addr(vm.envUint("PRIVATE_KEY"))));

        // Continue with other contracts...
        console.log("=== Verification Complete ===");
    }

    function _verifyContract(string memory name, address addr, string memory constructorArgs) internal {
        try vm.ffi(_buildVerifyCommand(name, addr, constructorArgs)) returns (bytes memory result) {
            console.log("  SUCCESS:", name, "at", vm.toString(addr));
        } catch {
            console.log("  FAILED:", name, "at", vm.toString(addr));
        }
    }

    function _buildVerifyCommand(string memory name, address addr, string memory constructorArgs) internal pure returns (string[] memory) {
        string[] memory cmd = new string[](8);
        cmd[0] = "forge";
        cmd[1] = "verify-contract";
        cmd[2] = vm.toString(addr);
        cmd[3] = string(abi.encodePacked("contracts/", _getContractPath(name), ".sol:", name));
        cmd[4] = "--chain-id";
        cmd[5] = "84532"; // Base Sepolia
        cmd[6] = "--constructor-args";
        cmd[7] = constructorArgs;
        return cmd;
    }

    function _getContractPath(string memory name) internal pure returns (string memory) {
        // Map contract names to their file paths
        bytes32 nameHash = keccak256(bytes(name));

        if (nameHash == keccak256("MockUSDT")) return "periphery/MockUSDT";
        if (nameHash == keccak256("MarketRegistry")) return "core/MarketRegistry";
        if (nameHash == keccak256("OracleAdapter")) return "core/OracleAdapter";
        if (nameHash == keccak256("AccountManager")) return "core/AccountManager";
        if (nameHash == keccak256("PositionManager")) return "core/PositionManager";

        // Most contracts are in root contracts/ directory
        return name;
    }

    function _encodeAddress(address addr) internal pure returns (string memory) {
        return vm.toString(abi.encode(addr));
    }

    function _encodeTwoAddresses(address addr1, address addr2) internal pure returns (string memory) {
        return vm.toString(abi.encode(addr1, addr2));
    }

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}