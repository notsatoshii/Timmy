// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/IPositionManager.sol";
import "../contracts/interfaces/IFeeRouter.sol";
import "../contracts/interfaces/IBorrowFeeEngine.sol";

/// @title TriggerFeeDistribution
/// @notice Close a few positions to trigger borrow fee routing to FeeRouter
contract TriggerFeeDistribution is Script {
    IExecutionEngine constant EXECUTION_ENGINE = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IPositionManager constant POSITION_MANAGER = IPositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    IFeeRouter constant FEE_ROUTER = IFeeRouter(0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F);

    function run() external {
        vm.startBroadcast();

        console.log("=== TRIGGERING FEE DISTRIBUTION ===");

        // Check borrow fees before
        uint256 borrowFeesBefore = FEE_ROUTER.getTotalFeesRouted(IFeeRouter.FeeType.BORROW);
        console.log("Borrow fees routed before:", borrowFeesBefore);

        // Find and close a few open positions
        for (uint256 positionId = 3; positionId <= 10; positionId++) {
            try POSITION_MANAGER.isPositionOpen(positionId) returns (bool isOpen) {
                if (isOpen) {
                    console.log("Closing position", positionId);
                    try EXECUTION_ENGINE.closePosition(positionId) {
                        console.log("  -> Successfully closed position", positionId);
                        break; // Close just one position to test fee routing
                    } catch {
                        console.log("  -> Failed to close position", positionId);
                    }
                }
            } catch {
                console.log("Position", positionId, "does not exist");
            }
        }

        // Check borrow fees after
        uint256 borrowFeesAfter = FEE_ROUTER.getTotalFeesRouted(IFeeRouter.FeeType.BORROW);
        console.log("Borrow fees routed after:", borrowFeesAfter);
        console.log("Fees distributed:", borrowFeesAfter - borrowFeesBefore);

        vm.stopBroadcast();
    }
}