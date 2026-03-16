// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/interfaces/IExecutionEngine.sol";
import "../contracts/interfaces/IPositionManager.sol";
import "../contracts/interfaces/IAccountManager.sol";
import "../contracts/libraries/FixedPointMath.sol";

contract ClosePositionTest is Script {
    using FixedPointMath for uint256;

    IExecutionEngine constant executionEngine = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IPositionManager constant positionManager = IPositionManager(0x25ba54a7b2fBac753B601Da05e3661F2E959510b);
    IAccountManager constant accountManager = IAccountManager(0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684);

    function run() external {
        string memory keyStr = vm.envString("TEST_WALLET_KEY");
        uint256 privateKey = vm.parseUint(string.concat("0x", keyStr));
        address testWallet = vm.addr(privateKey);

        console.log("Test wallet address:", testWallet);
        console.log("Closing Position ID 1...");

        // Get position details before closing
        IPositionManager.Position memory position = positionManager.getPosition(1);
        console.log("Position owner:", position.owner);
        console.log("Market ID:", vm.toString(position.marketId));
        console.log("Direction (isLong):", position.isLong);
        console.log("Collateral:", position.collateral);
        console.log("Entry price:", position.entryPrice);
        console.log("Leverage:", position.leverage);
        console.log("Position is open:", position.isOpen);

        // Get balance before closing
        uint256 balanceBefore = accountManager.getBalance(testWallet);
        console.log("AccountManager balance before:", balanceBefore);

        vm.startBroadcast(privateKey);

        // Close the position
        executionEngine.closePosition(1);

        vm.stopBroadcast();

        // Get balance after closing
        uint256 balanceAfter = accountManager.getBalance(testWallet);
        console.log("AccountManager balance after:", balanceAfter);

        int256 balanceChange = int256(balanceAfter) - int256(balanceBefore);
        console.log("Balance change (collateral + PnL):", balanceChange);

        // Verify position is closed
        IPositionManager.Position memory closedPosition = positionManager.getPosition(1);
        console.log("Position is open after close (should be false):", closedPosition.isOpen);

        console.log("Close position test completed successfully!");
    }
}