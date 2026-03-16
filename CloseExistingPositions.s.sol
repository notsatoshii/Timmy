// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/core/PositionManager.sol";

contract CloseExistingPositions is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address executionEngine = vm.envAddress("EXECUTION_ENGINE");
        address positionManager = vm.envAddress("POSITION_MANAGER");

        PositionManager pm = PositionManager(positionManager);

        vm.startBroadcast(deployerKey);

        // Close positions 30-39 (all have 1-2x leverage)
        for (uint256 i = 30; i < 40; i++) {
            try pm.getPosition(i) returns (PositionManager.Position memory pos) {
                if (pos.isOpen) {
                    console.log("Closing position", i, "with leverage", pos.leverage / 1e18);
                    (bool success,) = executionEngine.call(abi.encodeWithSignature("closePosition(uint256)", i));
                    if (success) {
                        console.log("Successfully closed position", i);
                    } else {
                        console.log("Failed to close position", i);
                    }
                }
            } catch {
                console.log("Position", i, "does not exist");
            }
        }

        vm.stopBroadcast();
    }
}