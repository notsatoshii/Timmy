// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "./contracts/core/PositionManager.sol";

contract CheckPositions is Script {
    function run() external {
        address positionManager = vm.envAddress("POSITION_MANAGER");
        PositionManager pm = PositionManager(positionManager);

        uint256 nextId = pm.nextPositionId();
        console.log("Next position ID:", nextId);

        for (uint256 i = 52; i < nextId && i < 60; i++) {
            try pm.getPosition(i) returns (PositionManager.Position memory pos) {
                uint256 leverageWad = pos.leverage;
                uint256 leverageInteger = leverageWad / 1e18;
                console.log("Position", i);
                console.log("  Leverage (integer part):", leverageInteger);
                console.log("  IsOpen:", pos.isOpen);
                console.log("  Collateral (USDT 6-dec):", pos.collateral);
                console.log("---");
            } catch {
                console.log("Position", i, "does not exist");
            }
        }
    }
}