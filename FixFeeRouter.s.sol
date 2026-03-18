// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./contracts/FeeRouter.sol";

/// @notice Fix FeeRouter deployment and roles
contract FixFeeRouter is Script {
    function run() external {
        address newFeeRouter = 0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519;
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        address borrowFeeEngine = vm.envAddress("BORROW_FEE_ENGINE");
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address liquidationEngine = vm.envAddress("LIQUIDATION_ENGINE");
        address settlementEngine = vm.envAddress("SETTLEMENT_ENGINE");

        console2.log("=== FIXING FEE ROUTER ROLES ===");
        console2.log("FeeRouter:", newFeeRouter);
        console2.log("Deployer:", deployer);

        vm.startBroadcast();

        FeeRouter feeRouter = FeeRouter(newFeeRouter);

        // Grant roles to engine contracts
        feeRouter.grantRole(feeRouter.BORROW_FEE_ENGINE_ROLE(), borrowFeeEngine);
        feeRouter.grantRole(feeRouter.EXECUTION_ENGINE_ROLE(), executionEngine);
        feeRouter.grantRole(feeRouter.LIQUIDATION_ENGINE_ROLE(), liquidationEngine);
        feeRouter.grantRole(feeRouter.SETTLEMENT_ENGINE_ROLE(), settlementEngine);

        // Test the FeeRouter
        uint8 tier = feeRouter.getCurrentTier();
        (uint256 lpPct, uint256 protocolPct, uint256 insurancePct) = feeRouter.getCurrentSplit();

        console2.log("Current tier:", tier);
        console2.log("Fee split:");
        console2.log("  LP:", (lpPct * 100) / 1e18, "%");
        console2.log("  Protocol:", (protocolPct * 100) / 1e18, "%");
        console2.log("  Insurance:", (insurancePct * 100) / 1e18, "%");

        vm.stopBroadcast();

        console2.log("=== SUCCESS ===");
        console2.log("FeeRouter is now properly configured!");
        console2.log("");
        console2.log("Update deploy-env.sh:");
        console2.log("export FEE_ROUTER=0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519");
    }
}