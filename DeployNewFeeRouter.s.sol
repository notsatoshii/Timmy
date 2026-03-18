// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/FeeRouter.sol";

/// @notice Deploy new FeeRouter pointing to the fixed InsuranceFund
contract DeployNewFeeRouter is Script {
    function run() external {
        // Load addresses
        address usdt = vm.envAddress("USDT_ADDRESS");
        address newInsuranceFund = vm.envAddress("INSURANCE_FUND");  // Now points to fixed version
        address rewardsDistributor = vm.envAddress("REWARDS_DISTRIBUTOR");
        address borrowFeeEngine = vm.envAddress("BORROW_FEE_ENGINE");
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address liquidationEngine = vm.envAddress("LIQUIDATION_ENGINE");
        address settlementEngine = vm.envAddress("SETTLEMENT_ENGINE");
        address oldFeeRouter = vm.envAddress("FEE_ROUTER");

        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        console2.log("=== DEPLOYING NEW FEE ROUTER ===");
        console2.log("Deployer:", deployer);
        console2.log("USDT:", usdt);
        console2.log("Fixed InsuranceFund:", newInsuranceFund);
        console2.log("RewardsDistributor:", rewardsDistributor);
        console2.log("Protocol Treasury:", deployer); // Using deployer as treasury
        console2.log("Old FeeRouter:", oldFeeRouter);
        console2.log("");

        vm.startBroadcast();

        // 1. Deploy new FeeRouter
        console2.log("=== DEPLOYING NEW FEE ROUTER ===");
        FeeRouter newFeeRouter = new FeeRouter(
            deployer,               // admin
            usdt,                  // USDT token
            newInsuranceFund,      // Fixed InsuranceFund
            rewardsDistributor,    // RewardsDistributor
            deployer               // Protocol treasury (using deployer)
        );

        console2.log("New FeeRouter deployed at:", address(newFeeRouter));

        // 2. Grant necessary roles to engine contracts
        console2.log("");
        console2.log("=== GRANTING ROLES ===");

        console2.log("Granting BORROW_FEE_ENGINE_ROLE to:", borrowFeeEngine);
        newFeeRouter.grantRole(newFeeRouter.BORROW_FEE_ENGINE_ROLE(), borrowFeeEngine);

        console2.log("Granting EXECUTION_ENGINE_ROLE to:", executionEngine);
        newFeeRouter.grantRole(newFeeRouter.EXECUTION_ENGINE_ROLE(), executionEngine);

        console2.log("Granting LIQUIDATION_ENGINE_ROLE to:", liquidationEngine);
        newFeeRouter.grantRole(newFeeRouter.LIQUIDATION_ENGINE_ROLE(), liquidationEngine);

        console2.log("Granting SETTLEMENT_ENGINE_ROLE to:", settlementEngine);
        newFeeRouter.grantRole(newFeeRouter.SETTLEMENT_ENGINE_ROLE(), settlementEngine);

        // 3. Test the connection to new InsuranceFund
        console2.log("");
        console2.log("=== TESTING NEW FEE ROUTER ===");

        uint8 tier = newFeeRouter.getCurrentTier();
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = newFeeRouter.getCurrentSplit();

        console2.log("Current tier:", tier);
        console2.log("Fee split:");
        console2.log("  LP:", (lpPct * 100) / 1e18, "%");
        console2.log("  Protocol:", (protocolPct * 100) / 1e18, "%");
        console2.log("  Insurance:", (insurancePct * 100) / 1e18, "%");

        // 4. Check if insurance fund is properly connected
        address connected = address(newFeeRouter.insuranceFund());
        if (connected == newInsuranceFund) {
            console2.log("SUCCESS: FeeRouter properly connected to fixed InsuranceFund");
        } else {
            console2.log("ERROR: FeeRouter connected to wrong insurance fund");
            console2.log("  Expected:", newInsuranceFund);
            console2.log("  Actual:", connected);
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== NEXT STEPS ===");
        console2.log("1. Update deploy-env.sh with new FeeRouter address:");
        console2.log("   export FEE_ROUTER=", address(newFeeRouter));
        console2.log("");
        console2.log("2. Update engine contracts to use new FeeRouter:");
        console2.log("   - BorrowFeeEngine needs FeeRouter address updated");
        console2.log("   - ExecutionEngine needs FeeRouter address updated");
        console2.log("   - LiquidationEngine needs FeeRouter address updated");
        console2.log("   - SettlementEngine needs FeeRouter address updated");
        console2.log("");
        console2.log("3. Run health check to verify everything works");
        console2.log("");
        console2.log("IMPORTANT: The old FeeRouter is now obsolete.");
        console2.log("Make sure to update all references to use the new address.");
    }
}