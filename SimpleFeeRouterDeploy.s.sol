// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/FeeRouter.sol";

/// @notice Simple FeeRouter deployment
contract SimpleFeeRouterDeploy is Script {
    function run() external returns (address) {
        // Get addresses from environment
        address usdt = vm.envAddress("USDT_ADDRESS");
        address insuranceFund = vm.envAddress("INSURANCE_FUND");
        address rewardsDistributor = vm.envAddress("REWARDS_DISTRIBUTOR");
        address borrowFeeEngine = vm.envAddress("BORROW_FEE_ENGINE");
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address liquidationEngine = vm.envAddress("LIQUIDATION_ENGINE");
        address settlementEngine = vm.envAddress("SETTLEMENT_ENGINE");

        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== DEPLOYING FEE ROUTER ===");
        console2.log("Deployer:", deployer);
        console2.log("USDT:", usdt);
        console2.log("Insurance Fund:", insuranceFund);
        console2.log("Rewards Distributor:", rewardsDistributor);
        console2.log("Protocol Treasury (deployer):", deployer);

        vm.startBroadcast();

        // Deploy FeeRouter
        FeeRouter feeRouter = new FeeRouter(
            deployer,           // admin
            usdt,              // USDT token
            insuranceFund,     // Insurance Fund
            rewardsDistributor, // Rewards Distributor
            deployer           // Protocol treasury
        );

        console2.log("FeeRouter deployed at:", address(feeRouter));

        // Grant roles to engine contracts
        feeRouter.grantRole(feeRouter.BORROW_FEE_ENGINE_ROLE(), borrowFeeEngine);
        feeRouter.grantRole(feeRouter.EXECUTION_ENGINE_ROLE(), executionEngine);
        feeRouter.grantRole(feeRouter.LIQUIDATION_ENGINE_ROLE(), liquidationEngine);
        feeRouter.grantRole(feeRouter.SETTLEMENT_ENGINE_ROLE(), settlementEngine);

        console2.log("Roles granted successfully");

        // Test functionality
        uint8 tier = feeRouter.getCurrentTier();
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = feeRouter.getCurrentSplit();

        console2.log("Current tier:", tier);
        console2.log("LP share:", (lpPct * 100) / 1e18, "%");
        console2.log("Protocol share:", (protocolPct * 100) / 1e18, "%");
        console2.log("Insurance share:", (insurancePct * 100) / 1e18, "%");

        vm.stopBroadcast();

        console2.log("=== DEPLOYMENT SUCCESS ===");
        console2.log("Update deploy-env.sh:");
        console2.log("export FEE_ROUTER=", address(feeRouter));

        return address(feeRouter);
    }
}