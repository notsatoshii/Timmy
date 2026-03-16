// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/IAccountManager.sol";
import "../contracts/interfaces/IPositionManager.sol";

contract TestClosePosition is Script {
    function run() external {
        address testWallet = 0xB072263740D7c60f1Aa0BF46e737F83544C7b785;

        IExecutionEngine executionEngine = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
        IAccountManager accountManager = IAccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);
        IPositionManager positionManager = IPositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);

        // Check all positions to find an open one
        console2.log("=== Checking All Positions ===");

        for (uint256 i = 1; i <= 3; i++) {
            try positionManager.getPosition(i) returns (IPositionManager.Position memory pos) {
                console2.log("Position ID:", i);
                console2.log("  Open:", pos.isOpen);
                console2.log("  Owner:", pos.owner);
                if (pos.isOpen && pos.owner == testWallet) {
                    console2.log("Found open position:", i);

                    // Check position details before closing
                    console2.log("=== Position Details Before Close ===");
                    console2.log("Position ID:", pos.id);
                    console2.log("Owner:", pos.owner);
                    console2.log("Market ID (bytes32):");
                    console2.logBytes32(pos.marketId);
                    console2.log("Is Long:", pos.isLong);
                    console2.log("Entry PI:", pos.entryPI);
                    console2.log("Position Size:", pos.positionSize);
                    console2.log("Collateral:", pos.collateral);
                    console2.log("Leverage (WAD):", pos.leverage);

                    // Check AccountManager balance before
                    uint256 balanceBefore = accountManager.getBalance(testWallet);
                    console2.log("=== AccountManager Balance Before Close ===");
                    console2.log("Balance:", balanceBefore);

                    // Close the position
                    console2.log("=== Closing Position ===");
                    console2.log("Position ID:", i);
                    vm.startBroadcast();
                    executionEngine.closePosition(i);
                    vm.stopBroadcast();

                    // Check AccountManager balance after
                    uint256 balanceAfter = accountManager.getBalance(testWallet);
                    console2.log("=== AccountManager Balance After Close ===");
                    console2.log("Balance:", balanceAfter);
                    console2.log("Change:", balanceAfter > balanceBefore ? balanceAfter - balanceBefore : balanceBefore - balanceAfter);
                    console2.log("Gain/Loss:", balanceAfter > balanceBefore ? "GAIN" : "LOSS");

                    // Verify position is closed
                    console2.log("=== Position Status After Close ===");
                    IPositionManager.Position memory closedPos = positionManager.getPosition(i);
                    console2.log("Position Open Status:", closedPos.isOpen);

                    return; // Exit after closing first open position
                }
            } catch {
                console2.log("Position does not exist, ID:", i);
            }
        }

        console2.log("No open positions found for test wallet!");
    }
}