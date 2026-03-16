// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../contracts/interfaces/IPositionManager.sol";
import "../../contracts/interfaces/IExecutionEngine.sol";

contract CloseLowLeveragePositions is Script {
    function run() external {
        // Base Sepolia addresses
        address POSITION_MANAGER = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;
        address EXECUTION_ENGINE = 0x081F77C848EaaCfBfCD06E159C6B8d437db6F386;

        IPositionManager pm = IPositionManager(POSITION_MANAGER);
        IExecutionEngine ee = IExecutionEngine(EXECUTION_ENGINE);

        console.log("=== Closing low leverage positions (1x-3x) ===");

        for (uint256 i = 1; i <= 35; i++) {
            try pm.getPosition(i) returns (IPositionManager.Position memory pos) {
                if (pos.isOpen && pos.leverage <= 3e18) { // 3x or lower
                    uint256 leverageReadable = pos.leverage / 1e18;
                    console.log("Closing Position ID:", i);
                    console.log("  Leverage:", leverageReadable);

                    vm.startBroadcast();
                    try ee.closePosition(i) {
                        console.log("  Position closed successfully");
                    } catch Error(string memory reason) {
                        console.log("  Failed to close position:", reason);
                    } catch {
                        console.log("  Failed to close position - unknown error");
                    }
                    vm.stopBroadcast();
                }
            } catch {
                // Position doesn't exist, skip
                break;
            }
        }

        console.log("=== Low leverage position cleanup complete ===");
    }
}