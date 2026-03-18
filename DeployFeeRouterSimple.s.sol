// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/FeeRouter.sol";

contract DeployFeeRouterSimple is Script {
    function run() external {
        vm.startBroadcast();

        // Load constructor parameters from environment
        address admin = vm.envAddress("DEPLOYER");
        address usdt = vm.envAddress("USDT_ADDRESS");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address rewardsDistributor = vm.envAddress("REWARDS_DISTRIBUTOR");
        address protocolTreasury = admin; // Use deployer as treasury

        console.log("Deploying FeeRouter with:");
        console.log("Admin:", admin);
        console.log("USDT:", usdt);
        console.log("InsuranceFund:", insuranceFund);
        console.log("RewardsDistributor:", rewardsDistributor);
        console.log("ProtocolTreasury:", protocolTreasury);

        FeeRouter feeRouter = new FeeRouter(
            admin,
            usdt,
            insuranceFund,
            rewardsDistributor,
            protocolTreasury
        );

        console.log("FeeRouter deployed at:", address(feeRouter));

        vm.stopBroadcast();
    }
}