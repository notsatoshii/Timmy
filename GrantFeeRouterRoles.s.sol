// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/FeeRouter.sol";

/// @notice Grant roles to the deployed FeeRouter
contract GrantFeeRouterRoles is Script {
    function run() external {
        address feeRouterAddr = 0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519;

        address borrowFeeEngine = vm.envAddress("BORROW_FEE_ENGINE");
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address liquidationEngine = vm.envAddress("LIQUIDATION_ENGINE");
        address settlementEngine = vm.envAddress("SETTLEMENT_ENGINE");

        console2.log("=== GRANTING FEE ROUTER ROLES ===");
        console2.log("FeeRouter:", feeRouterAddr);

        vm.startBroadcast();

        // The broadcaster should have admin role
        FeeRouter feeRouter = FeeRouter(feeRouterAddr);

        // First grant admin role to the deployer if not already granted
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        feeRouter.grantRole(0x00, deployer); // DEFAULT_ADMIN_ROLE

        // Then grant engine roles
        feeRouter.grantRole(feeRouter.BORROW_FEE_ENGINE_ROLE(), borrowFeeEngine);
        feeRouter.grantRole(feeRouter.EXECUTION_ENGINE_ROLE(), executionEngine);
        feeRouter.grantRole(feeRouter.LIQUIDATION_ENGINE_ROLE(), liquidationEngine);
        feeRouter.grantRole(feeRouter.SETTLEMENT_ENGINE_ROLE(), settlementEngine);

        // Test the functionality
        uint8 tier = feeRouter.getCurrentTier();
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = feeRouter.getCurrentSplit();

        console2.log("Current tier:", tier);
        console2.log("LP share:", (lpPct * 100) / 1e18, "%");
        console2.log("Protocol share:", (protocolPct * 100) / 1e18, "%");
        console2.log("Insurance share:", (insurancePct * 100) / 1e18, "%");

        vm.stopBroadcast();

        console2.log("=== ROLES GRANTED SUCCESSFULLY ===");
        console2.log("Update deploy-env.sh:");
        console2.log("export FEE_ROUTER=0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519");
    }
}