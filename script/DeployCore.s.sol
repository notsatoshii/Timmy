// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core contracts
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { OracleAdapter } from "../contracts/core/OracleAdapter.sol";
import { AccountManager } from "../contracts/core/AccountManager.sol";
import { PositionManager } from "../contracts/core/PositionManager.sol";

// Mock token for testnet
import { MockUSDT } from "../contracts/periphery/MockUSDT.sol";

/// @title DeployCore — Core LEVER Protocol deployment (Phase 1)
/// @notice Deploys foundation contracts: USDT, MarketRegistry, AccountManager, PositionManager, OracleAdapter
/// @dev Usage:
///   forge script script/DeployCore.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
contract DeployCore is Script {

    struct CoreAddresses {
        address usdt;
        address marketRegistry;
        address oracleAdapter;
        address accountManager;
        address positionManager;
    }

    function run() external returns (CoreAddresses memory addresses) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== LEVER Core Deployment (Phase 1) ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy USDT (Mock or use existing)
        addresses.usdt = _deployOrGetUSDT();

        // Deploy foundation contracts
        addresses.marketRegistry = _deployMarketRegistry(deployer);
        addresses.accountManager = _deployAccountManager(deployer, addresses.usdt);
        addresses.positionManager = _deployPositionManager(deployer);
        addresses.oracleAdapter = _deployOracleAdapter(deployer, addresses.marketRegistry);

        vm.stopBroadcast();

        // Save core deployment config
        _saveCoreConfig(addresses);

        console.log("=== Core Deployment Complete ===");
        _logAddresses(addresses);

        return addresses;
    }

    function _deployOrGetUSDT() internal returns (address) {
        address existingUSDT = vm.envOr("USDT_ADDRESS", address(0));

        if (existingUSDT != address(0)) {
            console.log("Using existing USDT:", existingUSDT);
            return existingUSDT;
        } else {
            console.log("Deploying MockUSDT...");
            MockUSDT mockUSDT = new MockUSDT();
            console.log("MockUSDT deployed:", address(mockUSDT));
            return address(mockUSDT);
        }
    }

    function _deployMarketRegistry(address deployer) internal returns (address) {
        console.log("Deploying MarketRegistry...");
        MarketRegistry registry = new MarketRegistry(deployer);
        console.log("MarketRegistry deployed:", address(registry));
        return address(registry);
    }

    function _deployAccountManager(address deployer, address usdt) internal returns (address) {
        console.log("Deploying AccountManager...");
        AccountManager manager = new AccountManager(deployer, usdt);
        console.log("AccountManager deployed:", address(manager));
        return address(manager);
    }

    function _deployPositionManager(address deployer) internal returns (address) {
        console.log("Deploying PositionManager...");
        PositionManager manager = new PositionManager(deployer);
        console.log("PositionManager deployed:", address(manager));
        return address(manager);
    }

    function _deployOracleAdapter(address deployer, address marketRegistry) internal returns (address) {
        console.log("Deploying OracleAdapter...");
        OracleAdapter oracle = new OracleAdapter(deployer, marketRegistry);
        console.log("OracleAdapter deployed:", address(oracle));
        return address(oracle);
    }

    function _saveCoreConfig(CoreAddresses memory addr) internal {
        string memory config = string(abi.encodePacked(
            '{\n',
            '  "usdt": "', vm.toString(addr.usdt), '",\n',
            '  "marketRegistry": "', vm.toString(addr.marketRegistry), '",\n',
            '  "oracleAdapter": "', vm.toString(addr.oracleAdapter), '",\n',
            '  "accountManager": "', vm.toString(addr.accountManager), '",\n',
            '  "positionManager": "', vm.toString(addr.positionManager), '"\n',
            '}'
        ));

        vm.writeFile("core-deployment.json", config);
        console.log("Core deployment config saved to core-deployment.json");
    }

    function _logAddresses(CoreAddresses memory addr) internal view {
        console.log("USDT:           ", addr.usdt);
        console.log("MarketRegistry: ", addr.marketRegistry);
        console.log("OracleAdapter:  ", addr.oracleAdapter);
        console.log("AccountManager: ", addr.accountManager);
        console.log("PositionManager:", addr.positionManager);
    }
}