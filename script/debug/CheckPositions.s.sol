// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../contracts/interfaces/IPositionManager.sol";

contract CheckPositions is Script {
    function run() external {
        // Base Sepolia addresses
        address POSITION_MANAGER = 0x25ba54a7b2fBac753B601Da05e3661F2E959510b;

        IPositionManager pm = IPositionManager(POSITION_MANAGER);

        console.log("=== Checking first 10 positions ===");

        for (uint256 i = 1; i <= 10; i++) {
            try pm.getPosition(i) returns (IPositionManager.Position memory pos) {
                console.log("Position", i, ":");
                console.log("  Owner:", pos.owner);
                console.log("  IsLong:", pos.isLong);
                console.log("  Collateral (WAD):", pos.collateral);
                console.log("  Position Size (WAD):", pos.positionSize);
                console.log("  Leverage (WAD):", pos.leverage);
                console.log("  IsOpen:", pos.isOpen);

                // Convert to readable numbers
                uint256 collateralUSDT = pos.collateral / 1e12; // WAD to USDT (6 decimals)
                uint256 notionalUSDT = pos.positionSize / 1e12;
                uint256 leverageReadable = pos.leverage / 1e18; // WAD to readable

                console.log("  Readable: Collateral:", collateralUSDT, "USDT");
                console.log("  Readable: Notional:", notionalUSDT, "USDT");
                console.log("  Readable: Leverage:", leverageReadable, "x");
                console.log("");
            } catch {
                console.log("Position", i, "does not exist");
                break;
            }
        }
    }
}