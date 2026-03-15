// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Pool & Fee contracts
import { FeeRouter } from "../contracts/FeeRouter.sol";
import { InsuranceFund } from "../contracts/InsuranceFund.sol";
import { LeverVault } from "../contracts/LeverVault.sol";
import { RewardsDistributor } from "../contracts/RewardsDistributor.sol";

/// @title DeployPool — LP Pool & Fee routing deployment (Phase 2)
/// @notice Deploys LeverVault, RewardsDistributor, InsuranceFund, FeeRouter
/// @dev Handles circular dependencies via placeholder approach
///      Usage: forge script script/DeployPool.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
contract DeployPool is Script {

    struct PoolAddresses {
        address leverVault;
        address rewardsDistributor;
        address insuranceFund;
        address feeRouter;
    }

    function run() external returns (PoolAddresses memory addresses) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address protocolTreasury = vm.envOr("PROTOCOL_TREASURY", deployer);

        console.log("=== LEVER Pool Deployment (Phase 2) ===");
        console.log("Deployer:", deployer);
        console.log("Protocol Treasury:", protocolTreasury);

        // Load core addresses
        string memory coreConfigPath = vm.envOr("CORE_CONFIG", string("core-deployment.json"));
        string memory coreJson = vm.readFile(coreConfigPath);
        address usdt = vm.parseJsonAddress(coreJson, ".usdt");

        console.log("Using USDT from core:", usdt);

        vm.startBroadcast(deployerPrivateKey);

        // Solve circular dependency: LeverVault needs RewardsDistributor, RewardsDistributor needs LeverVault
        console.log("Solving LeverVault <-> RewardsDistributor circular dependency...");

        // Step 1: Deploy placeholder RewardsDistributor
        address placeholderVault = address(0x1111111111111111111111111111111111111111);
        address placeholderRewards = address(new RewardsDistributor(deployer, usdt, placeholderVault));
        console.log("Placeholder RewardsDistributor:", placeholderRewards);

        // Step 2: Deploy LeverVault with placeholder
        addresses.leverVault = address(new LeverVault(deployer, usdt, placeholderRewards));
        console.log("LeverVault deployed:", addresses.leverVault);

        // Step 3: Deploy real RewardsDistributor
        addresses.rewardsDistributor = address(new RewardsDistributor(deployer, usdt, addresses.leverVault));
        console.log("Real RewardsDistributor deployed:", addresses.rewardsDistributor);

        // Step 4: Deploy InsuranceFund
        addresses.insuranceFund = address(new InsuranceFund(deployer, usdt, addresses.leverVault));
        console.log("InsuranceFund deployed:", addresses.insuranceFund);

        // Step 5: Deploy FeeRouter
        addresses.feeRouter = address(new FeeRouter(
            deployer,
            usdt,
            addresses.insuranceFund,
            addresses.rewardsDistributor,
            protocolTreasury
        ));
        console.log("FeeRouter deployed:", addresses.feeRouter);

        vm.stopBroadcast();

        _savePoolConfig(addresses);

        console.log("=== Pool Deployment Complete ===");
        console.log("WARNING: LeverVault internally points to placeholder RewardsDistributor");
        console.log("This is a design limitation requiring manual intervention if needed");

        _logAddresses(addresses);
        return addresses;
    }

    function _savePoolConfig(PoolAddresses memory addr) internal {
        string memory config = string(abi.encodePacked(
            '{\n',
            '  "leverVault": "', vm.toString(addr.leverVault), '",\n',
            '  "rewardsDistributor": "', vm.toString(addr.rewardsDistributor), '",\n',
            '  "insuranceFund": "', vm.toString(addr.insuranceFund), '",\n',
            '  "feeRouter": "', vm.toString(addr.feeRouter), '"\n',
            '}'
        ));

        vm.writeFile("pool-deployment.json", config);
        console.log("Pool deployment config saved to pool-deployment.json");
    }

    function _logAddresses(PoolAddresses memory addr) internal view {
        console.log("LeverVault:        ", addr.leverVault);
        console.log("RewardsDistributor:", addr.rewardsDistributor);
        console.log("InsuranceFund:     ", addr.insuranceFund);
        console.log("FeeRouter:         ", addr.feeRouter);
    }
}