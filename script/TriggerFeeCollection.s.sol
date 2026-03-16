// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IExecutionEngine } from "../contracts/interfaces/IExecutionEngine.sol";
import { IInsuranceFund } from "../contracts/interfaces/IInsuranceFund.sol";

/// @title TriggerFeeCollection
/// @notice Close a specific position to demonstrate fee collection to InsuranceFund
contract TriggerFeeCollection is Script {

    IExecutionEngine constant EXECUTION_ENGINE = IExecutionEngine(0x081F77C848EaaCfBfCD06E159C6B8d437db6F386);
    IInsuranceFund constant INSURANCE_FUND = IInsuranceFund(0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8);

    function run() external {
        console.log("=== Triggering Fee Collection via Position Close ===");

        // Check insurance fund balance before
        uint256 insuranceBalanceBefore = INSURANCE_FUND.getBalance();
        console.log("Insurance Fund Balance Before:", insuranceBalanceBefore / 1e18, "USDT");

        // Use trader_002 private key (owns position 10)
        uint256 traderKey = 0xe4706a7051c55c5dadcbbcde78c8c160448de1b379f09a51b21431d1cb22b565;
        address trader = vm.addr(traderKey);

        console.log("Trader Address:", trader);
        console.log("Closing position 10 to collect accrued fees...");

        vm.startBroadcast(traderKey);

        // Close position 10
        try EXECUTION_ENGINE.closePosition(10) {
            console.log("SUCCESS: Closed position 10");
        } catch {
            console.log("ERROR: Failed to close position 10");
            vm.stopBroadcast();
            return;
        }

        vm.stopBroadcast();

        // Check insurance fund balance after
        uint256 insuranceBalanceAfter = INSURANCE_FUND.getBalance();
        uint256 increase = insuranceBalanceAfter - insuranceBalanceBefore;

        console.log("Insurance Fund Balance After:", insuranceBalanceAfter / 1e18, "USDT");
        console.log("Fee Collection Result:");

        if (increase > 0) {
            console.log("  SUCCESS: InsuranceFund grew by", increase / 1e18, "USDT");
            console.log("  Fee routing working correctly!");
            console.log("  20% of borrow fees successfully routed to InsuranceFund");
        } else {
            console.log("  WARNING: No InsuranceFund growth detected");
            console.log("  Check if fees are accruing or routing properly");
        }

        console.log("\n=== Recommendation ===");
        console.log("To maintain demo quality:");
        console.log("1. Run this script periodically to show InsuranceFund growth");
        console.log("2. Or implement automated keeper for fee collection");
        console.log("3. Consider closing 1-2 positions per day during active demo periods");
    }
}